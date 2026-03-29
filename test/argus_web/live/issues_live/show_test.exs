defmodule ArgusWeb.IssuesLive.ShowTest do
  use ArgusWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Argus.Projects

  import Argus.AccountsFixtures
  import Argus.WorkspaceFixtures

  setup %{conn: conn} do
    user = user_fixture()
    team = team_fixture()
    _membership = membership_fixture(team, user, :admin)
    project = project_fixture(team, %{"name" => "Billing API"})
    issue = rich_issue_fixture(project)

    %{conn: log_in_user(conn, user), project: project, issue: issue}
  end

  test "renders the latest occurrence with stacktrace context, locals, and supporting metadata",
       %{
         conn: conn,
         project: project,
         issue: issue
       } do
    {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/issues/#{issue.id}")

    assert has_element?(view, "#issue-event-tab")
    assert has_element?(view, "#issue-occurrence-nav")
    assert has_element?(view, "#issue-selected-event")
    assert has_element?(view, "#issue-frame-0[open]")
    assert has_element?(view, "#issue-breadcrumbs-tab")
    assert has_element?(view, "#issue-request-panel")
    assert has_element?(view, "#issue-sdk-panel")
    assert has_element?(view, "#issue-show-all-frames")

    html = render(view)

    assert html =~ "Event 1 of 2"
    assert html =~ "billing-web@2026.3.28"
    assert html =~ "raise RuntimeError(&quot;invoice failed&quot;)"
    assert html =~ "Current user"
    assert html =~ "alice@example.com"
    refute html =~ "Loaded cart"
    refute html =~ "django.core.handlers"
  end

  test "toggles between in-app frames and all frames, and keeps breadcrumbs secondary", %{
    conn: conn,
    project: project,
    issue: issue
  } do
    [latest_occurrence, older_occurrence] = Projects.list_all_occurrences(issue)

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/issues/#{issue.id}")

    assert has_element?(view, "#issue-event-position[data-position='1']")
    assert render(view) =~ latest_occurrence.event_id

    render_click(element(view, "#issue-older-event"))

    assert_patch(
      view,
      ~p"/projects/#{project.slug}/issues/#{issue.id}?tab=event&event=#{older_occurrence.id}&frames=in_app"
    )

    assert has_element?(view, "#issue-event-position[data-position='2']")
    assert render(view) =~ older_occurrence.event_id

    render_click(element(view, "#issue-show-all-frames"))

    assert_patch(
      view,
      ~p"/projects/#{project.slug}/issues/#{issue.id}?tab=event&event=#{older_occurrence.id}&frames=all"
    )

    assert render(view) =~ "django.core.handlers"

    render_click(element(view, "#issue-events-tab"))

    assert_patch(
      view,
      ~p"/projects/#{project.slug}/issues/#{issue.id}?tab=events&event=#{older_occurrence.id}&frames=all"
    )

    assert has_element?(view, "#issue-events-list")

    render_click(element(view, "#issue-breadcrumbs-tab"))

    assert_patch(
      view,
      ~p"/projects/#{project.slug}/issues/#{issue.id}?tab=breadcrumbs&event=#{older_occurrence.id}&frames=all"
    )

    assert has_element?(view, "#issue-breadcrumbs")
    assert has_element?(view, "#issue-breadcrumb-0")
    assert render(view) =~ "Loaded cart"
    refute render(view) =~ "Clicked retry payment"
  end

  test "assigns and unassigns the issue from the detail page", %{
    conn: conn,
    project: project,
    issue: issue
  } do
    teammate = user_fixture(%{name: "Casey Operator"})
    membership_fixture(project.team, teammate)

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/issues/#{issue.id}")

    assert has_element?(view, "#issue-assignee-form")

    render_change(element(view, "#issue-assignee-form"), %{
      "assignment" => %{"assignee_id" => Integer.to_string(teammate.id)}
    })

    assigned_issue = Projects.get_error_event(project, issue.id)
    assert assigned_issue.assignee_id == teammate.id

    render_change(element(view, "#issue-assignee-form"), %{"assignment" => %{"assignee_id" => ""}})

    unassigned_issue = Projects.get_error_event(project, issue.id)
    assert is_nil(unassigned_issue.assignee_id)
  end

  defp rich_issue_fixture(project) do
    older_timestamp = ~U[2026-03-28 22:20:00Z]
    latest_timestamp = ~U[2026-03-28 22:25:00Z]

    issue_attrs = %{
      fingerprint: "RuntimeError|invoice failed|billing.views.checkout",
      title: "RuntimeError: invoice failed",
      culprit: "billing.views.checkout",
      level: :error,
      platform: "python",
      sdk: %{"name" => "sentry.python.django", "version" => "2.54.0"},
      request: %{"url" => "http://example.com/billing/checkout"},
      contexts: %{
        "runtime" => %{"name" => "CPython", "version" => "3.12.11"},
        "os" => %{"name" => "Linux"},
        "browser" => %{"name" => "Firefox"}
      },
      tags: %{"environment" => "test", "logger" => "sentry"},
      extra: %{"invoice_id" => "inv_123"},
      first_seen_at: older_timestamp,
      last_seen_at: older_timestamp,
      occurrence_count: 1,
      status: :unresolved
    }

    {:ok, %{issue: issue}} =
      Projects.upsert_issue_and_occurrence(
        project,
        issue_attrs,
        rich_occurrence_attrs("evt-old", older_timestamp, "http://example.com/billing/checkout")
      )

    {:ok, %{issue: _issue}} =
      Projects.upsert_issue_and_occurrence(
        project,
        %{issue_attrs | last_seen_at: latest_timestamp},
        rich_occurrence_attrs(
          "evt-latest",
          latest_timestamp,
          "http://example.com/billing/checkout/retry"
        )
      )

    issue
  end

  defp rich_occurrence_attrs(event_id, timestamp, request_url) do
    runtime_context = %{"name" => "CPython", "version" => "3.12.11"}

    %{
      event_id: event_id,
      timestamp: timestamp,
      request_url: request_url,
      user_context: %{"email" => "alice@example.com", "id" => "user_123"},
      exception_values: [
        %{
          "type" => "RuntimeError",
          "value" => "invoice failed",
          "mechanism" => %{"type" => "django", "handled" => false},
          "stacktrace" => %{
            "frames" => [
              %{
                "filename" => "/srv/app/billing/helpers.py",
                "function" => "coerce_total",
                "module" => "billing.helpers",
                "lineno" => 18,
                "in_app" => true,
                "pre_context" => [
                  "subtotal = line_items_total(items)",
                  "tax = calculate_tax(subtotal)"
                ],
                "context_line" => "invoice_total = subtotal + tax",
                "post_context" => ["return invoice_total"],
                "vars" => %{
                  "subtotal" => "100.00",
                  "tax" => "8.00",
                  "invoice_total" => "108.00"
                }
              },
              %{
                "filename" =>
                  "/venv/lib/python3.12/site-packages/django/core/handlers/exception.py",
                "function" => "inner",
                "module" => "django.core.handlers.exception",
                "lineno" => 55,
                "in_app" => false,
                "pre_context" => ["response = get_response(request)"],
                "context_line" => "return response",
                "post_context" => ["except Exception: raise"],
                "vars" => %{"middleware" => "ExceptionMiddleware"}
              },
              %{
                "filename" => "/srv/app/billing/views.py",
                "function" => "checkout",
                "module" => "billing.views",
                "lineno" => 42,
                "in_app" => true,
                "pre_context" => [
                  "invoice_total = coerce_total(cart.items)",
                  "if invoice_total <= 0:"
                ],
                "context_line" => "raise RuntimeError(\"invoice failed\")",
                "post_context" => ["return render(request, \"checkout.html\")"],
                "vars" => %{
                  "current_user" => "alice@example.com",
                  "cart_id" => "cart_123"
                }
              }
            ]
          }
        }
      ],
      breadcrumbs: [
        %{
          "timestamp" => DateTime.to_iso8601(timestamp),
          "type" => "log",
          "category" => "query",
          "message" => "Loaded cart",
          "data" => %{"cart_id" => "cart_123"}
        },
        %{
          "timestamp" => DateTime.to_iso8601(timestamp),
          "type" => "navigation",
          "category" => "ui.click",
          "message" => "Clicked retry payment",
          "data" => %{"button" => "retry"}
        }
      ],
      raw_payload: %{
        "user" => %{"email" => "alice@example.com", "id" => "user_123"},
        "request" => %{
          "url" => request_url,
          "method" => "POST",
          "headers" => %{"Content-Type" => "application/json"},
          "env" => %{"REMOTE_ADDR" => "127.0.0.1"},
          "cookies" => %{"csrftoken" => "[Filtered]"}
        },
        "sdk" => %{
          "name" => "sentry.python.django",
          "version" => "2.54.0",
          "integrations" => ["django", "logging"]
        },
        "contexts" => %{
          "runtime" => runtime_context,
          "os" => %{"name" => "Linux"},
          "browser" => %{"name" => "Firefox"},
          "trace" => %{"trace_id" => "trace-123"}
        },
        "environment" => "test",
        "release" => "billing-web@2026.3.28",
        "server_name" => "billing-web-1",
        "transaction" => "billing.views.checkout",
        "platform" => "python",
        "tags" => %{"environment" => "test", "logger" => "sentry"},
        "extra" => %{"invoice_id" => "inv_123"},
        "modules" => %{"django" => "5.2.0", "sentry-sdk" => "2.54.0"}
      },
      minidump_attachment: nil
    }
  end
end
