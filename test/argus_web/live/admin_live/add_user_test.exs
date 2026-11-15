defmodule ArgusWeb.AdminLive.AddUserTest do
  use ArgusWeb.ConnCase, async: true

  import Argus.AccountsFixtures
  import Argus.WorkspaceFixtures
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias Argus.{Accounts, Teams}

  setup %{conn: conn} do
    admin = admin_fixture()
    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/admin")
    render_click(element(view, "#open-add-user-modal"))

    %{admin: admin, view: view}
  end

  test "defaults to an invitation link when email is configured", %{view: view} do
    assert has_element?(view, "#add-user-method-invite[checked]")
    refute has_element?(view, "#add-user-password-fields")
    refute has_element?(view, "#email-disabled-hint")
  end

  test "creates an active user with a password and a team", %{view: view} do
    team = team_fixture()
    email = unique_user_email()

    render_change(element(view, "#add-user-form"), %{"user" => %{"method" => "password"}})
    assert has_element?(view, "#add-user-password-fields")

    render_submit(element(view, "#add-user-form"), %{
      "user" => %{
        "method" => "password",
        "name" => "Direct Person",
        "email" => email,
        "role" => "member",
        "password" => "direct-password",
        "password_confirmation" => "direct-password",
        "team_id" => Integer.to_string(team.id),
        "team_role" => "admin"
      }
    })

    refute has_element?(view, "#add-user-modal")

    user = Accounts.get_user_by_email_and_password(email, "direct-password")
    assert user.confirmed_at
    assert Teams.member_role(user, team) == :admin
    assert has_element?(view, "#admin-users td", "Direct Person")
    assert_no_email_sent()
  end

  test "shows password validation errors without creating the user", %{view: view} do
    email = unique_user_email()

    render_submit(element(view, "#add-user-form"), %{
      "user" => %{
        "method" => "password",
        "name" => "Weak Password",
        "email" => email,
        "role" => "member",
        "password" => "short",
        "password_confirmation" => "other",
        "team_id" => "",
        "team_role" => "member"
      }
    })

    assert has_element?(view, "#add-user-form")
    assert has_element?(view, "#add-user-form p", "should be at least 8 character(s)")
    assert has_element?(view, "#add-user-form p", "does not match password")
    refute Accounts.get_user_by_email(email)
  end

  test "invites a user into a team and shows the link to share", %{view: view} do
    team = team_fixture()
    email = unique_user_email()

    render_submit(element(view, "#add-user-form"), %{
      "user" => %{
        "method" => "invite",
        "name" => "Invited Person",
        "email" => email,
        "role" => "member",
        "team_id" => Integer.to_string(team.id),
        "team_role" => "member"
      }
    })

    user = Accounts.get_user_by_email(email)
    invitation = Accounts.get_pending_invitation(user)

    assert has_element?(view, "#invite-result")

    assert has_element?(
             view,
             "#invite-result-copy[data-copy-value$='/invitations/#{invitation.token}']"
           )

    assert has_element?(view, "#invite-result-message", "We emailed the invitation")
    assert Teams.member_role(user, team) == :member
    assert_email_sent(subject: "You're invited to Argus", to: [nil: email])

    render_click(element(view, "#invite-result-done"))
    refute has_element?(view, "#add-user-modal")
  end

  test "keeps the form open with errors for a taken email", %{view: view} do
    existing = user_fixture()

    render_submit(element(view, "#add-user-form"), %{
      "user" => %{
        "method" => "invite",
        "name" => "Duplicate",
        "email" => existing.email,
        "role" => "member",
        "team_id" => "",
        "team_role" => "member"
      }
    })

    assert has_element?(view, "#add-user-form p", "has already been taken")
    refute has_element?(view, "#invite-result")
  end

  test "can start another user after an invitation", %{view: view} do
    render_submit(element(view, "#add-user-form"), %{
      "user" => %{
        "method" => "invite",
        "name" => "First Invitee",
        "email" => unique_user_email(),
        "role" => "member",
        "team_id" => "",
        "team_role" => "member"
      }
    })

    render_click(element(view, "#add-another-user"))

    assert has_element?(view, "#add-user-form")
    refute has_element?(view, "#invite-result")
  end
end
