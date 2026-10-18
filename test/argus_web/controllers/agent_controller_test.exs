defmodule ArgusWeb.AgentControllerTest do
  use ArgusWeb.ConnCase, async: true

  alias Argus.Accounts

  import Argus.AccountsFixtures
  import Argus.WorkspaceFixtures

  setup %{conn: conn} do
    %{user: user, project: project} = workspace_fixture(role: :member)
    {:ok, {token, _api_token}} = Accounts.create_api_token(user, %{"name" => "agent"})

    conn = put_req_header(conn, "authorization", "Bearer #{token}")
    %{conn: conn, user: user, project: project}
  end

  describe "authentication" do
    test "rejects requests without a token" do
      conn = get(build_conn(), ~p"/api/v1/projects")

      assert conn.status == 401
      assert get_resp_header(conn, "www-authenticate") == ["Bearer"]
    end

    test "rejects unknown and revoked tokens", %{user: user} do
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer argus_nope")
        |> get(~p"/api/v1/projects")

      assert conn.status == 401

      {:ok, {token, api_token}} = Accounts.create_api_token(user, %{"name" => "temp"})
      :ok = Accounts.delete_api_token(user, api_token.id)

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/v1/projects")

      assert conn.status == 401
    end
  end

  test "index documents the endpoints", %{conn: conn} do
    conn = get(conn, ~p"/api/v1")

    assert response_content_type(conn, :markdown) =~ "text/markdown"
    assert response(conn, 200) =~ "/api/v1/projects/:slug/issues"
    assert response(conn, 200) =~ "/api/v1/projects/:slug/issues/:id/ignore"
  end

  test "lists only projects the user can access", %{conn: conn, project: project} do
    other_project = project_fixture(team_fixture(), %{"name" => "Hidden"})

    body = conn |> get(~p"/api/v1/projects") |> response(200)

    assert body =~ project.slug
    refute body =~ other_project.slug
  end

  test "returns 404 for projects outside the user's teams", %{conn: conn} do
    other_project = project_fixture(team_fixture())

    conn = get(conn, ~p"/api/v1/projects/#{other_project.slug}/issues")

    assert response(conn, 404) =~ "Project not found"
  end

  describe "issues" do
    test "lists unresolved issues with pagination links", %{conn: conn, project: project} do
      for n <- 1..3 do
        issue_fixture(project, %{fingerprint: "fp-#{n}", title: "Boom #{n}"})
      end

      body =
        conn
        |> get(~p"/api/v1/projects/#{project.slug}/issues?per_page=2")
        |> response(200)

      assert body =~ "| ID | Title |"
      assert body =~ "Page 1 of 2 (3 issues)"
      assert body =~ "Next: "
      assert body =~ "page=2"
      assert body =~ "per_page=2"
    end

    test "full=true includes each issue's full text", %{conn: conn, project: project} do
      issue_fixture(project, %{title: "RuntimeError: full text"})

      body =
        conn
        |> get(~p"/api/v1/projects/#{project.slug}/issues?full=true")
        |> response(200)

      assert body =~ "Argus Issue"
      assert body =~ "Title: RuntimeError: full text"
      assert body =~ "Selected Event"
    end

    test "filters by status", %{conn: conn, project: project} do
      issue_fixture(project, %{fingerprint: "fp-open", title: "Open one"})
      issue_fixture(project, %{fingerprint: "fp-done", title: "Done one", status: :resolved})

      body =
        conn
        |> get(~p"/api/v1/projects/#{project.slug}/issues?status=resolved")
        |> response(200)

      assert body =~ "Done one"
      refute body =~ "Open one"
    end

    test "shows the full issue text", %{conn: conn, project: project} do
      issue = issue_fixture(project)

      body =
        conn
        |> get(~p"/api/v1/projects/#{project.slug}/issues/#{issue.id}")
        |> response(200)

      assert body =~ "Title: #{issue.title}"
      assert body =~ "Exception 1: RuntimeError"
      assert body =~ "/api/v1/projects/#{project.slug}/issues/#{issue.id}/occurrences"
    end

    test "returns 404 for unknown or malformed issue ids", %{conn: conn, project: project} do
      assert conn |> get(~p"/api/v1/projects/#{project.slug}/issues/999999") |> response(404)
      assert conn |> get(~p"/api/v1/projects/#{project.slug}/issues/abc") |> response(404)
    end
  end

  describe "occurrences" do
    setup %{project: project} do
      issue = issue_fixture(project)
      _ = issue_fixture(project)
      _ = issue_fixture(project)

      %{issue: issue}
    end

    test "pages through occurrences", %{conn: conn, project: project, issue: issue} do
      body =
        conn
        |> get(~p"/api/v1/projects/#{project.slug}/issues/#{issue.id}/occurrences?per_page=2")
        |> response(200)

      assert body =~ "| ID | Timestamp |"
      assert body =~ "Page 1 of 2 (3 occurrences)"

      body =
        conn
        |> get(
          ~p"/api/v1/projects/#{project.slug}/issues/#{issue.id}/occurrences?per_page=2&page=2"
        )
        |> response(200)

      assert body =~ "Page 2 of 2 (3 occurrences)"
      assert body =~ "Previous: "
    end

    test "full=true renders every occurrence", %{conn: conn, project: project, issue: issue} do
      body =
        conn
        |> get(~p"/api/v1/projects/#{project.slug}/issues/#{issue.id}/occurrences?full=true")
        |> response(200)

      assert length(String.split(body, "Selected Event")) == 4
    end

    test "shows a single occurrence", %{conn: conn, project: project, issue: issue} do
      {[occurrence | _], _} = Argus.Projects.list_occurrences(issue, 1, 1)

      body =
        conn
        |> get(
          ~p"/api/v1/projects/#{project.slug}/issues/#{issue.id}/occurrences/#{occurrence.id}"
        )
        |> response(200)

      assert body =~ "Event ID: #{occurrence.event_id}"

      assert conn
             |> get(~p"/api/v1/projects/#{project.slug}/issues/#{issue.id}/occurrences/999999")
             |> response(404)
    end
  end

  describe "resolve" do
    test "resolves an issue", %{conn: conn, project: project} do
      issue = issue_fixture(project)

      body =
        conn
        |> post(~p"/api/v1/projects/#{project.slug}/issues/#{issue.id}/resolve")
        |> response(200)

      assert body =~ "is now resolved"
      assert Argus.Repo.reload!(issue).status == :resolved
    end

    test "succeeds for an already resolved issue", %{conn: conn, project: project} do
      issue = issue_fixture(project, %{status: :resolved})

      body =
        conn
        |> post(~p"/api/v1/projects/#{project.slug}/issues/#{issue.id}/resolve")
        |> response(200)

      assert body =~ "was already resolved"
    end

    test "returns 404 for unknown issues and inaccessible projects", %{
      conn: conn,
      project: project
    } do
      other_issue = issue_fixture(project_fixture(team_fixture()))

      assert conn
             |> post(~p"/api/v1/projects/#{project.slug}/issues/999999/resolve")
             |> response(404)

      assert conn
             |> post(
               ~p"/api/v1/projects/#{other_issue.project.slug}/issues/#{other_issue.id}/resolve"
             )
             |> response(404)

      assert Argus.Repo.reload!(other_issue).status == :unresolved
    end

    test "requires a token", %{project: project} do
      issue = issue_fixture(project)

      assert build_conn()
             |> post(~p"/api/v1/projects/#{project.slug}/issues/#{issue.id}/resolve")
             |> response(401)

      assert Argus.Repo.reload!(issue).status == :unresolved
    end
  end

  describe "ignore" do
    test "ignores an issue", %{conn: conn, project: project} do
      issue = issue_fixture(project)

      body =
        conn
        |> post(~p"/api/v1/projects/#{project.slug}/issues/#{issue.id}/ignore")
        |> response(200)

      assert body =~ "is now ignored"
      assert body =~ "stays ignored if a new event arrives"
      assert Argus.Repo.reload!(issue).status == :ignored
    end

    test "succeeds for an already ignored issue", %{conn: conn, project: project} do
      issue = issue_fixture(project, %{status: :ignored})

      body =
        conn
        |> post(~p"/api/v1/projects/#{project.slug}/issues/#{issue.id}/ignore")
        |> response(200)

      assert body =~ "was already ignored"
      assert Argus.Repo.reload!(issue).status == :ignored
    end

    test "returns 404 for unknown issues and inaccessible projects", %{
      conn: conn,
      project: project
    } do
      other_issue = issue_fixture(project_fixture(team_fixture()))

      assert conn
             |> post(~p"/api/v1/projects/#{project.slug}/issues/999999/ignore")
             |> response(404)

      assert conn
             |> post(~p"/api/v1/projects/#{project.slug}/issues/abc/ignore")
             |> response(404)

      assert conn
             |> post(
               ~p"/api/v1/projects/#{other_issue.project.slug}/issues/#{other_issue.id}/ignore"
             )
             |> response(404)

      assert Argus.Repo.reload!(other_issue).status == :unresolved
    end

    test "requires a token", %{project: project} do
      issue = issue_fixture(project)

      assert build_conn()
             |> post(~p"/api/v1/projects/#{project.slug}/issues/#{issue.id}/ignore")
             |> response(401)

      assert Argus.Repo.reload!(issue).status == :unresolved
    end
  end

  test "admins can read any project" do
    admin = admin_fixture()
    project = project_fixture(team_fixture())
    {:ok, {token, _}} = Accounts.create_api_token(admin, %{"name" => "admin"})

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> get(~p"/api/v1/projects/#{project.slug}/issues")

    assert response(conn, 200) =~ "# Issues"
  end
end
