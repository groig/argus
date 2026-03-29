defmodule ArgusWeb.LogsLive.IndexTest do
  use ArgusWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Argus.Logs

  import Argus.AccountsFixtures
  import Argus.WorkspaceFixtures

  setup %{conn: conn} do
    user = user_fixture()
    team = team_fixture()
    _membership = membership_fixture(team, user, :admin)
    project = project_fixture(team, %{"name" => "Billing API"})

    %{conn: log_in_user(conn, user), project: project}
  end

  test "filters logs by message and level", %{conn: conn, project: project} do
    _info_log = log_fixture(project, %{message: "Job completed", level: :info})
    _error_log = log_fixture(project, %{message: "Provider timeout", level: :error})

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/logs")

    assert render(view) =~ "Job completed"
    assert render(view) =~ "Provider timeout"

    render_change(
      form(view, "#log-filters", %{
        "filters" => %{"search" => "timeout", "level" => "error"}
      })
    )

    html = render(view)

    assert html =~ "Provider timeout"
    refute html =~ "Job completed"
  end

  test "streams new logs when tail mode is enabled", %{conn: conn, project: project} do
    _initial_log = log_fixture(project, %{message: "Existing log"})

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/logs")

    render_click(element(view, "#toggle-tail"))

    {:ok, _log_event} =
      Logs.create_log_event(project, %{
        level: :warning,
        message: "Tail log message",
        timestamp: DateTime.utc_now(:second),
        metadata: %{"attributes" => %{"logger.name" => "tail"}},
        logger_name: "tail",
        origin: "manual"
      })

    assert render(view) =~ "Tail log message"
  end

  test "paginates the logs list", %{conn: conn, project: project} do
    base = ~U[2026-03-31 12:00:00Z]

    for index <- 1..55 do
      log_fixture(project, %{
        message: "log-#{String.pad_leading(Integer.to_string(index), 3, "0")}",
        timestamp: DateTime.add(base, index, :second)
      })
    end

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/logs")

    assert has_element?(view, "#logs-pagination")
    assert render(view) =~ "Showing 1-50 of 55 logs"
    assert render(view) =~ "log-055"
    refute render(view) =~ "log-001"

    render_click(element(view, "#logs-pagination-next"))

    assert render(view) =~ "Showing 51-55 of 55 logs"
    assert render(view) =~ "Page 2 of 2"
    assert render(view) =~ "log-005"
    assert render(view) =~ "log-001"
    refute render(view) =~ "log-055"
  end
end
