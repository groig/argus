alias Argus.Accounts
alias Argus.Accounts.User
alias Argus.Logs
alias Argus.Logs.LogEvent
alias Argus.Projects
alias Argus.Projects.{ErrorEvent, ErrorOccurrence, Project}
alias Argus.Repo
alias Argus.Teams
alias Argus.Teams.Team

import Ecto.Query

manifest_path = System.get_env("ARGUS_SCREENSHOT_MANIFEST_PATH") || "/tmp/argus-screenshot-manifest.json"
screenshot_password = System.get_env("ARGUS_SCREENSHOT_PASSWORD") || "screenshots123"

ensure_user = fn email, name, role, password ->
  case Repo.get_by(User, email: email) do
    nil ->
      {:ok, user} =
        Accounts.create_user(%{
          email: email,
          name: name,
          role: role,
          password: password,
          password_confirmation: password,
          confirmed: true
        })

      user

    %User{} = user ->
      user =
        user
        |> User.profile_changeset(%{email: email, name: name}, validate_unique: false)
        |> Ecto.Changeset.change(
          role: role,
          confirmed_at: user.confirmed_at || ~U[2026-03-28 18:00:00Z]
        )
        |> Repo.update!()

      if Accounts.get_user_by_email_and_password(email, password) do
        user
      else
        {:ok, {user, _expired_tokens}} =
          Accounts.update_user_password(user, %{
            password: password,
            password_confirmation: password
          })

        user
      end
  end
end

ensure_team = fn name ->
  case Repo.get_by(Team, name: name) do
    nil ->
      {:ok, team} = Teams.create_team(%{name: name})
      team

    %Team{} = team ->
      team
  end
end

ensure_project = fn team, attrs ->
  slug = attrs["slug"]

  case Repo.get_by(Project, slug: slug) do
    nil ->
      {:ok, project} = Projects.create_project(team, attrs)
      project

    %Project{} = project ->
      project
      |> Project.changeset(Map.put(attrs, "team_id", team.id))
      |> Repo.update!()
      |> Repo.preload(:team)
  end
end

reset_project_data = fn project ->
  from(occurrence in ErrorOccurrence, where: occurrence.project_id == ^project.id) |> Repo.delete_all()
  from(issue in ErrorEvent, where: issue.project_id == ^project.id) |> Repo.delete_all()
  from(log_event in LogEvent, where: log_event.project_id == ^project.id) |> Repo.delete_all()
end

capture_occurrence = fn event_id, timestamp, request_url, release, exception_type, exception_value, frames, breadcrumbs, tags, extra ->
  %{
    event_id: event_id,
    timestamp: timestamp,
    request_url: request_url,
    user_context: %{
      "email" => "ari.chen@example.com",
      "id" => "user_ari",
      "username" => "ari"
    },
    exception_values: [
      %{
        "type" => exception_type,
        "value" => exception_value,
        "mechanism" => %{"type" => "django", "handled" => false},
        "stacktrace" => %{"frames" => frames}
      }
    ],
    breadcrumbs: breadcrumbs,
    raw_payload: %{
      "user" => %{
        "email" => "ari.chen@example.com",
        "id" => "user_ari",
        "username" => "ari"
      },
      "request" => %{
        "url" => request_url,
        "method" => "POST",
        "headers" => %{
          "Content-Type" => "application/json",
          "X-Request-Id" => "req_9a7f24"
        },
        "env" => %{"REMOTE_ADDR" => "127.0.0.1"},
        "cookies" => %{"sessionid" => "[Filtered]"}
      },
      "sdk" => %{
        "name" => "sentry.python.django",
        "version" => "2.54.0",
        "integrations" => ["django", "logging", "redis"]
      },
      "contexts" => %{
        "runtime" => %{"name" => "CPython", "version" => "3.12.11"},
        "os" => %{"name" => "Linux", "version" => "6.8.0"},
        "browser" => %{"name" => "Firefox", "version" => "149.0"},
        "trace" => %{
          "trace_id" => "4d0d4a7bc1a14247a8c6c7b1a3be2f6d",
          "span_id" => "93db2afab2dce842"
        }
      },
      "environment" => "production",
      "release" => release,
      "server_name" => "payments-web-1",
      "transaction" => "/checkout/charge",
      "platform" => "python",
      "tags" => tags,
      "extra" => extra,
      "modules" => %{"django" => "5.2.0", "sentry-sdk" => "2.54.0"}
    },
    minidump_attachment: nil
  }
end

create_issue = fn project, issue_attrs, occurrences ->
  [first_occurrence | rest] = occurrences

  {:ok, %{issue: issue}} =
    Projects.upsert_issue_and_occurrence(project, issue_attrs, first_occurrence)

  Enum.reduce(rest, issue, fn occurrence, _current_issue ->
    {:ok, %{issue: updated_issue}} =
      Projects.upsert_issue_and_occurrence(
        project,
        %{issue_attrs | last_seen_at: occurrence.timestamp},
        occurrence
      )

    updated_issue
  end)
end

screenshot_user =
  ensure_user.(
    "screenshots@argus.local",
    "README Operator",
    :member,
    screenshot_password
  )

assignee =
  ensure_user.(
    "ari.chen@argus.local",
    "Ari Chen",
    :member,
    "screenshots123"
  )

team = ensure_team.("Platform")

{:ok, _membership} = Teams.add_member(team, screenshot_user, :admin)
{:ok, _membership} = Teams.add_member(team, assignee, :member)

payments_project =
  ensure_project.(team, %{
    "name" => "Payments API",
    "slug" => "payments-api",
    "dsn_key" => "readmePaymentsKeyA01"
  })

storefront_project =
  ensure_project.(team, %{
    "name" => "Storefront",
    "slug" => "storefront",
    "dsn_key" => "readmeStorefrontKeyB02"
  })

Enum.each([payments_project, storefront_project], reset_project_data)

payments_frames = [
  %{
    "filename" => "/srv/app/payments/gateway.py",
    "function" => "authorize_charge",
    "module" => "payments.gateway",
    "lineno" => 87,
    "in_app" => true,
    "pre_context" => [
      "payload = build_gateway_payload(order)",
      "headers = signed_headers(merchant)"
    ],
    "context_line" => "response = stripe_client.post(\"/charges\", json=payload, headers=headers)",
    "post_context" => ["return normalize_charge_response(response)"],
    "vars" => %{
      "merchant_id" => "\"mrc_4102\"",
      "order_id" => "\"ord_9041\"",
      "payload" => "%{amount: 18900, currency: \"usd\"}"
    }
  },
  %{
    "filename" => "/venv/lib/python3.12/site-packages/django/core/handlers/exception.py",
    "function" => "inner",
    "module" => "django.core.handlers.exception",
    "lineno" => 55,
    "in_app" => false,
    "pre_context" => ["response = get_response(request)"],
    "context_line" => "return response",
    "post_context" => ["except Exception: raise"],
    "vars" => %{"middleware" => "\"ExceptionMiddleware\""}
  },
  %{
    "filename" => "/srv/app/payments/views.py",
    "function" => "charge_checkout",
    "module" => "payments.views",
    "lineno" => 143,
    "in_app" => true,
    "pre_context" => [
      "charge = authorize_charge(order, merchant)",
      "if charge[\"status\"] != \"approved\":"
    ],
    "context_line" => "raise RuntimeError(\"charge checkout failed\")",
    "post_context" => ["return JsonResponse({\"ok\": True})"],
    "vars" => %{
      "current_user" => "\"ari.chen@example.com\"",
      "merchant" => "\"Northwind\"",
      "order_total" => "189.00"
    }
  }
]

payments_breadcrumbs = [
  %{
    "timestamp" => "2026-03-28T22:17:41Z",
    "type" => "log",
    "category" => "query",
    "message" => "Loaded checkout cart",
    "data" => %{"cart_id" => "cart_9041", "duration_ms" => 14}
  },
  %{
    "timestamp" => "2026-03-28T22:17:43Z",
    "type" => "log",
    "category" => "query",
    "message" => "Selected payment source",
    "data" => %{"source" => "visa_4242"}
  }
]

payments_issue_attrs = %{
  fingerprint: "RuntimeError|charge checkout failed|payments.views.charge_checkout",
  title: "Exception: charge checkout failed",
  culprit: "/checkout/charge",
  level: :error,
  platform: "python",
  sdk: %{"name" => "sentry.python.django", "version" => "2.54.0"},
  request: %{"url" => "http://localhost:8000/checkout/charge"},
  contexts: %{
    "runtime" => %{"name" => "CPython", "version" => "3.12.11"},
    "os" => %{"name" => "Linux", "version" => "6.8.0"},
    "browser" => %{"name" => "Firefox", "version" => "149.0"},
    "trace" => %{"trace_id" => "4d0d4a7bc1a14247a8c6c7b1a3be2f6d"}
  },
  tags: %{"environment" => "production", "release" => "payments-web@2026.3.28"},
  extra: %{"order_id" => "ord_9041", "merchant_id" => "mrc_4102"},
  first_seen_at: ~U[2026-03-28 22:05:00Z],
  last_seen_at: ~U[2026-03-28 22:21:00Z],
  occurrence_count: 1,
  status: :unresolved
}

payments_issue =
  create_issue.(payments_project, payments_issue_attrs, [
    capture_occurrence.(
      "evt-payments-001",
      ~U[2026-03-28 22:05:00Z],
      "http://localhost:8000/checkout/charge",
      "payments-web@2026.3.28",
      "RuntimeError",
      "charge checkout failed",
      payments_frames,
      payments_breadcrumbs,
      %{"environment" => "production", "release" => "payments-web@2026.3.28"},
      %{"order_id" => "ord_9041", "merchant_id" => "mrc_4102"}
    ),
    capture_occurrence.(
      "evt-payments-002",
      ~U[2026-03-28 22:12:00Z],
      "http://localhost:8000/checkout/charge",
      "payments-web@2026.3.28",
      "RuntimeError",
      "charge checkout failed",
      payments_frames,
      payments_breadcrumbs,
      %{"environment" => "production", "release" => "payments-web@2026.3.28"},
      %{"order_id" => "ord_9041", "merchant_id" => "mrc_4102"}
    ),
    capture_occurrence.(
      "evt-payments-003",
      ~U[2026-03-28 22:21:00Z],
      "http://localhost:8000/checkout/charge",
      "payments-web@2026.3.28",
      "RuntimeError",
      "charge checkout failed",
      payments_frames,
      payments_breadcrumbs,
      %{"environment" => "production", "release" => "payments-web@2026.3.28"},
      %{"order_id" => "ord_9041", "merchant_id" => "mrc_4102"}
    )
  ])

{:ok, payments_issue} = Projects.assign_error_event(screenshot_user, payments_issue, assignee.id)

create_issue.(payments_project, %{
  fingerprint: "TimeoutError|issuer lookup timed out|payments.issuer.lookup",
  title: "TimeoutError: issuer lookup timed out",
  culprit: "/cards/issuer",
  level: :warning,
  platform: "python",
  sdk: %{"name" => "sentry.python.django", "version" => "2.54.0"},
  request: %{"url" => "http://localhost:8000/cards/issuer"},
  contexts: %{"runtime" => %{"name" => "CPython", "version" => "3.12.11"}},
  tags: %{"environment" => "production"},
  extra: %{"issuer" => "visa"},
  first_seen_at: ~U[2026-03-28 21:43:00Z],
  last_seen_at: ~U[2026-03-28 21:43:00Z],
  occurrence_count: 1,
  status: :resolved
}, [
  capture_occurrence.(
    "evt-payments-warning-001",
    ~U[2026-03-28 21:43:00Z],
    "http://localhost:8000/cards/issuer",
    "payments-web@2026.3.28",
    "TimeoutError",
    "issuer lookup timed out",
    payments_frames,
    payments_breadcrumbs,
    %{"environment" => "production"},
    %{"issuer" => "visa"}
  )
])

create_issue.(storefront_project, %{
  fingerprint: "TypeError|cart line missing price|storefront.cart.render",
  title: "TypeError: cart line missing price",
  culprit: "/cart",
  level: :error,
  platform: "python",
  sdk: %{"name" => "sentry.python.django", "version" => "2.54.0"},
  request: %{"url" => "http://localhost:8000/cart"},
  contexts: %{"runtime" => %{"name" => "CPython", "version" => "3.12.11"}},
  tags: %{"environment" => "production", "release" => "storefront-web@2026.3.28"},
  extra: %{"cart_id" => "cart_11"},
  first_seen_at: ~U[2026-03-28 20:54:00Z],
  last_seen_at: ~U[2026-03-28 20:54:00Z],
  occurrence_count: 1,
  status: :unresolved
}, [
  capture_occurrence.(
    "evt-storefront-001",
    ~U[2026-03-28 20:54:00Z],
    "http://localhost:8000/cart",
    "storefront-web@2026.3.28",
    "TypeError",
    "cart line missing price",
    [
      %{
        "filename" => "/srv/app/storefront/cart.py",
        "function" => "render_cart",
        "module" => "storefront.cart",
        "lineno" => 63,
        "in_app" => true,
        "pre_context" => ["for line in cart.lines:", "  price = line.get(\"price\")"],
        "context_line" => "total += price",
        "post_context" => ["return total"],
        "vars" => %{"line_id" => "\"line_11\"", "price" => "nil"}
      }
    ],
    [
      %{
        "timestamp" => "2026-03-28T20:53:59Z",
        "type" => "log",
        "category" => "query",
        "message" => "Loaded cart lines",
        "data" => %{"cart_id" => "cart_11", "rows" => 4}
      }
    ],
    %{"environment" => "production", "release" => "storefront-web@2026.3.28"},
    %{"cart_id" => "cart_11"}
  )
])

{:ok, log_event} =
  Logs.create_log_event(
    payments_project,
    %{
      level: :warning,
      message: "Payment provider degraded",
      timestamp: ~U[2026-03-28 22:28:25Z],
    metadata: %{
      "attributes" => %{
        "logger.name" => "payments.alerts",
        "code.function_name" => "capture_payment",
        "deployment.environment" => "production",
        "http.route" => "/checkout/charge",
        "payment.provider" => "stripe",
        "sentry.severity_number" => 13
      },
      "context" => %{
        "merchant_id" => "mrc_4102",
        "order_id" => "ord_9041",
        "path" => "/checkout/charge"
      }
    },
    logger_name: "payments.alerts",
    origin: "sentry",
    release: "payments-web@2026.3.28",
    environment: "production",
    sdk_name: "sentry.python.django",
    sdk_version: "2.54.0",
    sequence: 482,
    trace_id: "4d0d4a7bc1a14247a8c6c7b1a3be2f6d",
      span_id: "93db2afab2dce842"
    },
    bypass_rate_limit: true
  )

{:ok, _info_log} =
  Logs.create_log_event(
    payments_project,
    %{
      level: :info,
      message: "Queued capture retry",
      timestamp: ~U[2026-03-28 22:24:18Z],
      metadata: %{
        "attributes" => %{"logger.name" => "payments.jobs", "job.name" => "capture_retry"}
      },
      logger_name: "payments.jobs",
      origin: "sentry",
      release: "payments-web@2026.3.28",
      environment: "production",
      sdk_name: "sentry.python.django",
      sdk_version: "2.54.0"
    },
    bypass_rate_limit: true
  )

{:ok, _storefront_log} =
  Logs.create_log_event(
    storefront_project,
    %{
      level: :info,
      message: "Cart session rebuilt",
      timestamp: ~U[2026-03-28 20:58:12Z],
      metadata: %{"attributes" => %{"logger.name" => "storefront.sessions"}},
      logger_name: "storefront.sessions",
      origin: "sentry",
      release: "storefront-web@2026.3.28",
      environment: "production",
      sdk_name: "sentry.python.django",
      sdk_version: "2.54.0"
    },
    bypass_rate_limit: true
  )

manifest = %{
  "login" => %{
    "email" => screenshot_user.email,
    "password" => screenshot_password
  },
  "routes" => %{
    "dashboard" => "/projects",
    "issue_detail" => "/projects/#{payments_project.slug}/issues/#{payments_issue.id}",
    "log_detail" => "/projects/#{payments_project.slug}/logs/#{log_event.id}"
  }
}

manifest_path
|> Path.dirname()
|> File.mkdir_p!()

File.write!(manifest_path, Jason.encode!(manifest, pretty: true))

IO.puts("Seeded screenshot workspace for #{screenshot_user.email}")
IO.puts("Screenshot manifest written to #{manifest_path}")
