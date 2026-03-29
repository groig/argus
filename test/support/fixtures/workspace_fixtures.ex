defmodule Argus.WorkspaceFixtures do
  @moduledoc """
  Test helpers for teams, memberships, projects, issues, and logs.
  """

  alias Argus.Accounts.User
  alias Argus.Logs
  alias Argus.Projects
  alias Argus.Teams
  alias Argus.Teams.Team

  import Argus.AccountsFixtures

  def team_fixture(attrs \\ %{}) do
    {:ok, team} =
      attrs
      |> Map.new()
      |> Enum.into(%{name: "Team #{System.unique_integer([:positive])}"})
      |> Teams.create_team()

    team
  end

  def membership_fixture(%Team{} = team, %User{} = user, role \\ :member) do
    {:ok, team_member} = Teams.add_member(team, user, role)
    team_member
  end

  def project_fixture(team \\ team_fixture(), attrs \\ %{}) do
    {:ok, project} =
      attrs
      |> Map.new()
      |> Enum.into(%{name: "Project #{System.unique_integer([:positive])}"})
      |> then(&Projects.create_project(team, &1))

    project
  end

  def workspace_fixture(opts \\ %{}) do
    opts = Map.new(opts)
    user = Map.get(opts, :user, user_fixture())
    role = Map.get(opts, :role, :admin)
    team = Map.get(opts, :team, team_fixture())
    _membership = membership_fixture(team, user, role)
    project = Map.get(opts, :project, project_fixture(team))

    %{user: user, team: team, project: project}
  end

  def issue_fixture(project, attrs \\ %{}) do
    timestamp = DateTime.utc_now(:second)

    issue_attrs =
      attrs
      |> Map.new()
      |> Enum.into(%{
        fingerprint: "RuntimeError|boom|app.ex",
        title: "RuntimeError: boom",
        culprit: "Argus.Worker.perform/1",
        level: :error,
        platform: "elixir",
        sdk: %{"name" => "sentry-elixir"},
        request: %{"url" => "https://example.com/jobs/1"},
        contexts: %{"runtime" => %{"name" => "BEAM"}},
        tags: %{"environment" => "test"},
        extra: %{},
        first_seen_at: timestamp,
        last_seen_at: timestamp,
        occurrence_count: 1,
        status: :unresolved
      })

    occurrence_attrs = %{
      event_id: "evt-#{System.unique_integer([:positive])}",
      timestamp: timestamp,
      request_url: issue_attrs.request["url"],
      user_context: %{"email" => user_fixture().email},
      exception_values: [%{"type" => "RuntimeError", "value" => "boom"}],
      breadcrumbs: [],
      raw_payload: %{"tags" => issue_attrs.tags, "contexts" => issue_attrs.contexts},
      minidump_attachment: nil
    }

    {:ok, %{issue: issue}} =
      Projects.upsert_issue_and_occurrence(project, issue_attrs, occurrence_attrs)

    issue
  end

  def log_fixture(project, attrs \\ %{}) do
    {:ok, log_event} =
      attrs
      |> Map.new()
      |> Enum.into(%{
        level: :info,
        message: "Background job completed",
        timestamp: DateTime.utc_now(:second),
        metadata: %{"attributes" => %{"logger.name" => "Oban"}},
        logger_name: "Oban",
        origin: "auto",
        trace_id: "trace-123",
        span_id: "span-456"
      })
      |> then(&Logs.create_log_event(project, &1))

    log_event
  end
end
