defmodule ArgusWeb.PageControllerTest do
  use ArgusWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    response = html_response(conn, 200)
    assert response =~ "Welcome"
    assert response =~ ~s(href="/login")
    refute response =~ "Self-hosted Sentry-compatible ingestion"
  end

  test "GET /users/register returns 404", %{conn: conn} do
    conn = get(conn, ~p"/users/register")
    assert response(conn, 404) == "Not found"
  end
end
