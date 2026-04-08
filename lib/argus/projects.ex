defmodule Argus.Projects do
  @moduledoc """
  Projects, grouped issues, raw occurrences, and issue lifecycle behavior.

  Argus models Sentry-style issue tracking with two layers:

  - `ErrorEvent` is the grouped issue users triage
  - `ErrorOccurrence` is the raw captured event users inspect

  The grouped issue keeps the main UI compact. The raw occurrence keeps the full event data needed
  for debugging. This context also owns reopening rules, ignored-state handling, assignment, and
  issue-triggered notifications.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Argus.Accounts.User
  alias Argus.Logs
  alias Argus.Logs.LogEvent
  alias Argus.Projects.IssueNotifier
  alias Argus.Projects.{ErrorEvent, ErrorOccurrence, Project}
  alias Argus.Repo
  alias Argus.Teams

  def subscribe_to_issues(%Project{id: project_id}) do
    Phoenix.PubSub.subscribe(Argus.PubSub, issue_topic(project_id))
  end

  def broadcast_issue({event_name, %ErrorEvent{} = error_event}) do
    Phoenix.PubSub.broadcast(
      Argus.PubSub,
      issue_topic(error_event.project_id),
      {event_name, Repo.preload(error_event, [:project, :assignee], force: true)}
    )
  end

  def list_projects_for_team(%User{} = user, %Teams.Team{id: team_id}) do
    if user.role == :admin or Teams.member_role(user, %Teams.Team{id: team_id}) do
      Repo.all(
        from project in Project,
          where: project.team_id == ^team_id,
          order_by: [asc: project.name],
          preload: [:team]
      )
    else
      []
    end
  end

  def list_all_projects_for_user(%User{role: :admin}) do
    Repo.all(from project in Project, order_by: [asc: project.name], preload: [:team])
  end

  def list_all_projects_for_user(%User{id: user_id}) do
    Repo.all(
      from project in Project,
        join: team in assoc(project, :team),
        join: team_member in assoc(team, :team_members),
        where: team_member.user_id == ^user_id,
        order_by: [asc: team.name, asc: project.name],
        preload: [:team],
        distinct: project.id
    )
  end

  def get_project!(id), do: Repo.get!(Project, id) |> Repo.preload(:team)

  def get_project_by_id_and_dsn_key(project_id, dsn_key) do
    Repo.get_by(Project, id: project_id, dsn_key: dsn_key) |> Repo.preload(:team)
  end

  def get_project_for_user_by_slug(%User{role: :admin}, slug) do
    Repo.get_by(Project, slug: slug) |> Repo.preload(:team)
  end

  def get_project_for_user_by_slug(%User{id: user_id}, slug) do
    Repo.one(
      from project in Project,
        join: team in assoc(project, :team),
        join: team_member in assoc(team, :team_members),
        where: project.slug == ^slug and team_member.user_id == ^user_id,
        preload: [:team]
    )
  end

  def first_project_for_user(%User{} = user) do
    user
    |> list_all_projects_for_user()
    |> List.first()
  end

  def first_project_for_team(%User{} = user, %Teams.Team{} = team) do
    user
    |> list_projects_for_team(team)
    |> List.first()
  end

  def create_project(%Teams.Team{} = team, attrs) do
    attrs =
      attrs
      |> stringify_keys()
      |> Map.put("team_id", team.id)
      |> Map.put_new(
        "slug",
        build_unique_slug(Map.get(attrs, "name") || Map.get(attrs, :name) || "project")
      )
      |> Map.put_new("dsn_key", generate_dsn_key())

    %Project{}
    |> Project.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, project} -> {:ok, Repo.preload(project, :team)}
      error -> error
    end
  end

  def change_project(%Project{} = project, attrs \\ %{}) do
    project
    |> Project.changeset(stringify_keys(attrs))
  end

  def update_project(%Project{} = project, attrs) do
    project
    |> change_project(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated_project} ->
        updated_project = Repo.preload(updated_project, :team)
        _deleted_count = Logs.enforce_project_log_limit(updated_project)
        {:ok, updated_project}

      error ->
        error
    end
  end

  def delete_project(%Project{} = project) do
    Repo.delete(project)
  end

  def project_stats([]), do: %{}

  def project_stats(projects) when is_list(projects) do
    project_ids = Enum.map(projects, & &1.id)

    issue_counts =
      Repo.all(
        from error_event in ErrorEvent,
          where: error_event.project_id in ^project_ids,
          group_by: error_event.project_id,
          select: {error_event.project_id, count(error_event.id)}
      )
      |> Map.new()

    unresolved_counts =
      Repo.all(
        from error_event in ErrorEvent,
          where: error_event.project_id in ^project_ids and error_event.status == :unresolved,
          group_by: error_event.project_id,
          select: {error_event.project_id, count(error_event.id)}
      )
      |> Map.new()

    log_counts =
      Repo.all(
        from log_event in LogEvent,
          where: log_event.project_id in ^project_ids,
          group_by: log_event.project_id,
          select: {log_event.project_id, count(log_event.id)}
      )
      |> Map.new()

    latest_issues =
      Repo.all(
        from error_event in ErrorEvent,
          where: error_event.project_id in ^project_ids,
          order_by: [desc: error_event.last_seen_at, desc: error_event.id],
          select: %{
            project_id: error_event.project_id,
            id: error_event.id,
            title: error_event.title,
            culprit: error_event.culprit,
            level: error_event.level,
            status: error_event.status,
            last_seen_at: error_event.last_seen_at
          }
      )
      |> Enum.reduce(%{}, fn issue, acc ->
        Map.put_new(acc, issue.project_id, issue)
      end)

    Map.new(projects, fn project ->
      {project.id,
       %{
         issue_count: Map.get(issue_counts, project.id, 0),
         unresolved_count: Map.get(unresolved_counts, project.id, 0),
         log_count: Map.get(log_counts, project.id, 0),
         last_issue: Map.get(latest_issues, project.id)
       }}
    end)
  end

  def recent_error_events_for_projects(projects, limit \\ 8)

  def recent_error_events_for_projects([], _limit), do: []

  def recent_error_events_for_projects(projects, limit) when is_list(projects) do
    project_ids = Enum.map(projects, & &1.id)

    Repo.all(
      from error_event in ErrorEvent,
        where: error_event.project_id in ^project_ids,
        order_by: [desc: error_event.last_seen_at, desc: error_event.id],
        limit: ^limit,
        preload: [project: :team, assignee: []]
    )
  end

  def issue_dsn(%Project{} = project) do
    uri = URI.parse(ArgusWeb.Endpoint.url())
    host = uri.host || "localhost"
    port = if uri.port, do: ":#{uri.port}", else: ""
    path = String.trim_trailing(uri.path || "", "/")
    "#{uri.scheme}://#{project.dsn_key}@#{host}#{port}#{path}/#{project.id}"
  end

  def list_error_events(%Project{id: project_id}, filters \\ %{}) do
    search = Map.get(filters, "search", "") |> String.trim()
    level = normalize_level(Map.get(filters, "level"))
    status = normalize_status(Map.get(filters, "status"))

    from(error_event in ErrorEvent, where: error_event.project_id == ^project_id)
    |> maybe_filter_level(level)
    |> maybe_filter_status(status)
    |> maybe_search(search)
    |> order_by([error_event], desc: error_event.last_seen_at, desc: error_event.id)
    |> preload([:assignee])
    |> Repo.all()
  end

  def get_error_event(%Project{id: project_id}, id) do
    Repo.one(
      from error_event in ErrorEvent,
        where: error_event.project_id == ^project_id and error_event.id == ^id,
        preload: [:project, :assignee]
    )
  end

  def list_occurrences(%ErrorEvent{id: error_event_id}, page \\ 1, per_page \\ 20) do
    offset = max(page - 1, 0) * per_page

    occurrences =
      Repo.all(
        from error_occurrence in ErrorOccurrence,
          where: error_occurrence.error_event_id == ^error_event_id,
          order_by: [desc: error_occurrence.timestamp, desc: error_occurrence.id],
          offset: ^offset,
          limit: ^per_page
      )

    total_count =
      Repo.aggregate(
        from(error_occurrence in ErrorOccurrence,
          where: error_occurrence.error_event_id == ^error_event_id
        ),
        :count,
        :id
      )

    {occurrences, total_count}
  end

  def list_occurrence_summaries(%ErrorEvent{id: error_event_id}) do
    Repo.all(
      from error_occurrence in ErrorOccurrence,
        where: error_occurrence.error_event_id == ^error_event_id,
        order_by: [desc: error_occurrence.timestamp, desc: error_occurrence.id],
        select:
          struct(error_occurrence, [
            :id,
            :event_id,
            :timestamp,
            :request_url,
            :user_context,
            :exception_values
          ])
    )
  end

  def get_occurrence(%ErrorEvent{id: error_event_id}, occurrence_id) do
    Repo.one(
      from error_occurrence in ErrorOccurrence,
        where:
          error_occurrence.error_event_id == ^error_event_id and
            error_occurrence.id == ^occurrence_id
    )
  end

  def list_all_occurrences(%ErrorEvent{id: error_event_id}) do
    Repo.all(
      from error_occurrence in ErrorOccurrence,
        where: error_occurrence.error_event_id == ^error_event_id,
        order_by: [desc: error_occurrence.timestamp, desc: error_occurrence.id]
    )
  end

  def aggregate_tags(%ErrorEvent{id: error_event_id}) do
    Repo.all(
      from error_occurrence in ErrorOccurrence,
        where: error_occurrence.error_event_id == ^error_event_id,
        select: error_occurrence.raw_payload
    )
    |> Enum.reduce(%{}, fn occurrence, acc ->
      occurrence
      |> Map.get("tags", %{})
      |> Enum.reduce(acc, fn {key, value}, outer_acc ->
        value = normalize_tag_value(value)
        key_counts = Map.get(outer_acc, key, %{})
        count = Map.get(key_counts, value, 0) + 1
        Map.put(outer_acc, key, Map.put(key_counts, value, count))
      end)
    end)
  end

  def context_summary(%ErrorEvent{} = error_event) do
    contexts = error_event.contexts || %{}

    %{
      runtime: contexts["runtime"] || %{},
      os: contexts["os"] || %{},
      browser: contexts["browser"] || %{}
    }
  end

  def update_error_event_status(%ErrorEvent{} = error_event, status) do
    error_event
    |> ErrorEvent.changeset(%{status: status})
    |> Repo.update()
    |> case do
      {:ok, updated_error_event} ->
        updated_error_event =
          Repo.preload(updated_error_event, [:project, :assignee], force: true)

        broadcast_issue({:error_event_updated, updated_error_event})
        {:ok, updated_error_event}

      error ->
        error
    end
  end

  def bulk_update_error_event_status(%Project{id: project_id}, ids, status) do
    ids = Enum.uniq(ids)

    {count, _} =
      Repo.update_all(
        from(error_event in ErrorEvent,
          where: error_event.project_id == ^project_id and error_event.id in ^ids
        ),
        set: [status: status, updated_at: DateTime.utc_now(:second)]
      )

    from(error_event in ErrorEvent,
      where: error_event.project_id == ^project_id and error_event.id in ^ids
    )
    |> Repo.all()
    |> Enum.each(fn error_event -> broadcast_issue({:error_event_updated, error_event}) end)

    count
  end

  def list_assignable_users(%Project{} = project) do
    Repo.all(
      from user in User,
        join: team_member in Teams.TeamMember,
        on: team_member.user_id == user.id,
        where: team_member.team_id == ^project.team_id,
        order_by: [asc: user.name, asc: user.email],
        distinct: user.id
    )
  end

  def assign_error_event(%User{} = actor, %ErrorEvent{} = error_event, assignee_id)
      when is_integer(assignee_id) do
    with {:ok, project} <- fetch_project_for_issue(error_event),
         :ok <- authorize_issue_assignment(actor, project),
         %User{} = assignee <- assignable_user(project, assignee_id) do
      update_issue_assignee(error_event, assignee.id)
    else
      {:error, _reason} = error -> error
      nil -> {:error, :invalid_assignee}
    end
  end

  def unassign_error_event(%User{} = actor, %ErrorEvent{} = error_event) do
    with {:ok, project} <- fetch_project_for_issue(error_event),
         :ok <- authorize_issue_assignment(actor, project) do
      update_issue_assignee(error_event, nil)
    end
  end

  def unassign_error_events_for_team_member(%Teams.Team{} = team, user_id)
      when is_integer(user_id) do
    issue_ids =
      Repo.all(
        from error_event in ErrorEvent,
          join: project in assoc(error_event, :project),
          where: project.team_id == ^team.id and error_event.assignee_id == ^user_id,
          select: error_event.id
      )

    if issue_ids == [] do
      0
    else
      {count, _} =
        Repo.update_all(
          from(error_event in ErrorEvent, where: error_event.id in ^issue_ids),
          set: [assignee_id: nil, updated_at: DateTime.utc_now(:second)]
        )

      from(error_event in ErrorEvent,
        where: error_event.id in ^issue_ids,
        preload: [:project, :assignee]
      )
      |> Repo.all()
      |> Enum.each(fn error_event -> broadcast_issue({:error_event_updated, error_event}) end)

      count
    end
  end

  def upsert_issue_and_occurrence(%Project{} = project, issue_attrs, occurrence_attrs) do
    now = issue_attrs.last_seen_at

    Multi.new()
    |> Multi.run(:existing_occurrence, fn repo, _changes ->
      case repo.get_by(ErrorOccurrence,
             project_id: project.id,
             event_id: occurrence_attrs.event_id
           ) do
        nil -> {:ok, nil}
        occurrence -> {:ok, occurrence}
      end
    end)
    |> Multi.run(:inserted_issue, fn repo, %{existing_occurrence: existing_occurrence} ->
      if existing_occurrence do
        {:ok, nil}
      else
        issue_attrs
        |> Map.put(:project_id, project.id)
        |> Map.put(:inserted_at, now)
        |> Map.put(:updated_at, now)
        |> then(&struct(ErrorEvent, &1))
        |> then(fn error_event ->
          repo.insert(
            error_event,
            on_conflict: :nothing,
            conflict_target: [:project_id, :fingerprint],
            returning: true
          )
        end)
      end
    end)
    |> Multi.run(:base_error_event, fn repo,
                                       %{
                                         existing_occurrence: existing_occurrence,
                                         inserted_issue: inserted_issue
                                       } ->
      cond do
        existing_occurrence ->
          {:ok, repo.get!(ErrorEvent, existing_occurrence.error_event_id)}

        inserted_issue && inserted_issue.id ->
          {:ok, inserted_issue}

        true ->
          error_event =
            repo.one!(
              from error_event in ErrorEvent,
                where:
                  error_event.project_id == ^project.id and
                    error_event.fingerprint == ^issue_attrs.fingerprint,
                lock: "FOR UPDATE"
            )

          {:ok, error_event}
      end
    end)
    |> Multi.run(:occurrence, fn repo,
                                 %{
                                   existing_occurrence: existing_occurrence,
                                   base_error_event: error_event
                                 } ->
      if existing_occurrence do
        {:ok, existing_occurrence}
      else
        occurrence_attrs =
          occurrence_attrs
          |> Map.new()
          |> Map.put(:project_id, project.id)
          |> Map.put(:error_event_id, error_event.id)

        %ErrorOccurrence{}
        |> ErrorOccurrence.changeset(occurrence_attrs)
        |> repo.insert(
          on_conflict: :nothing,
          conflict_target: [:project_id, :event_id],
          returning: true
        )
      end
    end)
    |> Multi.run(:error_event, fn repo,
                                  %{
                                    existing_occurrence: existing_occurrence,
                                    inserted_issue: inserted_issue,
                                    base_error_event: base_error_event,
                                    occurrence: occurrence
                                  } ->
      cond do
        existing_occurrence ->
          {:ok, base_error_event}

        occurrence && occurrence.id == nil ->
          if inserted_issue && inserted_issue.id do
            repo.delete(inserted_issue)
          end

          case repo.get_by(ErrorOccurrence,
                 project_id: project.id,
                 event_id: occurrence_attrs.event_id
               ) do
            %ErrorOccurrence{} = duplicate_occurrence ->
              {:ok, repo.get!(ErrorEvent, duplicate_occurrence.error_event_id)}

            nil ->
              {:ok, base_error_event}
          end

        inserted_issue && inserted_issue.id ->
          {:ok, base_error_event}

        true ->
          update_existing_issue(repo, base_error_event, issue_attrs, now)
      end
    end)
    # Keep the lifecycle outcome explicit so notifications and webhooks can react
    # to created/reopened issues without inferring intent from a mutated status later.
    |> Multi.run(:disposition, fn _repo,
                                  %{
                                    existing_occurrence: existing_occurrence,
                                    inserted_issue: inserted_issue,
                                    base_error_event: base_error_event,
                                    occurrence: occurrence,
                                    error_event: error_event
                                  } ->
      disposition =
        cond do
          existing_occurrence ->
            :duplicate

          occurrence && occurrence.id == nil ->
            :duplicate

          inserted_issue && inserted_issue.id ->
            :created

          base_error_event.status == :resolved and error_event.status == :unresolved ->
            :reopened

          true ->
            :updated
        end

      {:ok, disposition}
    end)
    |> Repo.transact()
    |> case do
      {:ok, %{error_event: error_event, disposition: disposition}} ->
        error_event = Repo.preload(error_event, [:project, :assignee], force: true)

        if disposition != :duplicate do
          broadcast_issue({:error_event_updated, error_event})
        end

        maybe_notify_issue(error_event, disposition)
        {:ok, %{issue: error_event, disposition: disposition}}

      error ->
        error
    end
  end

  defp update_existing_issue(repo, error_event, issue_attrs, now) do
    status =
      case error_event.status do
        :resolved -> :unresolved
        other -> other
      end

    error_event
    |> ErrorEvent.changeset(%{
      title: issue_attrs.title,
      culprit: issue_attrs.culprit,
      level: issue_attrs.level,
      platform: issue_attrs.platform,
      sdk: issue_attrs.sdk,
      request: issue_attrs.request,
      contexts: issue_attrs.contexts,
      tags: issue_attrs.tags,
      extra: issue_attrs.extra,
      last_seen_at: issue_attrs.last_seen_at,
      occurrence_count: error_event.occurrence_count + 1,
      status: status,
      updated_at: now
    })
    |> repo.update()
  end

  defp maybe_notify_issue(error_event, disposition) when disposition in [:created, :reopened] do
    error_event
    |> Repo.preload(assignee: [], project: [team: [team_members: :user]])
    |> IssueNotifier.notify_async(disposition)
  end

  defp maybe_notify_issue(_error_event, _disposition), do: :ok

  defp fetch_project_for_issue(%ErrorEvent{project: %Project{} = project}), do: {:ok, project}

  defp fetch_project_for_issue(%ErrorEvent{project_id: project_id}) do
    case Repo.get(Project, project_id) |> Repo.preload(:team) do
      %Project{} = project -> {:ok, project}
      nil -> {:error, :not_found}
    end
  end

  defp authorize_issue_assignment(%User{role: :admin}, _project), do: :ok

  defp authorize_issue_assignment(%User{} = actor, %Project{} = project) do
    if Teams.member_role(actor, %Teams.Team{id: project.team_id}),
      do: :ok,
      else: {:error, :forbidden}
  end

  defp assignable_user(%Project{team_id: team_id}, assignee_id) do
    Repo.one(
      from user in User,
        join: team_member in Teams.TeamMember,
        on: team_member.user_id == user.id,
        where: team_member.team_id == ^team_id and user.id == ^assignee_id
    )
  end

  defp update_issue_assignee(%ErrorEvent{} = error_event, assignee_id) do
    error_event
    |> ErrorEvent.changeset(%{assignee_id: assignee_id})
    |> Repo.update()
    |> case do
      {:ok, updated_issue} ->
        updated_issue = Repo.preload(updated_issue, [:project, :assignee], force: true)
        broadcast_issue({:error_event_updated, updated_issue})
        {:ok, updated_issue}

      error ->
        error
    end
  end

  defp issue_topic(project_id), do: "project:#{project_id}:issues"

  defp build_unique_slug(name) do
    base =
      name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, "-")
      |> String.trim("-")
      |> case do
        "" -> "project"
        slug -> slug
      end

    Enum.reduce_while(Stream.iterate(0, &(&1 + 1)), base, fn attempt, _acc ->
      slug = if attempt == 0, do: base, else: "#{base}-#{attempt + 1}"

      if Repo.get_by(Project, slug: slug) do
        {:cont, slug}
      else
        {:halt, slug}
      end
    end)
  end

  defp generate_dsn_key do
    18
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp stringify_keys(attrs) do
    Map.new(attrs, fn {key, value} -> {to_string(key), value} end)
  end

  defp maybe_filter_level(query, nil), do: query

  defp maybe_filter_level(query, level),
    do: where(query, [error_event], error_event.level == ^level)

  defp maybe_filter_status(query, nil), do: query

  defp maybe_filter_status(query, status),
    do: where(query, [error_event], error_event.status == ^status)

  defp maybe_search(query, ""), do: query

  defp maybe_search(query, search) do
    where(query, [error_event], ilike(error_event.title, ^"%#{search}%"))
  end

  defp normalize_level("all"), do: nil

  defp normalize_level(level) when level in ~w(error warning info),
    do: String.to_existing_atom(level)

  defp normalize_level(_), do: nil

  defp normalize_status("all"), do: nil

  defp normalize_status(status) when status in ~w(unresolved resolved ignored) do
    String.to_existing_atom(status)
  end

  defp normalize_status(_), do: nil

  defp normalize_tag_value(value) when is_binary(value), do: value
  defp normalize_tag_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_tag_value(value), do: inspect(value)
end
