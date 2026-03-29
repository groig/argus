defmodule ArgusWeb.TeamLive.SettingsTest do
  use ArgusWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Argus.Projects.Project
  alias Argus.Repo

  import Argus.AccountsFixtures
  import Argus.WorkspaceFixtures

  setup %{conn: conn} do
    user = user_fixture()
    team = team_fixture()
    _membership = membership_fixture(team, user, :admin)
    project = project_fixture(team, %{"name" => "Payments API"})

    %{conn: log_in_user(conn, user), team: team, project: project}
  end

  test "renders tabbed team settings", %{
    conn: conn,
    team: team,
    project: project
  } do
    {:ok, view, _html} = live(conn, ~p"/teams/#{team.id}/settings?tab=projects")

    assert has_element?(view, "#team-projects")
    assert render(view) =~ project.name
  end

  test "creates a project from the modal and navigates to project settings", %{
    conn: conn,
    team: team
  } do
    {:ok, view, _html} = live(conn, ~p"/teams/#{team.id}/settings")

    render_click(element(view, "#open-project-modal"))
    render_submit(form(view, "#project-form", %{"project" => %{"name" => "Ingestion API"}}))

    created_project = Repo.get_by!(Project, name: "Ingestion API")

    assert_redirect(view, ~p"/projects/#{created_project.slug}/settings")
  end
end

defmodule ArgusWeb.ProjectLive.SettingsTest do
  use ArgusWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Argus.Projects.Project
  alias Argus.Repo

  import Argus.AccountsFixtures
  import Argus.WorkspaceFixtures

  setup %{conn: conn} do
    user = user_fixture()
    team = team_fixture()
    _membership = membership_fixture(team, user, :admin)
    project = project_fixture(team, %{"name" => "Payments API"})

    %{conn: log_in_user(conn, user), team: team, project: project}
  end

  test "updates the selected project", %{conn: conn, project: project} do
    {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/settings")

    render_submit(
      form(view, "#project-edit-form", %{
        "project" => %{
          "name" => "Billing API",
          "slug" => "billing-api",
          "log_limit" => "250"
        }
      })
    )

    updated_project = Repo.get!(Project, project.id)

    assert updated_project.name == "Billing API"
    assert updated_project.slug == "billing-api"
    assert updated_project.log_limit == 250
  end

  test "prunes oldest logs when the project log limit is lowered", %{conn: conn, project: project} do
    _first =
      log_fixture(project, %{
        message: "oldest",
        timestamp: ~U[2026-03-31 10:00:00Z]
      })

    _second =
      log_fixture(project, %{
        message: "middle",
        timestamp: ~U[2026-03-31 10:01:00Z]
      })

    _third =
      log_fixture(project, %{
        message: "newest",
        timestamp: ~U[2026-03-31 10:02:00Z]
      })

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/settings")

    render_submit(
      form(view, "#project-edit-form", %{
        "project" => %{
          "name" => project.name,
          "slug" => project.slug,
          "log_limit" => "2"
        }
      })
    )

    remaining_messages =
      Repo.all(
        from log_event in Argus.Logs.LogEvent,
          where: log_event.project_id == ^project.id,
          order_by: [asc: log_event.timestamp, asc: log_event.id],
          select: log_event.message
      )

    assert remaining_messages == ["middle", "newest"]
  end

  test "deletes the selected project", %{conn: conn, team: team, project: project} do
    {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/settings")

    render_click(element(view, "#delete-project-button"))
    assert has_element?(view, "#delete-project-modal")

    render_click(element(view, "#confirm-delete-project"))

    assert_redirect(view, ~p"/teams/#{team.id}/settings?tab=projects")
    assert Repo.get(Project, project.id) == nil
  end
end
