defmodule ArgusWeb.AgentController do
  @moduledoc """
  Markdown API meant for agents.

  Every response is `text/markdown` and links to the next useful request, so an agent can start at
  `/api/v1` and navigate from there. Access matches the token owner's access in the web UI. The
  only write is resolving an issue.
  """

  use ArgusWeb, :controller

  alias Argus.Projects
  alias ArgusWeb.IssueText

  @issue_page %{default: 25, max: 100, full_default: 10, full_max: 25}
  @occurrence_page %{default: 20, max: 100, full_default: 5, full_max: 20}

  def index(conn, _params) do
    markdown(conn, """
    # Argus agent API

    Every response is Markdown. Authenticate with `Authorization: Bearer <token>`. Everything is read-only except resolving an issue.

    ## Endpoints

    - `GET #{url(~p"/api/v1/projects")}` — projects you can access
    - `GET #{url(~p"/api/v1/projects/:slug/issues")}` — issues of a project, newest activity first
      - `status`: `unresolved` (default), `resolved`, `ignored`, `all`
      - `level`: `error`, `warning`, `info`, `all` (default)
      - `q`: search in issue titles
      - `page`, `per_page` (default #{@issue_page.default}, max #{@issue_page.max})
      - `full=true`: include each issue's full text (latest occurrence); `per_page` defaults to #{@issue_page.full_default}, max #{@issue_page.full_max}
    - `GET #{url(~p"/api/v1/projects/:slug/issues/:id")}` — full issue text with the latest occurrence, same as the "Copy issue" button
      - `frames`: `in_app` (default) or `all`
    - `POST #{url(~p"/api/v1/projects/:slug/issues/:id/resolve")}` — mark an issue as resolved; it reopens if it happens again
    - `GET #{url(~p"/api/v1/projects/:slug/issues/:id/occurrences")}` — occurrences of an issue, newest first
      - `page`, `per_page` (default #{@occurrence_page.default}, max #{@occurrence_page.max})
      - `full=true`: include each occurrence's full text; `per_page` defaults to #{@occurrence_page.full_default}, max #{@occurrence_page.full_max}
      - `frames`: `in_app` (default) or `all`
    - `GET #{url(~p"/api/v1/projects/:slug/issues/:id/occurrences/:occurrence_id")}` — full text of one occurrence
      - `frames`: `in_app` (default) or `all`
    """)
  end

  def projects(conn, _params) do
    projects = Projects.list_all_projects_for_user(conn.assigns.current_scope.user)
    stats = Projects.project_stats(projects)

    rows =
      Enum.map(projects, fn project ->
        project_stats = Map.get(stats, project.id, %{})

        "| #{cell(project.name)} | `#{project.slug}` | #{cell(project.team.name)} | " <>
          "#{Map.get(project_stats, :unresolved_count, "-")} | " <>
          "#{url(~p"/api/v1/projects/#{project.slug}/issues")} |"
      end)

    markdown(conn, [
      "# Projects",
      if(rows == [],
        do: "No projects.",
        else:
          Enum.join(
            ["| Name | Slug | Team | Unresolved | Issues |", "|---|---|---|---|---|" | rows],
            "\n"
          )
      )
    ])
  end

  def issues(conn, %{"slug" => slug} = params) do
    with {:ok, project} <- fetch_project(conn, slug) do
      full? = full?(params)
      per_page = per_page(params, @issue_page, full?)

      filters = %{
        "status" => Map.get(params, "status", "unresolved"),
        "level" => Map.get(params, "level", "all"),
        "search" => Map.get(params, "q", "")
      }

      result = Projects.paginate_error_events(project, filters, page(params), per_page)
      frame_mode = frame_mode(params)

      body =
        cond do
          result.entries == [] ->
            "No issues match."

          full? ->
            result.entries
            |> Enum.map(&full_issue_text(project, &1, frame_mode))
            |> Enum.join("\n\n---\n\n")

          true ->
            issue_table(project, result.entries)
        end

      markdown(conn, [
        "# Issues — #{project.name}",
        "Filters: status=#{filters["status"]}, level=#{filters["level"]}" <>
          if(filters["search"] != "", do: ", q=#{filters["search"]}", else: ""),
        body,
        pagination(
          ~p"/api/v1/projects/#{project.slug}/issues",
          params,
          result.page,
          result.total_pages,
          result.total_count,
          "issues"
        )
      ])
    else
      {:error, conn} -> conn
    end
  end

  def issue(conn, %{"slug" => slug, "id" => id} = params) do
    with {:ok, project} <- fetch_project(conn, slug),
         {:ok, issue} <- fetch_issue(project, id) do
      markdown(conn, [
        full_issue_text(project, issue, frame_mode(params)),
        "---\n\nMore occurrences: #{url(~p"/api/v1/projects/#{project.slug}/issues/#{issue.id}/occurrences")}"
      ])
    else
      {:error, conn} -> conn
      :issue_not_found -> not_found(conn, "Issue not found.")
    end
  end

  def resolve(conn, %{"slug" => slug, "id" => id}) do
    with {:ok, project} <- fetch_project(conn, slug),
         {:ok, issue} <- fetch_issue(project, id),
         {:ok, resolved} <-
           Projects.update_error_event_status(conn.assigns.current_scope.user, issue, :resolved) do
      message =
        if issue.status == :resolved,
          do: "Issue #{issue.id} was already resolved.",
          else: "Issue #{issue.id} is now resolved."

      markdown(conn, [
        "# Issue resolved",
        "#{message} It reopens automatically if a new event arrives.",
        "Title: #{resolved.title}",
        "Issue: #{url(~p"/api/v1/projects/#{project.slug}/issues/#{resolved.id}")}"
      ])
    else
      {:error, %Plug.Conn{} = conn} -> conn
      :issue_not_found -> not_found(conn, "Issue not found.")
      {:error, _changeset} -> unprocessable(conn, "The issue could not be resolved.")
    end
  end

  def occurrences(conn, %{"slug" => slug, "id" => id} = params) do
    with {:ok, project} <- fetch_project(conn, slug),
         {:ok, issue} <- fetch_issue(project, id) do
      full? = full?(params)
      per_page = per_page(params, @occurrence_page, full?)
      {occurrences, total_count} = Projects.list_occurrences(issue, page(params), per_page)
      total_pages = max(div(total_count + per_page - 1, per_page), 1)
      frame_mode = frame_mode(params)

      body =
        cond do
          occurrences == [] ->
            "No occurrences on this page."

          full? ->
            occurrences
            |> Enum.map(&IssueText.issue_copy_text(project, issue, &1, frame_mode))
            |> Enum.join("\n\n---\n\n")

          true ->
            occurrence_table(project, issue, occurrences)
        end

      markdown(conn, [
        "# Occurrences — #{issue.title}",
        "Issue: #{url(~p"/api/v1/projects/#{project.slug}/issues/#{issue.id}")}",
        body,
        pagination(
          ~p"/api/v1/projects/#{project.slug}/issues/#{issue.id}/occurrences",
          params,
          min(page(params), total_pages),
          total_pages,
          total_count,
          "occurrences"
        )
      ])
    else
      {:error, conn} -> conn
      :issue_not_found -> not_found(conn, "Issue not found.")
    end
  end

  def occurrence(conn, %{"slug" => slug, "id" => id, "occurrence_id" => occurrence_id} = params) do
    with {:ok, project} <- fetch_project(conn, slug),
         {:ok, issue} <- fetch_issue(project, id),
         {:ok, occurrence_id} <- parse_id(occurrence_id),
         %{} = occurrence <- Projects.get_occurrence(issue, occurrence_id) do
      markdown(conn, IssueText.issue_copy_text(project, issue, occurrence, frame_mode(params)))
    else
      {:error, conn} -> conn
      :issue_not_found -> not_found(conn, "Issue not found.")
      _ -> not_found(conn, "Occurrence not found.")
    end
  end

  defp fetch_project(conn, slug) do
    case Projects.get_project_for_user_by_slug(conn.assigns.current_scope.user, slug) do
      nil -> {:error, not_found(conn, "Project not found.")}
      project -> {:ok, project}
    end
  end

  defp fetch_issue(project, id) do
    with {:ok, id} <- parse_id(id),
         %{} = issue <- Projects.get_error_event(project, id) do
      {:ok, issue}
    else
      _ -> :issue_not_found
    end
  end

  defp full_issue_text(project, issue, frame_mode) do
    occurrence =
      case Projects.list_occurrences(issue, 1, 1) do
        {[occurrence | _], _total} -> occurrence
        _ -> nil
      end

    IssueText.issue_copy_text(project, issue, occurrence, frame_mode)
  end

  defp issue_table(project, issues) do
    rows =
      Enum.map(issues, fn issue ->
        "| #{issue.id} | #{cell(issue.title)} | #{issue.level} | #{issue.status} | " <>
          "#{issue.occurrence_count} | #{IssueText.format_datetime(issue.last_seen_at)} | " <>
          "#{cell(issue.culprit || "-")} | #{url(~p"/api/v1/projects/#{project.slug}/issues/#{issue.id}")} |"
      end)

    Enum.join(
      [
        "| ID | Title | Level | Status | Events | Last seen | Culprit | Details |",
        "|---|---|---|---|---|---|---|---|" | rows
      ],
      "\n"
    )
  end

  defp occurrence_table(project, issue, occurrences) do
    rows =
      Enum.map(occurrences, fn occurrence ->
        "| #{occurrence.id} | #{IssueText.format_datetime(occurrence.timestamp)} | " <>
          "#{cell(occurrence.event_id)} | #{cell(occurrence.request_url || "-")} | " <>
          "#{cell(IssueText.primary_exception_title(occurrence) || "-")} | " <>
          "#{url(~p"/api/v1/projects/#{project.slug}/issues/#{issue.id}/occurrences/#{occurrence.id}")} |"
      end)

    Enum.join(
      [
        "| ID | Timestamp | Event ID | Request URL | Exception | Details |",
        "|---|---|---|---|---|---|" | rows
      ],
      "\n"
    )
  end

  defp pagination(path, params, page, total_pages, total_count, noun) do
    query = Map.drop(params, ["slug", "id", "page"])

    links =
      [
        page > 1 && "Previous: #{page_url(path, query, page - 1)}",
        page < total_pages && "Next: #{page_url(path, query, page + 1)}"
      ]
      |> Enum.filter(& &1)

    Enum.join(["Page #{page} of #{total_pages} (#{total_count} #{noun})" | links], "\n")
  end

  defp page_url(path, query, page) do
    base = String.trim_trailing(url(~p"/"), "/")
    "#{base}#{path}?#{URI.encode_query(Map.put(query, "page", page))}"
  end

  defp markdown(conn, parts) when is_list(parts), do: markdown(conn, Enum.join(parts, "\n\n"))

  defp markdown(conn, body) do
    conn
    |> put_resp_content_type("text/markdown")
    |> send_resp(200, String.trim_trailing(body) <> "\n")
  end

  defp not_found(conn, message) do
    conn
    |> put_resp_content_type("text/markdown")
    |> send_resp(:not_found, "# Not found\n\n#{message}\n")
  end

  defp unprocessable(conn, message) do
    conn
    |> put_resp_content_type("text/markdown")
    |> send_resp(:unprocessable_entity, "# Not updated\n\n#{message}\n")
  end

  # Keeps table rows intact when values contain pipes or newlines.
  defp cell(value) do
    value
    |> to_string()
    |> String.replace("|", "\\|")
    |> String.replace(~r/\s*\n\s*/, " ")
  end

  defp full?(params), do: Map.get(params, "full") in ["true", "1"]

  defp frame_mode(%{"frames" => "all"}), do: "all"
  defp frame_mode(_params), do: "in_app"

  defp page(params), do: positive_int(Map.get(params, "page"), 1)

  defp per_page(params, limits, full?) do
    {default, max} =
      if full?, do: {limits.full_default, limits.full_max}, else: {limits.default, limits.max}

    params |> Map.get("per_page") |> positive_int(default) |> min(max)
  end

  defp positive_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> default
    end
  end

  defp positive_int(_value, default), do: default

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} when int > 0 -> {:ok, int}
      _ -> :error
    end
  end

  defp parse_id(_id), do: :error
end
