defmodule ArgusWeb.UserAuthTest do
  use ArgusWeb.ConnCase, async: true

  alias Phoenix.LiveView
  alias Argus.Accounts
  alias ArgusWeb.UserAuth

  import Argus.AccountsFixtures
  import Argus.WorkspaceFixtures

  setup %{conn: conn} do
    conn =
      conn
      |> Map.replace!(:secret_key_base, ArgusWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{})

    %{conn: conn}
  end

  describe "log_in_user/3" do
    test "stores the user token and redirects to the dashboard", %{conn: conn} do
      %{user: user} = workspace_fixture()

      conn = UserAuth.log_in_user(conn, user)

      assert token = get_session(conn, :user_token)
      assert get_session(conn, :live_socket_id) == "users_sessions:#{Base.url_encode64(token)}"
      assert redirected_to(conn) == ~p"/projects"
      assert Accounts.get_user_by_session_token(token)
    end

    test "falls back to the empty projects page when no projects are available", %{conn: conn} do
      user = user_fixture()
      conn = UserAuth.log_in_user(conn, user)

      assert redirected_to(conn) == ~p"/projects"
    end
  end

  describe "log_out_user/1" do
    test "clears the session token and redirects home", %{conn: conn} do
      user = user_fixture()
      user_token = Accounts.generate_user_session_token(user)

      conn =
        conn
        |> put_session(:user_token, user_token)
        |> UserAuth.log_out_user()

      refute get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"
      assert Accounts.get_user_by_session_token(user_token) == nil
    end
  end

  describe "fetch_current_scope_for_user/2" do
    test "loads current_scope from the session token", %{conn: conn} do
      user = user_fixture()
      user_token = Accounts.generate_user_session_token(user)

      conn =
        conn
        |> put_session(:user_token, user_token)
        |> UserAuth.fetch_current_scope_for_user([])

      assert conn.assigns.current_scope.user.id == user.id
    end
  end

  describe "on_mount :require_authenticated" do
    test "halts and redirects when there is no user token" do
      socket = %LiveView.Socket{
        endpoint: ArgusWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      assert {:halt, halted_socket} =
               UserAuth.on_mount(:require_authenticated, %{}, %{}, socket)

      assert halted_socket.assigns.current_scope == nil
    end
  end

  describe "require_authenticated_user/2" do
    test "redirects guests to /login", %{conn: conn} do
      conn =
        conn
        |> Phoenix.Controller.fetch_flash([])
        |> UserAuth.require_authenticated_user([])

      assert conn.halted
      assert redirected_to(conn) == ~p"/login"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "You must log in to access this page."
    end
  end
end
