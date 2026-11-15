defmodule ArgusWeb.AdminLive.EmailDisabledTest do
  # Turns email delivery off through global config.
  use ArgusWeb.ConnCase, async: false

  import Argus.AccountsFixtures
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias Argus.Accounts

  setup do
    disable_email_delivery()
  end

  test "the add user form defaults to setting a password", %{conn: conn} do
    {:ok, view, _html} = conn |> log_in_user(admin_fixture()) |> live(~p"/admin")

    render_click(element(view, "#open-add-user-modal"))

    assert has_element?(view, "#add-user-method-password[checked]")
    assert has_element?(view, "#add-user-password-fields")

    render_change(element(view, "#add-user-form"), %{"user" => %{"method" => "invite"}})

    assert has_element?(view, "#email-disabled-hint")
    assert has_element?(view, "#add-user-submit", "Create invitation link")
  end

  test "invitations show a link to share instead of failing", %{conn: conn} do
    {:ok, view, _html} = conn |> log_in_user(admin_fixture()) |> live(~p"/admin")
    email = unique_user_email()

    render_click(element(view, "#open-add-user-modal"))

    render_submit(element(view, "#add-user-form"), %{
      "user" => %{
        "method" => "invite",
        "name" => "Offline Invitee",
        "email" => email,
        "role" => "member",
        "team_id" => "",
        "team_role" => "member"
      }
    })

    invitation = email |> Accounts.get_user_by_email() |> Accounts.get_pending_invitation()

    assert has_element?(view, "#invite-result-message", "Email delivery is not configured")
    assert has_element?(view, "#invite-result-copy[data-copy-value$='#{invitation.token}']")
    assert_no_email_sent()
  end

  test "the login page points to an admin instead of the reset flow", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/login")

    refute has_element?(view, "#forgot-password-link")
    assert has_element?(view, "#forgot-password-admin-hint")
  end

  test "the reset password page explains that email is off", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/reset-password")

    refute has_element?(view, "#reset-password-form")
    assert has_element?(view, "#reset-password-email-disabled")
  end
end
