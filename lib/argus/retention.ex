defmodule Argus.Retention do
  @moduledoc """
  Periodically prunes old error occurrence samples.

  Issues (`error_events`) and their `occurrence_count` are never touched; only
  individual samples in `error_occurrences` are deleted when they are older
  than `:occurrence_max_age_days` or beyond the `:max_occurrences_per_issue`
  newest samples of their issue. The newest sample of every issue is always
  kept so an issue page never loses its example.

  Configure with:

      config :argus, Argus.Retention,
        enabled: true,
        interval_ms: :timer.hours(1),
        occurrence_max_age_days: 90,
        max_occurrences_per_issue: 100,
        batch_size: 5_000
  """

  use GenServer

  require Logger

  alias Argus.Repo

  @defaults [
    enabled: true,
    interval_ms: :timer.hours(1),
    initial_delay_ms: :timer.minutes(1),
    occurrence_max_age_days: 90,
    max_occurrences_per_issue: 100,
    batch_size: 5_000
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def config(overrides \\ []) do
    @defaults
    |> Keyword.merge(Application.get_env(:argus, __MODULE__, []))
    |> Keyword.merge(overrides)
  end

  @doc """
  Deletes occurrence samples outside the retention policy, in batches.
  Returns the number of deleted rows.
  """
  def prune_error_occurrences(opts \\ []) do
    config = config(opts)
    cutoff = DateTime.add(DateTime.utc_now(:second), -config[:occurrence_max_age_days], :day)
    prune_batches(cutoff, config[:max_occurrences_per_issue], config[:batch_size], 0)
  end

  defp prune_batches(cutoff, max_per_issue, batch_size, total) do
    %Postgrex.Result{num_rows: deleted} =
      Repo.query!(
        """
        DELETE FROM error_occurrences
        WHERE id IN (
          SELECT id
          FROM (
            SELECT id,
                   timestamp,
                   row_number() OVER (
                     PARTITION BY error_event_id ORDER BY timestamp DESC, id DESC
                   ) AS position
            FROM error_occurrences
          ) ranked
          WHERE position > $1 OR (position > 1 AND timestamp < $2)
          LIMIT $3
        )
        """,
        [max_per_issue, cutoff, batch_size],
        timeout: :timer.minutes(5)
      )

    if deleted < batch_size do
      total + deleted
    else
      prune_batches(cutoff, max_per_issue, batch_size, total + deleted)
    end
  end

  @impl true
  def init(opts) do
    config = config(opts)

    if config[:enabled] do
      schedule(config[:initial_delay_ms])
      {:ok, config}
    else
      :ignore
    end
  end

  @impl true
  def handle_info(:prune, config) do
    try do
      case prune_error_occurrences(config) do
        0 -> :ok
        deleted -> Logger.info("retention: pruned #{deleted} error occurrences")
      end
    rescue
      error -> Logger.error("retention: pruning failed: #{Exception.message(error)}")
    end

    schedule(config[:interval_ms])
    {:noreply, config}
  end

  defp schedule(delay_ms), do: Process.send_after(self(), :prune, delay_ms)
end
