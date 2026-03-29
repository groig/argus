defmodule ArgusWeb.UserLive.SettingsTest do
  use ArgusWeb.ConnCase, async: true

  alias Argus.Accounts

  import Argus.AccountsFixtures
  import Phoenix.LiveViewTest

  describe "settings page" do
    test "renders for authenticated users", %{conn: conn} do
      user = user_fixture()

      {:ok, _lv, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/settings")

      assert html =~ "Your settings"
      assert html =~ ~s(id="profile-form")
      assert html =~ ~s(id="password-form")
    end

    test "redirects unauthenticated users to login", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/settings")
      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/login"
      assert %{"error" => "You must log in to access this page."} = flash
    end
  end

  describe "profile form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "updates the user profile", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/settings")

      lv
      |> form("#profile-form", %{
        "user" => %{"name" => "Updated Name", "email" => "updated@example.com"}
      })
      |> render_submit()

      updated_user = Accounts.get_user!(user.id)
      assert updated_user.name == "Updated Name"
      assert updated_user.email == "updated@example.com"
    end
  end

  describe "password form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "updates the password through the trigger action flow", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/settings")

      form =
        form(lv, "#password-form", %{
          "user" => %{
            "password" => "newpassword123",
            "password_confirmation" => "newpassword123"
          }
        })

      render_submit(form)
      updated_conn = follow_trigger_action(form, conn)

      assert redirected_to(updated_conn) == ~p"/projects"
      assert Accounts.get_user_by_email_and_password(user.email, "newpassword123")
    end

    test "renders validation errors for invalid passwords", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/settings")

      html =
        lv
        |> element("#password-form")
        |> render_change(%{
          "user" => %{
            "password" => "short",
            "password_confirmation" => "different"
          }
        })

      assert html =~ "should be at least 8 character(s)"
      assert html =~ "does not match password"
    end
  end
end
