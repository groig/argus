defmodule Argus.RetentionTest do
  use Argus.DataCase, async: true

  import Argus.WorkspaceFixtures
  import Ecto.Query

  alias Argus.Projects.{ErrorEvent, ErrorOccurrence}
  alias Argus.Repo
  alias Argus.Retention

  setup do
    project = project_fixture(team_fixture())
    %{project: project}
  end

  defp retention_issue(project, fingerprint) do
    now = DateTime.utc_now(:second)

    Repo.insert!(%ErrorEvent{
      project_id: project.id,
      fingerprint: fingerprint,
      title: fingerprint,
      level: :error,
      first_seen_at: now,
      last_seen_at: now,
      occurrence_count: 0,
      status: :unresolved
    })
  end

  defp retention_occurrence(issue, days_ago) do
    Repo.insert!(%ErrorOccurrence{
      project_id: issue.project_id,
      error_event_id: issue.id,
      event_id: Ecto.UUID.generate(),
      timestamp: DateTime.add(DateTime.utc_now(:second), -days_ago, :day),
      raw_payload: %{}
    })
  end

  defp remaining_ages(issue) do
    now = DateTime.utc_now(:second)

    Repo.all(
      from o in ErrorOccurrence,
        where: o.error_event_id == ^issue.id,
        select: o.timestamp,
        order_by: [desc: o.timestamp]
    )
    |> Enum.map(&DateTime.diff(now, &1, :day))
  end

  test "deletes samples older than the age limit", %{project: project} do
    issue = retention_issue(project, "age")
    for days <- [1, 10, 95, 200], do: retention_occurrence(issue, days)

    assert Retention.prune_error_occurrences(occurrence_max_age_days: 90) == 2
    assert remaining_ages(issue) == [1, 10]
  end

  test "always keeps the newest sample of an issue, even if it is old", %{project: project} do
    issue = retention_issue(project, "stale")
    for days <- [120, 300], do: retention_occurrence(issue, days)

    assert Retention.prune_error_occurrences(occurrence_max_age_days: 90) == 1
    assert remaining_ages(issue) == [120]
  end

  test "caps samples per issue, keeping the newest", %{project: project} do
    noisy = retention_issue(project, "noisy")
    quiet = retention_issue(project, "quiet")
    for days <- 1..5, do: retention_occurrence(noisy, days)
    retention_occurrence(quiet, 2)

    assert Retention.prune_error_occurrences(max_occurrences_per_issue: 3) == 2
    assert remaining_ages(noisy) == [1, 2, 3]
    assert remaining_ages(quiet) == [2]
  end

  test "deletes in batches until done", %{project: project} do
    issue = retention_issue(project, "batched")
    for days <- 1..7, do: retention_occurrence(issue, days)

    assert Retention.prune_error_occurrences(max_occurrences_per_issue: 1, batch_size: 2) == 6
    assert remaining_ages(issue) == [1]
  end

  test "never touches issues or their occurrence counts", %{project: project} do
    issue = retention_issue(project, "counted")
    Repo.update_all(from(e in ErrorEvent, where: e.id == ^issue.id), set: [occurrence_count: 42])
    for days <- [100, 200], do: retention_occurrence(issue, days)

    Retention.prune_error_occurrences(occurrence_max_age_days: 90)

    assert %ErrorEvent{occurrence_count: 42} = Repo.get!(ErrorEvent, issue.id)
  end
end
