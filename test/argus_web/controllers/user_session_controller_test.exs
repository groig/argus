defmodule ArgusWeb.UserSessionControllerTest do
  use ArgusWeb.ConnCase, async: true

  import Argus.AccountsFixtures
  import Argus.WorkspaceFixtures

  describe "POST /login" do
    test "logs the user in and redirects to the dashboard", %{conn: conn} do
      %{user: user} = workspace_fixture()

      conn =
        post(conn, ~p"/login", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password(),
            "remember_me" => "true"
          }
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/projects"
      assert conn.resp_cookies["_argus_web_user_remember_me"]
    end

    test "rejects invalid credentials", %{conn: conn} do
      user_fixture()

      conn =
        post(conn, ~p"/login", %{
          "user" => %{"email" => "missing@example.com", "password" => "wrong"}
        })

      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
    end

    test "does not log in a pending invited user", %{conn: conn} do
      inviter = admin_fixture()
      invitation = invitation_fixture(inviter)

      conn =
        post(conn, ~p"/login", %{
          "user" => %{"email" => invitation.email, "password" => valid_user_password()}
        })

      refute get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/login"
    end
  end

  describe "DELETE /logout" do
    test "logs the user out even when already authenticated", %{conn: conn} do
      user = user_fixture()
      conn = conn |> log_in_user(user) |> delete(~p"/logout")

      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end
  end
end
