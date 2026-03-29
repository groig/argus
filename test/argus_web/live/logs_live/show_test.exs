defmodule ArgusWeb.LogsLive.ShowTest do
  use ArgusWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  import Argus.AccountsFixtures
  import Argus.WorkspaceFixtures

  setup %{conn: conn} do
    user = user_fixture()
    team = team_fixture()
    _membership = membership_fixture(team, user, :admin)
    project = project_fixture(team, %{"name" => "Billing API"})

    log_event =
      log_fixture(project, %{
        level: :warning,
        message: "Payment provider degraded",
        timestamp: ~U[2026-03-28 23:10:00Z],
        metadata: %{
          "attributes" => %{
            "logger.name" => "billing.alerts",
            "payment.provider" => "stripe",
            "request.id" => "req_123"
          },
          "context" => %{
            "customer_id" => "cus_123",
            "path" => "/billing/retry"
          }
        },
        logger_name: "billing.alerts",
        origin: "sentry",
        release: "billing-web@2026.3.28",
        environment: "production",
        sdk_name: "sentry.python.django",
        sdk_version: "2.54.0",
        sequence: 42,
        trace_id: "trace-123",
        span_id: "span-456"
      })

    %{conn: log_in_user(conn, user), project: project, log_event: log_event}
  end

  test "renders the formatted log detail view", %{
    conn: conn,
    project: project,
    log_event: log_event
  } do
    {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/logs/#{log_event.id}")

    assert has_element?(view, "#log-formatted-tab")
    assert has_element?(view, "#log-formatted-view")
    assert has_element?(view, "#log-summary-panel")
    assert has_element?(view, "#log-identifiers-panel")

    html = render(view)

    assert html =~ "Payment provider degraded"
    assert html =~ "billing.alerts"
    assert html =~ "stripe"
    assert html =~ "billing-web@2026.3.28"
    assert html =~ "warning"
  end

  test "switches to the raw log view", %{conn: conn, project: project, log_event: log_event} do
    {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/logs/#{log_event.id}")

    render_click(element(view, "#log-raw-tab"))

    assert_patch(view, ~p"/projects/#{project.slug}/logs/#{log_event.id}?tab=raw")
    assert has_element?(view, "#log-raw-view")
    assert has_element?(view, "#copy-log-raw")

    html = render(view)

    assert html =~ "&quot;message&quot;: &quot;Payment provider degraded&quot;"
    assert html =~ "&quot;trace_id&quot;: &quot;trace-123&quot;"
  end

  test "links to the dedicated detail page from the logs list", %{
    conn: conn,
    project: project,
    log_event: log_event
  } do
    {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/logs")

    assert has_element?(view, "a[href='/projects/#{project.slug}/logs/#{log_event.id}']")
  end
end
