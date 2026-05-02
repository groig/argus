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
  use ArgusWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Argus.Projects.IssueNotifier
  alias Argus.Projects.Project
  alias Argus.Repo

  import Argus.AccountsFixtures
  import Argus.WorkspaceFixtures

  setup %{conn: conn} do
    previous_config = Application.get_env(:argus, IssueNotifier, [])

    Application.put_env(:argus, IssueNotifier,
      req_options: [plug: {Req.Test, Argus.IssueWebhookStub}]
    )

    on_exit(fn ->
      Application.put_env(:argus, IssueNotifier, previous_config || [])
    end)

    user = user_fixture()
    team = team_fixture()
    _membership = membership_fixture(team, user, :admin)
    project = project_fixture(team, %{"name" => "Payments API"})

    %{conn: log_in_user(conn, user), team: team, project: project}
  end

  test "updates the selected project", %{conn: conn, project: project} do
    {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/settings")

    assert has_element?(
             view,
             "#project-edit-form input[name='project[accent_color]'][value='rose']"
           )

    assert has_element?(view, "[data-copy-toast='DSN copied']")
    assert has_element?(view, "[data-copy-toast='DSN key copied']")

    render_submit(
      form(view, "#project-edit-form", %{
        "project" => %{
          "name" => "Billing API",
          "slug" => "billing-api",
          "accent_color" => "rose",
          "log_limit" => "250"
        }
      })
    )

    updated_project = Repo.get!(Project, project.id)

    assert updated_project.name == "Billing API"
    assert updated_project.slug == "billing-api"
    assert updated_project.accent_color == "rose"
    assert updated_project.log_limit == 250
  end

  test "updates the selected project webhook and sends a test event", %{
    conn: conn,
    project: project
  } do
    test_pid = self()

    Req.Test.stub(Argus.IssueWebhookStub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:webhook_test_request, Jason.decode!(body)})
      Req.Test.json(conn, %{"ok" => true})
    end)

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/settings")

    render_submit(
      form(view, "#project-webhook-form", %{
        "project" => %{
          "webhook_url" => "https://hooks.argus.test/project",
          "webhook_body_template" =>
            ~s({"text":"{{event_label}} for {{project.name}}","url":"{{url}}"})
        }
      })
    )

    updated_project = Repo.get!(Project, project.id)

    assert updated_project.webhook_url == "https://hooks.argus.test/project"
    assert updated_project.webhook_body_template =~ "{{project.name}}"

    render_click(element(view, "#send-project-webhook-test"))

    assert_receive {:webhook_test_request, payload}
    assert payload["text"] == "Test issue webhook for #{project.name}"
    assert payload["url"] =~ "/projects/#{project.slug}/settings"
  end

  test "validates webhook templates before saving", %{conn: conn, project: project} do
    {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/settings")

    html =
      render_change(
        form(view, "#project-webhook-form", %{
          "project" => %{
            "webhook_url" => "https://hooks.argus.test/project",
            "webhook_body_template" => "{"
          }
        })
      )

    assert html =~ "must be valid JSON"
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
