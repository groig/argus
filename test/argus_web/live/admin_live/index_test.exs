defmodule ArgusWeb.AdminLive.IndexTest do
  use ArgusWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Argus.Accounts

  import Argus.AccountsFixtures
  import Swoosh.TestAssertions

  test "renders admin dashboard for global admins", %{conn: conn} do
    admin = admin_fixture()

    {:ok, view, _html} =
      conn
      |> log_in_user(admin)
      |> live(~p"/admin")

    assert has_element?(view, "#admin-tabs")
    assert has_element?(view, "#admin-users")
    refute has_element?(view, "#admin-webhook-config")

    render_click(element(view, "#open-invite-modal"))
    assert has_element?(view, "#invite-user-form")

    render_click(element(view, "#open-team-modal"))
    assert has_element?(view, "#team-form")
  end

  test "updates another user's global role from the users table", %{conn: conn} do
    admin = admin_fixture()
    member = user_fixture()

    {:ok, view, _html} =
      conn
      |> log_in_user(admin)
      |> live(~p"/admin")

    render_click(element(view, "button[phx-value-modal='user'][phx-value-id='#{member.id}']"))

    assert has_element?(view, "#user-modal")

    render_change(element(view, "#manage-user-role-form"), %{
      "user_role" => %{"user_id" => Integer.to_string(member.id), "role" => "admin"}
    })

    assert Accounts.get_user!(member.id).role == :admin
  end

  test "resends a pending user's invitation from the user modal", %{conn: conn} do
    admin = admin_fixture()
    invitation = invitation_fixture(admin)
    pending_user = invitation.user
    old_token = invitation.token
    assert_email_sent(fn email -> email.text_body =~ old_token end)

    {:ok, view, _html} =
      conn
      |> log_in_user(admin)
      |> live(~p"/admin")

    render_click(
      element(view, "button[phx-value-modal='user'][phx-value-id='#{pending_user.id}']")
    )

    render_click(element(view, "#resend-user-invitation-#{pending_user.id}"))

    assert Accounts.get_invitation_by_token(old_token) == nil

    assert_email_sent(fn email ->
      email.subject == "You're invited to Argus" and
        Enum.any?(email.to, fn {_name, address} -> address == pending_user.email end) and
        email.text_body =~ "/invitations/"
    end)
  end

  test "deletes another user from the user modal", %{conn: conn} do
    admin = admin_fixture()
    member = user_fixture()

    {:ok, view, _html} =
      conn
      |> log_in_user(admin)
      |> live(~p"/admin")

    render_click(element(view, "button[phx-value-modal='user'][phx-value-id='#{member.id}']"))

    assert has_element?(view, "#delete-user-#{member.id}")

    render_click(element(view, "#delete-user-#{member.id}"))

    assert_raise Ecto.NoResultsError, fn -> Accounts.get_user!(member.id) end
    refute has_element?(view, "#delete-user-#{member.id}")
  end
end
