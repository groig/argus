defmodule Argus.Logs do
  @moduledoc """
  Log storage, querying, and rate-limited live streaming.

  Logs stay chronological. The main extra rule here is rate limiting, which drops excess noise
  when a client starts flooding the system.
  """

  import Ecto.Query, warn: false

  require Logger

  alias Ecto.Multi
  alias Argus.Logs.{LogEvent, RateLimiter}
  alias Argus.Projects.Project
  alias Argus.Repo

  @default_page_size 50

  def subscribe(%Project{id: project_id}) do
    Phoenix.PubSub.subscribe(Argus.PubSub, topic(project_id))
  end

  def unsubscribe(%Project{id: project_id}) do
    Phoenix.PubSub.unsubscribe(Argus.PubSub, topic(project_id))
  end

  def broadcast(%LogEvent{} = log_event) do
    Phoenix.PubSub.broadcast(
      Argus.PubSub,
      topic(log_event.project_id),
      {:log_event_created, log_event}
    )
  end

  def list_log_events(%Project{id: project_id}, filters \\ %{}) do
    %Project{id: project_id}
    |> paginate_log_events(filters)
    |> Map.fetch!(:entries)
  end

  def paginate_log_events(
        %Project{id: project_id},
        filters \\ %{},
        page \\ 1,
        per_page \\ @default_page_size
      ) do
    search = Map.get(filters, "search", "") |> String.trim()
    level = normalize_level(Map.get(filters, "level"))
    page = normalize_page(page)
    per_page = normalize_per_page(per_page, @default_page_size)

    query =
      from(log_event in LogEvent, where: log_event.project_id == ^project_id)
      |> maybe_filter_level(level)
      |> maybe_search(search)

    total_count = Repo.aggregate(query, :count, :id)
    total_pages = max(div(total_count + per_page - 1, per_page), 1)
    page = min(page, total_pages)
    offset = (page - 1) * per_page

    entries =
      query
      |> order_by([log_event], desc: log_event.timestamp, desc: log_event.id)
      |> limit(^per_page)
      |> offset(^offset)
      |> Repo.all()

    %{
      entries: entries,
      page: page,
      per_page: per_page,
      total_count: total_count,
      total_pages: total_pages
    }
  end

  def get_log_event(%Project{id: project_id}, id) do
    Repo.one(
      from log_event in LogEvent,
        where: log_event.project_id == ^project_id and log_event.id == ^id
    )
  end

  def create_log_event(%Project{} = project, attrs, opts \\ []) do
    if opts[:bypass_rate_limit] do
      insert_log_event(project, attrs)
    else
      case RateLimiter.check(project.id, server: Keyword.get(opts, :rate_limiter, RateLimiter)) do
        :allow ->
          insert_log_event(project, attrs)

        {:drop, :rate_limited} ->
          {:dropped, :rate_limited}

        {:drop, summary} ->
          maybe_emit_rate_limit_summary(project, summary, opts)
          {:dropped, :rate_limited}
      end
    end
  end

  def enforce_project_log_limit(%Project{id: project_id} = project) do
    prune_excess_logs(project_id, effective_log_limit(project))
  end

  defp topic(project_id), do: "project:#{project_id}:logs"

  defp insert_log_event(%Project{} = project, attrs) do
    log_limit = effective_log_limit(project)

    Multi.new()
    |> Multi.insert(
      :log_event,
      LogEvent.changeset(%LogEvent{}, Map.put(attrs, :project_id, project.id))
    )
    |> Multi.run(:pruned_log_ids, fn repo, _changes ->
      {:ok, prune_excess_logs(repo, project.id, log_limit)}
    end)
    |> Repo.transact()
    |> case do
      {:ok, %{log_event: log_event, pruned_log_ids: pruned_log_ids}} ->
        if log_event.id not in pruned_log_ids do
          broadcast(log_event)
        end

        {:ok, log_event}

      error ->
        error
    end
  end

  defp prune_excess_logs(project_id, log_limit) do
    prune_excess_logs(Repo, project_id, log_limit)
  end

  defp prune_excess_logs(repo, project_id, log_limit) do
    count =
      repo.aggregate(
        from(log_event in LogEvent, where: log_event.project_id == ^project_id),
        :count,
        :id
      )

    excess = max(count - log_limit, 0)

    if excess == 0 do
      []
    else
      pruned_log_ids =
        repo.all(
          from log_event in LogEvent,
            where: log_event.project_id == ^project_id,
            order_by: [asc: log_event.timestamp, asc: log_event.id],
            limit: ^excess,
            select: log_event.id
        )

      repo.delete_all(from log_event in LogEvent, where: log_event.id in ^pruned_log_ids)
      pruned_log_ids
    end
  end

  defp effective_log_limit(%Project{log_limit: log_limit})
       when is_integer(log_limit) and log_limit > 0,
       do: log_limit

  defp effective_log_limit(_project), do: Project.default_log_limit()

  defp normalize_page(page) when is_integer(page) and page > 0, do: page

  defp normalize_page(page) when is_binary(page) do
    case Integer.parse(page) do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end

  defp normalize_page(_page), do: 1

  defp normalize_per_page(per_page, _default) when is_integer(per_page) and per_page > 0,
    do: per_page

  defp normalize_per_page(per_page, default) when is_binary(per_page) do
    case Integer.parse(per_page) do
      {per_page, ""} when per_page > 0 -> per_page
      _ -> default
    end
  end

  defp normalize_per_page(_per_page, default), do: default

  defp maybe_emit_rate_limit_summary(%Project{} = project, summary, opts) do
    _ =
      create_log_event(project, rate_limit_summary_attrs(project, summary),
        bypass_rate_limit: true,
        rate_limiter: Keyword.get(opts, :rate_limiter, RateLimiter)
      )
      |> case do
        {:ok, _log_event} ->
          :ok

        {:error, reason} ->
          Logger.warning("failed to persist rate limit summary log: #{inspect(reason)}")

        _ ->
          :ok
      end

    :ok
  end

  defp rate_limit_summary_attrs(%Project{} = project, summary) do
    timestamp = summary.suppression_started_at

    %{
      level: :warning,
      message: "Log rate limit exceeded",
      timestamp: timestamp,
      metadata: %{
        "kind" => "rate_limit",
        "project_id" => project.id,
        "max_logs" => summary.max_logs,
        "window_seconds" => summary.window_seconds,
        "suppression_started_at" => DateTime.to_iso8601(timestamp)
      },
      logger_name: "Argus.LogRateLimiter",
      message_template: "Log rate limit exceeded",
      origin: "argus.rate_limiter"
    }
  end

  defp maybe_filter_level(query, nil), do: query
  defp maybe_filter_level(query, level), do: where(query, [log_event], log_event.level == ^level)

  defp maybe_search(query, ""), do: query

  defp maybe_search(query, search) do
    where(query, [log_event], ilike(log_event.message, ^"%#{search}%"))
  end

  defp normalize_level("all"), do: nil

  defp normalize_level(level) when level in ~w(error warning info),
    do: String.to_existing_atom(level)

  defp normalize_level(_), do: nil
end
