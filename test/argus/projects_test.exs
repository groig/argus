defmodule Argus.ProjectsTest do
  use Argus.DataCase, async: true

  alias Argus.Projects
  alias Argus.Teams

  import Argus.AccountsFixtures
  import Argus.WorkspaceFixtures

  describe "upsert_issue_and_occurrence/3" do
    test "returns created for the first occurrence and reopened for resolved issues" do
      %{project: project} = workspace_fixture()
      first_seen_at = ~U[2026-03-28 22:00:00Z]
      reopened_at = ~U[2026-03-28 22:10:00Z]

      {:ok, %{issue: issue, disposition: :created}} =
        Projects.upsert_issue_and_occurrence(
          project,
          issue_attrs(first_seen_at),
          occurrence_attrs("evt-created", first_seen_at)
        )

      assert issue.status == :unresolved
      assert issue.occurrence_count == 1

      {:ok, resolved_issue} = Projects.update_error_event_status(issue, :resolved)

      {:ok, %{issue: reopened_issue, disposition: :reopened}} =
        Projects.upsert_issue_and_occurrence(
          project,
          issue_attrs(reopened_at),
          occurrence_attrs("evt-reopened", reopened_at)
        )

      assert resolved_issue.status == :resolved
      assert reopened_issue.status == :unresolved
      assert reopened_issue.occurrence_count == 2
      assert reopened_issue.last_seen_at == reopened_at
    end

    test "keeps ignored issues ignored when they appear again" do
      %{project: project} = workspace_fixture()
      first_seen_at = ~U[2026-03-28 22:00:00Z]
      repeated_at = ~U[2026-03-28 22:12:00Z]

      {:ok, %{issue: issue}} =
        Projects.upsert_issue_and_occurrence(
          project,
          issue_attrs(first_seen_at),
          occurrence_attrs("evt-ignored-1", first_seen_at)
        )

      {:ok, ignored_issue} = Projects.update_error_event_status(issue, :ignored)

      {:ok, %{issue: repeated_issue, disposition: :updated}} =
        Projects.upsert_issue_and_occurrence(
          project,
          issue_attrs(repeated_at),
          occurrence_attrs("evt-ignored-2", repeated_at)
        )

      assert ignored_issue.status == :ignored
      assert repeated_issue.status == :ignored
      assert repeated_issue.occurrence_count == 2
    end

    test "returns duplicate without incrementing counts for the same event id" do
      %{project: project} = workspace_fixture()
      timestamp = ~U[2026-03-28 22:00:00Z]

      {:ok, %{issue: issue, disposition: :created}} =
        Projects.upsert_issue_and_occurrence(
          project,
          issue_attrs(timestamp),
          occurrence_attrs("evt-duplicate", timestamp)
        )

      {:ok, %{issue: duplicate_issue, disposition: :duplicate}} =
        Projects.upsert_issue_and_occurrence(
          project,
          issue_attrs(DateTime.add(timestamp, 1, :minute)),
          occurrence_attrs("evt-duplicate", DateTime.add(timestamp, 1, :minute))
        )

      assert duplicate_issue.id == issue.id
      assert duplicate_issue.occurrence_count == 1
      assert duplicate_issue.last_seen_at == issue.last_seen_at
    end
  end

  describe "issue assignment" do
    test "assigns and unassigns an issue to team members only" do
      %{user: actor, team: team, project: project} = workspace_fixture()
      issue = issue_fixture(project)
      assignee = user_fixture()
      outsider = user_fixture()

      membership_fixture(team, assignee)

      {:ok, assigned_issue} = Projects.assign_error_event(actor, issue, assignee.id)
      assert assigned_issue.assignee_id == assignee.id
      assert assigned_issue.assignee.id == assignee.id

      assert {:error, :invalid_assignee} = Projects.assign_error_event(actor, issue, outsider.id)

      {:ok, unassigned_issue} = Projects.unassign_error_event(actor, assigned_issue)
      assert is_nil(unassigned_issue.assignee_id)
      assert is_nil(unassigned_issue.assignee)
    end

    test "unassigns issues when a team member is removed" do
      %{user: actor, team: team, project: project} = workspace_fixture()
      assignee = user_fixture()
      membership_fixture(team, assignee)
      issue = issue_fixture(project)

      {:ok, assigned_issue} = Projects.assign_error_event(actor, issue, assignee.id)

      assert {1, nil} = Teams.remove_member(team, assignee.id)

      reloaded_issue = Projects.get_error_event(project, assigned_issue.id)

      assert is_nil(reloaded_issue.assignee_id)
      assert is_nil(reloaded_issue.assignee)
    end
  end

  describe "occurrence queries" do
    test "lists lightweight occurrence summaries and fetches the selected occurrence separately" do
      %{project: project} = workspace_fixture()
      first_seen_at = ~U[2026-03-28 22:00:00Z]
      latest_seen_at = ~U[2026-03-28 22:10:00Z]

      {:ok, %{issue: _issue}} =
        Projects.upsert_issue_and_occurrence(
          project,
          issue_attrs(first_seen_at),
          occurrence_attrs("evt-first", first_seen_at)
        )

      {:ok, %{issue: issue}} =
        Projects.upsert_issue_and_occurrence(
          project,
          %{issue_attrs(latest_seen_at) | last_seen_at: latest_seen_at},
          occurrence_attrs("evt-latest", latest_seen_at)
        )

      [latest_summary, first_summary] = Projects.list_occurrence_summaries(issue)

      assert latest_summary.event_id == "evt-latest"
      assert first_summary.event_id == "evt-first"
      assert latest_summary.raw_payload == nil
      assert latest_summary.breadcrumbs == []
      assert latest_summary.minidump_attachment == nil

      full_occurrence = Projects.get_occurrence(issue, latest_summary.id)

      assert full_occurrence.event_id == latest_summary.event_id
      assert full_occurrence.raw_payload["request"]["url"] == "https://example.com/jobs/1"
      assert full_occurrence.breadcrumbs == []
    end
  end

  defp issue_attrs(timestamp) do
    %{
      fingerprint: "RuntimeError|boom|billing.jobs.sync",
      title: "RuntimeError: boom",
      culprit: "billing.jobs.sync",
      level: :error,
      platform: "elixir",
      sdk: %{"name" => "sentry-elixir", "version" => "1.0.0"},
      request: %{"url" => "https://example.com/jobs/1"},
      contexts: %{"runtime" => %{"name" => "BEAM"}},
      tags: %{"environment" => "test"},
      extra: %{"job_id" => 1},
      first_seen_at: timestamp,
      last_seen_at: timestamp,
      occurrence_count: 1,
      status: :unresolved
    }
  end

  defp occurrence_attrs(event_id, timestamp) do
    %{
      event_id: event_id,
      timestamp: timestamp,
      request_url: "https://example.com/jobs/1",
      user_context: %{"email" => "ops@example.com"},
      exception_values: [%{"type" => "RuntimeError", "value" => "boom"}],
      breadcrumbs: [],
      raw_payload: %{
        "user" => %{"email" => "ops@example.com"},
        "request" => %{"url" => "https://example.com/jobs/1"}
      },
      minidump_attachment: nil
    }
  end
end
