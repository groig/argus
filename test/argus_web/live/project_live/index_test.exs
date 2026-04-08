defmodule ArgusWeb.ProjectLive.IndexTest do
  use ArgusWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  import Argus.AccountsFixtures
  import Argus.WorkspaceFixtures

  test "renders the dashboard with project shortcuts and recent issues", %{conn: conn} do
    user = user_fixture()
    team = team_fixture(%{name: "Engineering"})
    _membership = membership_fixture(team, user, :admin)
    project = project_fixture(team, %{"name" => "My First Project"})
    _issue = issue_fixture(project)

    {:ok, view, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/projects")

    assert has_element?(view, "#app-sidebar.sticky.overflow-y-auto")
    assert has_element?(view, "#project-card-#{project.id}")
    assert render(view) =~ "Recent issues"
    assert render(view) =~ "My First Project"
  end

  test "renders the empty state when the active team has no projects", %{conn: conn} do
    user = user_fixture()
    team = team_fixture(%{name: "Ops"})
    _membership = membership_fixture(team, user, :admin)

    {:ok, _view, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/projects?team_id=#{team.id}")

    assert html =~ "No projects yet"
    assert html =~ "Create project"
  end
end
