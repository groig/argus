defmodule ArgusWeb.UserLive.ResetPasswordTest do
  use ArgusWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias Argus.Accounts

  import Argus.AccountsFixtures

  describe "forgot password page" do
    test "is linked from the login page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/login")

      assert has_element?(view, ~s(#forgot-password-link[href="/reset-password"]))
    end

    test "emails a reset link to an existing user", %{conn: conn} do
      user = user_fixture()
      {:ok, view, _html} = live(conn, ~p"/reset-password")

      {:ok, login, _html} =
        view
        |> form("#reset-password-form", user: %{email: user.email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/login")

      assert render(login) =~ "reset link is on its way"
      assert_email_sent(to: [{"", user.email}], subject: "Reset your Argus password")
    end

    test "responds the same way for unknown emails", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/reset-password")

      {:ok, login, _html} =
        view
        |> form("#reset-password-form", user: %{email: "nobody@example.com"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/login")

      assert render(login) =~ "reset link is on its way"
      assert_no_email_sent()
    end
  end

  describe "reset password page" do
    setup do
      user = user_fixture()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
        end)

      %{user: user, token: token}
    end

    test "redirects invalid tokens to the forgot password page", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: path, flash: flash}}} =
               live(conn, ~p"/reset-password/invalid")

      assert path == ~p"/reset-password"
      assert flash["error"] =~ "invalid or has expired"
    end

    test "shows validation errors", %{conn: conn, token: token} do
      {:ok, view, _html} = live(conn, ~p"/reset-password/#{token}")

      html =
        view
        |> form("#new-password-form",
          user: %{password: "short", password_confirmation: "different"}
        )
        |> render_change()

      assert html =~ "should be at least 8 character"
      assert html =~ "does not match password"
    end

    test "resets the password and logs out other sessions", %{
      conn: conn,
      user: user,
      token: token
    } do
      other_session = Accounts.generate_user_session_token(user)
      {:ok, view, _html} = live(conn, ~p"/reset-password/#{token}")

      {:ok, login, _html} =
        view
        |> form("#new-password-form",
          user: %{password: "brand-new-password", password_confirmation: "brand-new-password"}
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/login")

      assert render(login) =~ "Password reset"
      assert Accounts.get_user_by_email_and_password(user.email, "brand-new-password")
      refute Accounts.get_user_by_session_token(other_session)
      refute Accounts.get_user_by_reset_password_token(token)
    end
  end
end
