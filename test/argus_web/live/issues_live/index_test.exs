defmodule ArgusWeb.IssuesLive.IndexTest do
  use ArgusWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Argus.Projects

  import Argus.AccountsFixtures
  import Argus.WorkspaceFixtures

  setup %{conn: conn} do
    user = user_fixture()
    team = team_fixture()
    _membership = membership_fixture(team, user, :admin)
    project = project_fixture(team, %{"name" => "Billing API"})

    %{conn: log_in_user(conn, user), user: user, team: team, project: project}
  end

  test "renders assignee state and filters issues by search", %{
    conn: conn,
    user: user,
    team: team,
    project: project
  } do
    issue = issue_fixture(project, %{title: "Payment provider timeout"})

    _other_issue =
      issue_fixture(project, %{title: "Background job stalled", fingerprint: "other"})

    assignee = user_fixture(%{name: "Casey Operator"})
    membership_fixture(team, assignee)
    {:ok, _assigned_issue} = Projects.assign_error_event(user, issue, assignee.id)

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/issues")

    assert render(view) =~ "Casey Operator"
    assert render(view) =~ "Background job stalled"

    render_change(
      form(view, "#issue-filters", %{
        "filters" => %{"search" => "timeout", "level" => "all", "status" => "all"}
      })
    )

    html = render(view)

    assert html =~ "Payment provider timeout"
    refute html =~ "Background job stalled"
  end

  test "bulk resolves selected issues", %{conn: conn, project: project} do
    issue = issue_fixture(project, %{title: "Database timeout"})

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/issues")

    render_click(element(view, "input[phx-value-id='#{issue.id}']"))
    render_click(element(view, "button[phx-value-status='resolved']"))

    assert Projects.get_error_event(project, issue.id).status == :resolved
  end
end
