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

    render_click(element(view, "#open-add-user-modal"))
    assert has_element?(view, "#add-user-form")

    render_click(element(view, "#add-user-modal-close"))
    refute has_element?(view, "#add-user-modal")

    render_click(element(view, "#open-team-modal"))
    assert has_element?(view, "#team-form")

    render_click(element(view, "#team-modal-close"))
    refute has_element?(view, "#team-modal")
  end

  test "renders system version details for global admins", %{conn: conn} do
    admin = admin_fixture()

    {:ok, view, _html} =
      conn
      |> log_in_user(admin)
      |> live(~p"/admin?tab=system")

    assert has_element?(view, "#system-version")
    assert has_element?(view, "#system-app-version", to_string(Application.spec(:argus, :vsn)))
    assert has_element?(view, "#system-revision")
  end

  test "redirects members away from the admin panel", %{conn: conn} do
    member = user_fixture()

    assert {:error, {:live_redirect, %{to: "/projects"}}} =
             conn
             |> log_in_user(member)
             |> live(~p"/admin")
  end

  test "an admin demoted while the panel is open can't keep acting from it", %{conn: conn} do
    admin = admin_fixture()
    email = unique_user_email()

    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/admin")
    render_click(element(view, "#open-add-user-modal"))

    {:ok, _demoted} = Accounts.update_user_role(admin, :member)

    assert {:error, {:live_redirect, %{to: "/projects"}}} =
             render_submit(element(view, "#add-user-form"), %{
               "user" => %{
                 "method" => "password",
                 "name" => "Backdoor Admin",
                 "email" => email,
                 "role" => "admin",
                 "password" => "backdoor-password",
                 "password_confirmation" => "backdoor-password",
                 "team_id" => "",
                 "team_role" => "member"
               }
             })

    refute Accounts.get_user_by_email(email)
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
    new_invitation = Accounts.get_pending_invitation(user_scope_fixture(admin), pending_user)
    assert has_element?(view, "#user-invitation-copy[data-copy-value$='#{new_invitation.token}']")

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
