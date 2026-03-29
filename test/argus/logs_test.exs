defmodule Argus.LogsTest do
  use Argus.DataCase, async: true

  alias Argus.Logs
  alias Argus.Logs.{LogEvent, RateLimiter}
  alias Argus.Repo

  import Argus.WorkspaceFixtures

  describe "create_log_event/3" do
    test "drops excess logs and emits one summary log per suppression episode" do
      project = project_fixture(team_fixture())
      limiter = start_rate_limiter(max_logs: 2, window_seconds: 60)

      assert {:ok, _first} =
               Logs.create_log_event(project, log_attrs("first"), rate_limiter: limiter)

      assert {:ok, _second} =
               Logs.create_log_event(project, log_attrs("second"), rate_limiter: limiter)

      assert {:dropped, :rate_limited} =
               Logs.create_log_event(project, log_attrs("third"), rate_limiter: limiter)

      assert {:dropped, :rate_limited} =
               Logs.create_log_event(project, log_attrs("fourth"), rate_limiter: limiter)

      log_events =
        Repo.all(
          from log_event in LogEvent,
            where: log_event.project_id == ^project.id,
            order_by: [asc: log_event.id]
        )

      assert Enum.map(log_events, & &1.message) == [
               "first",
               "second",
               "Log rate limit exceeded"
             ]

      summary_log = List.last(log_events)

      assert summary_log.level == :warning
      assert summary_log.logger_name == "Argus.LogRateLimiter"
      assert summary_log.origin == "argus.rate_limiter"
      assert summary_log.metadata["kind"] == "rate_limit"
      assert summary_log.metadata["project_id"] == project.id
      assert summary_log.metadata["max_logs"] == 2
      assert summary_log.metadata["window_seconds"] == 60
    end

    test "bypass_rate_limit inserts logs even when the limiter is saturated" do
      project = project_fixture(team_fixture())
      limiter = start_rate_limiter(max_logs: 1, window_seconds: 60)

      assert {:ok, _first} =
               Logs.create_log_event(project, log_attrs("first"), rate_limiter: limiter)

      assert {:dropped, :rate_limited} =
               Logs.create_log_event(project, log_attrs("second"), rate_limiter: limiter)

      assert {:ok, bypassed} =
               Logs.create_log_event(
                 project,
                 log_attrs("bypassed"),
                 rate_limiter: limiter,
                 bypass_rate_limit: true
               )

      assert bypassed.message == "bypassed"

      assert Repo.aggregate(
               from(log_event in LogEvent, where: log_event.project_id == ^project.id),
               :count,
               :id
             ) == 3
    end

    test "keeps only the newest logs up to the project log limit" do
      project = project_fixture(team_fixture(), %{"log_limit" => 2})

      assert {:ok, _first} = Logs.create_log_event(project, log_attrs("first"))
      assert {:ok, _second} = Logs.create_log_event(project, log_attrs("second"))
      assert {:ok, _third} = Logs.create_log_event(project, log_attrs("third"))

      log_events =
        Repo.all(
          from log_event in LogEvent,
            where: log_event.project_id == ^project.id,
            order_by: [asc: log_event.timestamp, asc: log_event.id]
        )

      assert Enum.map(log_events, & &1.message) == ["second", "third"]
    end
  end

  defp start_rate_limiter(config) do
    name = {:global, {__MODULE__, make_ref()}}

    start_supervised!({RateLimiter, name: name, config: Keyword.merge([enabled: true], config)})

    name
  end

  defp log_attrs(message) do
    %{
      level: :info,
      message: message,
      timestamp: ~U[2026-03-28 23:40:00Z],
      metadata: %{"attributes" => %{"logger.name" => "test"}},
      logger_name: "test"
    }
  end
end
