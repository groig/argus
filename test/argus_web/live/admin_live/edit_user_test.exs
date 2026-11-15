defmodule ArgusWeb.AdminLive.EditUserTest do
  use ArgusWeb.ConnCase, async: true

  import Argus.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Argus.Accounts

  setup %{conn: conn} do
    admin = admin_fixture()
    %{admin: admin, conn: log_in_user(conn, admin)}
  end

  # Mounts after the fixtures exist, so the users table lists them.
  defp open_user(conn, user) do
    {:ok, view, _html} = live(conn, ~p"/admin")
    reopen_user(view, user)
  end

  defp reopen_user(view, user) do
    render_click(element(view, "#edit-user-#{user.id}"))
    assert has_element?(view, "#user-modal")
    view
  end

  describe "closing the modal" do
    test "with the close icon and the footer button", %{conn: conn} do
      member = user_fixture()

      view = open_user(conn, member)
      view |> element("#user-modal-close") |> render_click()
      refute has_element?(view, "#user-modal")

      view |> reopen_user(member) |> element("#user-modal-done") |> render_click()
      refute has_element?(view, "#user-modal")
    end

    test "wires Escape through the client hook that spares focused fields", %{conn: conn} do
      view = open_user(conn, user_fixture())

      # The hook runs in the browser and executes this command; the server only sees the push.
      assert has_element?(
               view,
               "#user-modal-panel[phx-hook='ArgusWeb.CoreComponents.ModalEscape'][data-cancel*='close-modal']"
             )
    end
  end

  describe "profile" do
    test "saves name, email, and global role on submit", %{conn: conn} do
      member = user_fixture()
      email = unique_user_email()

      view = open_user(conn, member)

      render_submit(element(view, "#edit-user-form"), %{
        "edit_user" => %{"name" => "Renamed Member", "email" => email, "role" => "admin"}
      })

      updated = Accounts.get_user!(member.id)
      assert updated.name == "Renamed Member"
      assert updated.email == email
      assert updated.role == :admin
      assert has_element?(view, "#user-modal")
      assert has_element?(view, "#admin-users td", "Renamed Member")
    end

    test "does not change anything until saved", %{conn: conn} do
      member = user_fixture()

      view = open_user(conn, member)

      render_change(element(view, "#edit-user-form"), %{
        "edit_user" => %{"name" => "Draft Name", "email" => member.email, "role" => "admin"}
      })

      assert Accounts.get_user!(member.id).role == :member
      assert Accounts.get_user!(member.id).name == member.name
    end

    test "shows validation errors", %{conn: conn} do
      member = user_fixture()
      other = user_fixture()

      view = open_user(conn, member)

      render_change(element(view, "#edit-user-form"), %{
        "edit_user" => %{"name" => "x", "email" => "not-an-email"}
      })

      assert has_element?(view, "#edit-user-form p", "must have the @ sign and no spaces")

      render_submit(element(view, "#edit-user-form"), %{
        "edit_user" => %{"name" => "Valid Name", "email" => other.email}
      })

      assert has_element?(view, "#edit-user-form p", "has already been taken")
      assert Accounts.get_user!(member.id).email == member.email
    end

    test "admins can edit their own profile but not their role", %{conn: conn, admin: admin} do
      view = open_user(conn, admin)

      assert has_element?(view, "#edit-user-form select[disabled]")
      refute has_element?(view, "#set-user-password-form")
      refute has_element?(view, "#delete-user-#{admin.id}")

      render_submit(element(view, "#edit-user-form"), %{
        "edit_user" => %{"name" => "Admin Renamed", "email" => admin.email, "role" => "member"}
      })

      updated = Accounts.get_user!(admin.id)
      assert updated.name == "Admin Renamed"
      assert updated.role == :admin
    end
  end

  describe "role changes" do
    test "disconnect the user's live sessions so the new role applies", %{conn: conn} do
      member = user_fixture()
      session_token = Accounts.generate_user_session_token(member)
      ArgusWeb.Endpoint.subscribe("users_sessions:#{Base.url_encode64(session_token)}")

      view = open_user(conn, member)

      render_submit(element(view, "#edit-user-form"), %{
        "edit_user" => %{"name" => member.name, "email" => member.email, "role" => "admin"}
      })

      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}
    end

    test "leave sessions alone when the role stays the same", %{conn: conn} do
      member = user_fixture()
      session_token = Accounts.generate_user_session_token(member)
      ArgusWeb.Endpoint.subscribe("users_sessions:#{Base.url_encode64(session_token)}")

      view = open_user(conn, member)

      render_submit(element(view, "#edit-user-form"), %{
        "edit_user" => %{"name" => "Same Role", "email" => member.email, "role" => "member"}
      })

      refute_received %Phoenix.Socket.Broadcast{event: "disconnect"}
    end
  end

  describe "concurrent changes" do
    test "saving a user deleted meanwhile closes the dialog instead of crashing", %{conn: conn} do
      member = user_fixture()
      view = open_user(conn, member)
      {:ok, _} = Accounts.delete_user(member)

      render_submit(element(view, "#edit-user-form"), %{
        "edit_user" => %{"name" => "Too Late", "email" => member.email}
      })

      refute has_element?(view, "#user-modal")
      refute has_element?(view, "#edit-user-#{member.id}")
    end

    test "resetting the password of a user deleted meanwhile closes the dialog", %{conn: conn} do
      member = user_fixture()
      view = open_user(conn, member)
      {:ok, _} = Accounts.delete_user(member)

      render_submit(element(view, "#set-user-password-form"), %{
        "user_password" => %{
          "expected_state" => "active",
          "password" => "replacement-password",
          "password_confirmation" => "replacement-password"
        }
      })

      refute has_element?(view, "#user-modal")
    end

    test "activating doesn't overwrite a password the user chose meanwhile", %{conn: conn} do
      invitation = invitation_fixture()
      view = open_user(conn, invitation.user)

      {:ok, _} =
        Accounts.accept_user_invitation(invitation.token, %{
          password: "chosen-by-user",
          password_confirmation: "chosen-by-user"
        })

      render_submit(element(view, "#set-user-password-form"), %{
        "user_password" => %{
          "password" => "admin-password",
          "password_confirmation" => "admin-password"
        }
      })

      assert Accounts.get_user_by_email_and_password(invitation.email, "chosen-by-user")
      refute Accounts.get_user_by_email_and_password(invitation.email, "admin-password")
      assert has_element?(view, "#user-status", "active")
    end
  end

  describe "password" do
    test "activates a pending user without email", %{conn: conn} do
      pending = pending_user_fixture()

      view = open_user(conn, pending)
      assert has_element?(view, "#set-user-password-submit", "Set password & activate")

      render_submit(element(view, "#set-user-password-form"), %{
        "user_password" => %{
          "password" => "activated-password",
          "password_confirmation" => "activated-password"
        }
      })

      assert Accounts.get_user_by_email_and_password(pending.email, "activated-password")
      assert has_element?(view, "#user-status", "active")
      refute has_element?(view, "#user-invitation")
    end

    test "resets an active user's password and ends their sessions", %{conn: conn} do
      member = user_fixture()
      session_token = Accounts.generate_user_session_token(member)

      view = open_user(conn, member)
      assert has_element?(view, "#set-user-password-submit", "Reset password")

      render_submit(element(view, "#set-user-password-form"), %{
        "user_password" => %{
          "password" => "replacement-password",
          "password_confirmation" => "replacement-password"
        }
      })

      assert Accounts.get_user_by_email_and_password(member.email, "replacement-password")
      assert Accounts.get_user_by_session_token(session_token) == nil
    end

    test "shows errors for an invalid password", %{conn: conn} do
      member = user_fixture()

      view = open_user(conn, member)

      render_submit(element(view, "#set-user-password-form"), %{
        "user_password" => %{"password" => "short", "password_confirmation" => "nope"}
      })

      assert has_element?(view, "#set-user-password-form p", "should be at least 8 character(s)")
      assert Accounts.get_user_by_email_and_password(member.email, valid_user_password())
    end
  end

  describe "invitation link" do
    test "shows the current link for pending users", %{conn: conn} do
      invitation = invitation_fixture()

      view = open_user(conn, invitation.user)

      assert has_element?(
               view,
               "#user-invitation-copy[data-copy-value$='/invitations/#{invitation.token}']"
             )
    end

    test "asks for a new link after the email of a pending user changes", %{conn: conn} do
      invitation = invitation_fixture()
      user = invitation.user

      view = open_user(conn, user)

      render_submit(element(view, "#edit-user-form"), %{
        "edit_user" => %{"name" => user.name, "email" => unique_user_email()}
      })

      assert has_element?(view, "#user-invitation-missing")

      render_click(element(view, "#resend-user-invitation-#{user.id}"))

      refute has_element?(view, "#user-invitation-missing")
      assert has_element?(view, "#user-invitation-copy")
    end

    test "is hidden for active users", %{conn: conn} do
      view = open_user(conn, user_fixture())
      refute has_element?(view, "#user-invitation")
    end
  end
end
