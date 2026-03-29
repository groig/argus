defmodule ArgusWeb.UserLive.InvitationTest do
  use ArgusWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Argus.Accounts

  import Argus.AccountsFixtures

  describe "invitation page" do
    test "renders inviter details for a valid invitation", %{conn: conn} do
      inviter = admin_fixture(%{name: "Platform Admin"})
      invitation = invitation_fixture(inviter, %{email: "invitee@example.com"})

      {:ok, _lv, html} = live(conn, ~p"/invitations/#{invitation.token}")

      assert html =~ "Join Argus"
      assert html =~ "Platform Admin invited invitee@example.com to the workspace."
      assert html =~ ~s(id="invitation-form")
    end

    test "redirects invalid invitations back to login", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: path}}} = live(conn, ~p"/invitations/invalid")
      assert path == ~p"/login"
    end

    test "keeps submitting the password form as POST after validation", %{conn: conn} do
      inviter = admin_fixture(%{name: "Platform Admin"})
      invitation = invitation_fixture(inviter, %{email: "invitee@example.com"})

      {:ok, view, _html} = live(conn, ~p"/invitations/#{invitation.token}")

      invitation_form =
        form(view, "#invitation-form", %{
          "user" => %{
            "password" => "changeme123",
            "password_confirmation" => "changeme123"
          }
        })

      render_change(invitation_form)
      conn = submit_form(invitation_form, conn)
      user = Accounts.get_user_by_email("invitee@example.com")

      assert redirected_to(conn) == ~p"/projects"
      assert get_session(conn, :user_token)
      assert user.confirmed_at
    end
  end
end
