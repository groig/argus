defmodule ArgusWeb.UserLive.LoginTest do
  use ArgusWeb.ConnCase, async: true

  import Argus.WorkspaceFixtures
  import Phoenix.LiveViewTest

  describe "login page" do
    test "renders the password login form", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/login")

      assert html =~ "Log in"
      assert html =~ "Keep me signed in on this device"
      assert html =~ ~s(id="login-form")
    end

    test "redirects signed-in users to the dashboard", %{conn: conn} do
      %{user: user} = workspace_fixture()

      assert {:error, {:redirect, %{to: path}}} =
               conn
               |> log_in_user(user)
               |> live(~p"/login")

      assert path == ~p"/projects"
    end
  end
end
