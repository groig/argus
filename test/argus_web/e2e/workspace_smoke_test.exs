defmodule ArgusWeb.E2E.WorkspaceSmokeTest do
  use ArgusWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Argus.Accounts
  alias Argus.Accounts.Invitation
  alias Argus.Projects.Project
  alias Argus.Repo
  alias Argus.Teams

  import Argus.AccountsFixtures
  import Argus.WorkspaceFixtures

  test "admin can onboard a user, create a project, ingest an issue, and the user can see it", %{
    conn: conn
  } do
    admin = admin_fixture(%{name: "Admin Person"})
    team = team_fixture(%{name: "Platform"})
    _membership = membership_fixture(team, admin, :admin)
    invited_email = "newmember@example.com"

    {:ok, admin_view, _html} =
      conn
      |> log_in_user(admin)
      |> live(~p"/admin")

    render_click(element(admin_view, "#open-invite-modal"))

    render_submit(
      form(admin_view, "#invite-user-form", %{
        "user" => %{"name" => "New Member", "email" => invited_email, "role" => "member"}
      })
    )

    invited_user = Accounts.get_user_by_email(invited_email)
    invitation = Repo.get_by!(Invitation, user_id: invited_user.id)

    invited_conn = build_conn()

    {:ok, invitation_view, _html} = live(invited_conn, ~p"/invitations/#{invitation.token}")

    invitation_form =
      form(invitation_view, "#invitation-form", %{
        "user" => %{
          "password" => "changeme123",
          "password_confirmation" => "changeme123"
        }
      })

    invited_conn = submit_form(invitation_form, invited_conn)

    {:ok, team_view, _html} =
      conn
      |> log_in_user(admin)
      |> live(~p"/teams/#{team.id}/settings?tab=users")

    render_submit(
      form(team_view, "#member-form", %{
        "member" => %{"email" => invited_email, "role" => "member"}
      })
    )

    assert Teams.member_role(invited_user, team) == :member

    {:ok, team_projects_view, _html} =
      conn
      |> log_in_user(admin)
      |> live(~p"/teams/#{team.id}/settings?tab=projects")

    render_click(element(team_projects_view, "#open-project-modal"))

    render_submit(
      form(team_projects_view, "#project-form", %{"project" => %{"name" => "Checkout API"}})
    )

    project = Repo.get_by!(Project, name: "Checkout API")

    post(
      build_conn()
      |> put_req_header("content-type", "application/json"),
      ~p"/api/#{project.id}/store/?sentry_key=#{project.dsn_key}",
      Jason.encode!(%{
        "event_id" => "e2e-smoke-event",
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now(:second)),
        "level" => "error",
        "platform" => "python",
        "sdk" => %{"name" => "sentry.python", "version" => "2.54.0"},
        "request" => %{"url" => "http://example.test/checkout"},
        "message" => "Checkout broke",
        "exception" => %{
          "values" => [%{"type" => "RuntimeError", "value" => "Checkout broke"}]
        }
      })
    )

    {:ok, issues_view, _html} = live(invited_conn, ~p"/projects/#{project.slug}/issues")

    assert render(issues_view) =~ "RuntimeError: Checkout broke"
  end
end
