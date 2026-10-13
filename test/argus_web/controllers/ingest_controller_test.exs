defmodule ArgusWeb.IngestControllerTest do
  use ArgusWeb.ConnCase, async: true

  import Ecto.Query

  alias Argus.Logs.LogEvent
  alias Argus.Metrics.MetricPoint
  alias Argus.Projects
  alias Argus.Projects.{ErrorEvent, ErrorOccurrence}
  alias Argus.Repo

  import Argus.WorkspaceFixtures

  setup do
    team = team_fixture()
    project = project_fixture(team)
    %{project: project}
  end

  describe "POST /api/:project_id/store/" do
    test "creates an issue and raw occurrence", %{conn: conn, project: project} do
      event_id = "a2f0e6085df44ef7a7c8a67cc55c1234"
      payload = error_payload(event_id)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/#{project.id}/store/?sentry_key=#{project.dsn_key}",
          Jason.encode!(payload)
        )

      assert %{"id" => ^event_id} = json_response(conn, 200)

      issue =
        Repo.one!(from error_event in ErrorEvent, where: error_event.project_id == ^project.id)

      occurrence =
        Repo.one!(
          from error_occurrence in ErrorOccurrence,
            where: error_occurrence.error_event_id == ^issue.id
        )

      assert issue.title == "RuntimeError: boom"
      assert issue.occurrence_count == 1
      assert occurrence.event_id == event_id
    end

    test "filters nested credentials before issue and occurrence storage", %{
      conn: conn,
      project: project
    } do
      event_id = "b2f0e6085df44ef7a7c8a67cc55c1234"

      payload =
        error_payload(event_id, %{
          "request" => %{
            "url" => "https://example.com/jobs/1?access_token=query-secret&view=full",
            "headers" => %{"Authorization" => "Bearer header-secret"}
          },
          "extra" => %{"database" => %{"password" => "extra-secret"}},
          "exception" => %{
            "values" => [
              %{
                "type" => "RuntimeError",
                "value" => "boom",
                "stacktrace" => %{
                  "frames" => [
                    %{
                      "filename" => "job.ex",
                      "function" => "perform",
                      "lineno" => 12,
                      "vars" => %{
                        "conn_params" => %{
                          "host" => "db.example.com",
                          "password" => "frame-secret"
                        }
                      }
                    }
                  ]
                }
              }
            ]
          }
        })

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/#{project.id}/store/?sentry_key=#{project.dsn_key}",
          Jason.encode!(payload)
        )

      assert %{"id" => ^event_id} = json_response(conn, 200)

      issue =
        Repo.one!(from error_event in ErrorEvent, where: error_event.project_id == ^project.id)

      occurrence =
        Repo.one!(
          from error_occurrence in ErrorOccurrence,
            where: error_occurrence.error_event_id == ^issue.id
        )

      assert issue.request["headers"]["Authorization"] == "[Filtered]"

      assert issue.request["url"] ==
               "https://example.com/jobs/1?access_token=[Filtered]&view=full"

      assert issue.extra["database"]["password"] == "[Filtered]"

      assert get_in(occurrence.exception_values, [
               Access.at(0),
               "stacktrace",
               "frames",
               Access.at(0),
               "vars",
               "conn_params",
               "password"
             ]) == "[Filtered]"

      assert get_in(occurrence.raw_payload, ["extra", "database", "password"]) == "[Filtered]"

      assert get_in(occurrence.raw_payload, [
               "exception",
               "values",
               Access.at(0),
               "stacktrace",
               "frames",
               Access.at(0),
               "vars",
               "conn_params",
               "password"
             ]) == "[Filtered]"
    end

    test "upserts by fingerprint and increments occurrence count", %{conn: conn, project: project} do
      first = error_payload("11111111111111111111111111111111")
      second = error_payload("22222222222222222222222222222222")

      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/#{project.id}/store/?sentry_key=#{project.dsn_key}", Jason.encode!(first))

      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/#{project.id}/store/?sentry_key=#{project.dsn_key}", Jason.encode!(second))

      issue =
        Repo.one!(from error_event in ErrorEvent, where: error_event.project_id == ^project.id)

      assert issue.occurrence_count == 2

      assert Repo.aggregate(
               from(o in ErrorOccurrence, where: o.error_event_id == ^issue.id),
               :count,
               :id
             ) == 2
    end

    test "reopens resolved issues when the same fingerprint appears again", %{
      conn: conn,
      project: project
    } do
      first = error_payload("33333333333333333333333333333333")
      second = error_payload("44444444444444444444444444444444")

      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/#{project.id}/store/?sentry_key=#{project.dsn_key}", Jason.encode!(first))

      issue =
        Repo.one!(from error_event in ErrorEvent, where: error_event.project_id == ^project.id)

      {:ok, _resolved_issue} = Projects.update_error_event_status(issue, :resolved)

      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/#{project.id}/store/?sentry_key=#{project.dsn_key}", Jason.encode!(second))

      reopened_issue =
        Repo.one!(from error_event in ErrorEvent, where: error_event.project_id == ^project.id)

      assert reopened_issue.status == :unresolved
      assert reopened_issue.occurrence_count == 2
    end
  end

  describe "POST /api/:project_id/envelope/" do
    test "authenticates using the envelope dsn header when no auth header is present", %{
      conn: conn,
      project: project
    } do
      event_id = "30a2f0e6085d44ef7a7c8a67cc55c999"
      payload = error_payload(event_id)
      payload_json = Jason.encode!(payload)

      envelope =
        build_envelope(
          %{"dsn" => Projects.issue_dsn(project), "event_id" => event_id},
          [%{"type" => "event", "length" => byte_size(payload_json)}, payload_json]
        )

      conn =
        conn
        |> put_req_header("content-type", "application/x-sentry-envelope")
        |> post(~p"/api/#{project.id}/envelope/", envelope)

      assert %{"id" => ^event_id} = json_response(conn, 200)

      issue =
        Repo.one!(from error_event in ErrorEvent, where: error_event.project_id == ^project.id)

      assert issue.title == "RuntimeError: boom"
      assert issue.occurrence_count == 1
    end

    test "accepts javascript event envelopes with bare-list breadcrumbs", %{
      conn: conn,
      project: project
    } do
      event_id = "0263971278634e52b718cbb944acda14"

      breadcrumbs = [
        %{
          "timestamp" => 1_778_091_981.028,
          "category" => "navigation",
          "data" => %{
            "from" => "/test",
            "to" => "/test",
            "authorization" => "Bearer breadcrumb-secret"
          }
        },
        %{
          "timestamp" => 1_778_092_141.755,
          "category" => "ui.click",
          "message" => "div.d-flex.gap-2.flex-wrap > button.btn.btn-danger[type=\"button\"]"
        },
        "ignored breadcrumb"
      ]

      payload =
        error_payload(event_id, %{
          "platform" => "javascript",
          "sdk" => %{"name" => "sentry.javascript.nextjs", "version" => "10.45.0"},
          "request" => %{"url" => "http://127.0.0.1:3000/test"},
          "breadcrumbs" => breadcrumbs,
          "exception" => %{
            "values" => [
              %{
                "type" => "Error",
                "value" => "Sentry test client error from /test page",
                "stacktrace" => %{
                  "frames" => [
                    %{
                      "filename" => "pages\\test\\index.js",
                      "function" => "throwClientError",
                      "in_app" => true,
                      "lineno" => 24,
                      "vars" => %{"token" => "frame-secret"}
                    }
                  ]
                }
              }
            ]
          }
        })

      payload_json = Jason.encode!(payload)

      envelope =
        build_envelope(
          %{
            "event_id" => event_id,
            "sent_at" => "2026-05-06T18:29:02.171Z",
            "sdk" => %{"name" => "sentry.javascript.nextjs", "version" => "10.45.0"}
          },
          [%{"type" => "event"}, payload_json]
        )

      conn =
        conn
        |> put_req_header("content-type", "application/x-sentry-envelope")
        |> post(~p"/api/#{project.id}/envelope/?sentry_key=#{project.dsn_key}", envelope)

      assert %{"id" => ^event_id} = json_response(conn, 200)

      issue =
        Repo.one!(from error_event in ErrorEvent, where: error_event.project_id == ^project.id)

      occurrence =
        Repo.one!(
          from error_occurrence in ErrorOccurrence,
            where: error_occurrence.error_event_id == ^issue.id
        )

      assert issue.title == "Error: Sentry test client error from /test page"

      assert get_in(occurrence.breadcrumbs, [Access.at(0), "data", "authorization"]) ==
               "[Filtered]"

      assert get_in(occurrence.breadcrumbs, [Access.at(0), "data", "from"]) == "/test"

      assert get_in(occurrence.exception_values, [
               Access.at(0),
               "stacktrace",
               "frames",
               Access.at(0),
               "vars",
               "token"
             ]) == "[Filtered]"
    end

    test "creates log events from envelope log items", %{conn: conn, project: project} do
      log_payload =
        Jason.encode!(%{
          "items" => [
            %{
              "timestamp" => DateTime.to_iso8601(DateTime.utc_now(:second)),
              "level" => "warning",
              "body" =>
                "database unavailable at postgresql://worker:log-secret@db.example.com/app",
              "trace_id" => "trace-1",
              "span_id" => "span-1",
              "attributes" => %{
                "logger.name" => "Argus.Logger",
                "sentry.environment" => "test",
                "sentry.sdk.name" => "sentry-elixir",
                "db.password" => "attribute-secret"
              }
            }
          ]
        })

      envelope =
        build_envelope(%{}, [%{"type" => "log", "length" => byte_size(log_payload)}, log_payload])

      conn =
        conn
        |> put_req_header("content-type", "application/x-sentry-envelope")
        |> put_req_header("x-sentry-auth", "Sentry sentry_key=#{project.dsn_key}")
        |> post(~p"/api/#{project.id}/envelope/", envelope)

      assert response(conn, 200) == ""

      log_event =
        Repo.one!(from(log_event in LogEvent, where: log_event.project_id == ^project.id))

      assert log_event.message ==
               "database unavailable at postgresql://worker:[Filtered]@db.example.com/app"

      assert log_event.level == :warning
      assert log_event.logger_name == "Argus.Logger"
      assert log_event.metadata["attributes"]["db.password"] == "[Filtered]"
    end

    test "creates log events from python sdk log envelopes with typed attributes", %{
      conn: conn,
      project: project
    } do
      log_payload =
        Jason.encode!(%{
          "items" => [
            %{
              "timestamp" => 1_774_736_795.7555397,
              "trace_id" => "bb8e667ffaba4703bb9b10bc5ff7099f",
              "span_id" => "b8a25c2fa7e15e4c",
              "level" => "info",
              "body" => "test sentry log",
              "attributes" => %{
                "logger.name" => %{"value" => "sentry", "type" => "string"},
                "sentry.environment" => %{"value" => "production", "type" => "string"},
                "sentry.sdk.name" => %{"value" => "sentry.python", "type" => "string"},
                "sentry.sdk.version" => %{"value" => "2.56.0", "type" => "string"}
              }
            },
            %{
              "timestamp" => 1_774_736_795.7559686,
              "trace_id" => "bb8e667ffaba4703bb9b10bc5ff7099f",
              "span_id" => "b8a25c2fa7e15e4c",
              "level" => "warn",
              "body" => "test sentry log",
              "attributes" => %{
                "logger.name" => %{"value" => "sentry", "type" => "string"},
                "sentry.environment" => %{"value" => "production", "type" => "string"},
                "sentry.sdk.name" => %{"value" => "sentry.python", "type" => "string"},
                "sentry.sdk.version" => %{"value" => "2.56.0", "type" => "string"}
              }
            }
          ]
        })

      envelope =
        build_envelope(
          %{"dsn" => Projects.issue_dsn(project), "sent_at" => "2026-03-28T22:26:35.758741Z"},
          [%{"type" => "log", "item_count" => 2}, log_payload]
        )

      conn =
        conn
        |> put_req_header("content-type", "application/x-sentry-envelope")
        |> post(~p"/api/#{project.id}/envelope/", envelope)

      assert response(conn, 200) == ""

      log_events =
        Repo.all(
          from log_event in LogEvent,
            where: log_event.project_id == ^project.id,
            order_by: [asc: log_event.id]
        )

      assert Enum.map(log_events, & &1.level) == [:info, :warning]
      assert Enum.map(log_events, & &1.message) == ["test sentry log", "test sentry log"]
      assert Enum.all?(log_events, &(&1.logger_name == "sentry"))
      assert Enum.all?(log_events, &(&1.environment == "production"))
      assert Enum.all?(log_events, &(&1.sdk_name == "sentry.python"))
    end

    test "creates metric points from python sdk trace metric envelopes", %{
      conn: conn,
      project: project
    } do
      timestamp = DateTime.utc_now(:second)

      metric_payload =
        Jason.encode!(%{
          "items" => [
            %{
              "timestamp" => DateTime.to_unix(timestamp) + 0.7555397,
              "trace_id" => "bb8e667ffaba4703bb9b10bc5ff7099f",
              "span_id" => "b8a25c2fa7e15e4c",
              "name" => "queue.depth",
              "type" => "gauge",
              "value" => 42,
              "unit" => "item",
              "attributes" => %{
                "queue" => %{"value" => "default", "type" => "string"},
                "active" => %{"value" => true, "type" => "boolean"},
                "api_key" => %{"value" => "metric-secret", "type" => "string"},
                "database_url" => %{
                  "value" => "postgresql://worker:metric-url-secret@db.example.com/app",
                  "type" => "string"
                }
              }
            },
            %{"name" => "ignored.metric", "type" => "set", "value" => 1}
          ]
        })

      envelope =
        build_envelope(
          %{"dsn" => Projects.issue_dsn(project), "sent_at" => "2026-03-28T22:26:35.758741Z"},
          [
            %{
              "type" => "trace_metric",
              "item_count" => 2,
              "content_type" => "application/vnd.sentry.items.trace-metric+json"
            },
            metric_payload
          ]
        )

      conn =
        conn
        |> put_req_header("content-type", "application/x-sentry-envelope")
        |> post(~p"/api/#{project.id}/envelope/", envelope)

      assert response(conn, 200) == ""

      metric_point =
        Repo.one!(from metric_point in MetricPoint, where: metric_point.project_id == ^project.id)

      assert metric_point.timestamp == timestamp
      assert metric_point.name == "queue.depth"
      assert metric_point.type == :gauge
      assert metric_point.value == 42.0
      assert metric_point.unit == "item"
      assert metric_point.trace_id == "bb8e667ffaba4703bb9b10bc5ff7099f"
      assert metric_point.span_id == "b8a25c2fa7e15e4c"

      assert metric_point.attributes == %{
               "queue" => "default",
               "active" => true,
               "api_key" => "[Filtered]",
               "database_url" => "postgresql://worker:[Filtered]@db.example.com/app"
             }

      assert get_in(metric_point.raw_payload, ["attributes", "api_key"]) == "[Filtered]"

      assert get_in(metric_point.raw_payload, ["attributes", "database_url", "value"]) ==
               "postgresql://worker:[Filtered]@db.example.com/app"
    end

    test "accepts brotli-compressed envelopes", %{conn: conn, project: project} do
      event_id = "d530a2f0e60844ef7a7c8a67cc55c111"

      payload =
        event_id
        |> error_payload(%{"timestamp" => "2026-03-28T22:21:20.872770Z"})
        |> Jason.encode!()

      envelope =
        build_envelope(
          %{"event_id" => event_id, "dsn" => Projects.issue_dsn(project)},
          [%{"type" => "event", "length" => byte_size(payload)}, payload]
        )

      conn =
        conn
        |> put_req_header("content-type", "application/x-sentry-envelope")
        |> put_req_header("content-encoding", "br")
        |> post(~p"/api/#{project.id}/envelope/", brotli_encode(envelope))

      assert %{"id" => ^event_id} = json_response(conn, 200)

      issue =
        Repo.one!(from error_event in ErrorEvent, where: error_event.project_id == ^project.id)

      occurrence =
        Repo.one!(
          from error_occurrence in ErrorOccurrence,
            where: error_occurrence.error_event_id == ^issue.id
        )

      assert issue.last_seen_at == ~U[2026-03-28 22:21:20Z]
      assert occurrence.timestamp == ~U[2026-03-28 22:21:20Z]
    end

    test "rejects invalid DSN keys in the auth plug", %{conn: conn, project: project} do
      conn =
        conn
        |> put_req_header("content-type", "application/x-sentry-envelope")
        |> put_req_header("x-sentry-auth", "Sentry sentry_key=wrong-key")
        |> post(~p"/api/#{project.id}/envelope/", "{}\n")

      assert json_response(conn, 403)["detail"] == "Project not found or key incorrect"
    end

    test "stores events whose title, culprit, url and fingerprint exceed 255 chars", %{
      conn: conn,
      project: project
    } do
      event_id = "40a2f0e6085d44ef7a7c8a67cc55c999"
      long_message = String.duplicate("very long exception message ", 40)
      long_url = "https://example.com/search?q=" <> String.duplicate("x", 400)

      payload =
        error_payload(event_id, %{
          "exception" => %{
            "values" => [%{"type" => "RuntimeError", "value" => long_message}]
          },
          "request" => %{"url" => long_url}
        })

      payload_json = Jason.encode!(payload)

      conn =
        conn
        |> put_req_header("content-type", "application/x-sentry-envelope")
        |> post(
          ~p"/api/#{project.id}/envelope/?sentry_key=#{project.dsn_key}",
          build_envelope(
            %{"event_id" => event_id},
            [%{"type" => "event", "length" => byte_size(payload_json)}, payload_json]
          )
        )

      assert %{"id" => ^event_id} = json_response(conn, 200)

      issue =
        Repo.one!(from error_event in ErrorEvent, where: error_event.project_id == ^project.id)

      assert issue.title == "RuntimeError: " <> long_message
      assert issue.culprit == long_url
      assert "v2:" <> hash = issue.fingerprint
      assert String.length(hash) == 64

      occurrence = Repo.one!(from o in ErrorOccurrence, where: o.error_event_id == ^issue.id)
      assert occurrence.request_url == long_url
    end

    test "groups repeated long-fingerprint events into one issue", %{
      conn: conn,
      project: project
    } do
      long_message = String.duplicate("repeated long message ", 30)

      for event_id <- ["50a2f0e6085d44ef7a7c8a67cc55c991", "50a2f0e6085d44ef7a7c8a67cc55c992"] do
        payload_json =
          event_id
          |> error_payload(%{
            "exception" => %{"values" => [%{"type" => "RuntimeError", "value" => long_message}]}
          })
          |> Jason.encode!()

        conn
        |> put_req_header("content-type", "application/x-sentry-envelope")
        |> post(
          ~p"/api/#{project.id}/envelope/?sentry_key=#{project.dsn_key}",
          build_envelope(
            %{"event_id" => event_id},
            [%{"type" => "event", "length" => byte_size(payload_json)}, payload_json]
          )
        )
        |> json_response(200)
      end

      assert [%ErrorEvent{occurrence_count: 2}] =
               Repo.all(
                 from error_event in ErrorEvent, where: error_event.project_id == ^project.id
               )
    end

    test "groups exceptions with the same frames despite variable messages", %{
      conn: conn,
      project: project
    } do
      deadlock = fn pid, tx ->
        "deadlock detected\nDETAIL:  Process #{pid} waits for ShareLock on transaction #{tx}; " <>
          "blocked by process #{pid + 2}.\nCONTEXT:  while updating tuple (#{rem(pid, 50)},2)"
      end

      frames = [
        %{"module" => "chancy.worker", "function" => "_maintain_updates", "lineno" => 503},
        %{"module" => "psycopg.cursor_async", "function" => "executemany", "lineno" => 148}
      ]

      for {event_id, pid, tx, lineno} <- [
            {"70a2f0e6085d44ef7a7c8a67cc55c991", 9477, 43_307_338, 148},
            {"70a2f0e6085d44ef7a7c8a67cc55c992", 64_005, 43_232_893, 150}
          ] do
        frames = List.update_at(frames, 1, &Map.put(&1, "lineno", lineno))

        post_event(conn, project, event_id, %{
          "exception" => %{
            "values" => [
              %{
                "type" => "DeadlockDetected",
                "value" => deadlock.(pid, tx),
                "stacktrace" => %{"frames" => frames}
              }
            ]
          }
        })
      end

      assert [%ErrorEvent{occurrence_count: 2}] = project_issues(project)
    end

    test "keeps exceptions raised from different frames apart", %{conn: conn, project: project} do
      for {event_id, function} <- [
            {"71a2f0e6085d44ef7a7c8a67cc55c991", "perform"},
            {"71a2f0e6085d44ef7a7c8a67cc55c992", "enqueue"}
          ] do
        post_event(conn, project, event_id, %{
          "exception" => %{
            "values" => [
              %{
                "type" => "RuntimeError",
                "value" => "boom",
                "stacktrace" => %{
                  "frames" => [%{"filename" => "job.ex", "function" => function}]
                }
              }
            ]
          }
        })
      end

      assert [%ErrorEvent{occurrence_count: 1}, %ErrorEvent{occurrence_count: 1}] =
               project_issues(project)
    end

    test "groups only by in-app frames when the SDK marks them", %{
      conn: conn,
      project: project
    } do
      for {event_id, library_function} <- [
            {"72a2f0e6085d44ef7a7c8a67cc55c991", "call"},
            {"72a2f0e6085d44ef7a7c8a67cc55c992", "call_with_retry"}
          ] do
        post_event(conn, project, event_id, %{
          "exception" => %{
            "values" => [
              %{
                "type" => "RuntimeError",
                "value" => "boom",
                "stacktrace" => %{
                  "frames" => [
                    %{"module" => "app.jobs", "function" => "perform", "in_app" => true},
                    %{"module" => "lib.http", "function" => library_function, "in_app" => false}
                  ]
                }
              }
            ]
          }
        })
      end

      assert [%ErrorEvent{occurrence_count: 2}] = project_issues(project)
    end

    test "groups messages and frameless exceptions with variable ids", %{
      conn: conn,
      project: project
    } do
      post_event(conn, project, "73a2f0e6085d44ef7a7c8a67cc55c991", %{
        "exception" => nil,
        "message" =>
          "Order 1234 failed for 6f1c2a3e-1b2c-4d5e-8f90-1234567890ab at 0x7faae5d5d550"
      })

      post_event(conn, project, "73a2f0e6085d44ef7a7c8a67cc55c992", %{
        "exception" => nil,
        "message" => "Order 98 failed for 0a1b2c3d-4e5f-4a6b-9c8d-0123456789ef at 0x7fab40df7950"
      })

      for {event_id, id} <- [
            {"73a2f0e6085d44ef7a7c8a67cc55c993", 1},
            {"73a2f0e6085d44ef7a7c8a67cc55c994", 22}
          ] do
        post_event(conn, project, event_id, %{
          "exception" => %{"values" => [%{"type" => "KeyError", "value" => "missing #{id}"}]}
        })
      end

      assert [%ErrorEvent{occurrence_count: 2}, %ErrorEvent{occurrence_count: 2}] =
               project_issues(project)
    end

    test "groups by the SDK fingerprint, expanding {{ default }}", %{
      conn: conn,
      project: project
    } do
      post_event(conn, project, "74a2f0e6085d44ef7a7c8a67cc55c991", %{
        "fingerprint" => ["billing", "timeout"]
      })

      post_event(conn, project, "74a2f0e6085d44ef7a7c8a67cc55c992", %{
        "fingerprint" => ["billing", "timeout"],
        "exception" => %{"values" => [%{"type" => "TimeoutError", "value" => "slow"}]}
      })

      post_event(conn, project, "74a2f0e6085d44ef7a7c8a67cc55c993", %{
        "fingerprint" => ["{{ default }}", "tenant-a"]
      })

      post_event(conn, project, "74a2f0e6085d44ef7a7c8a67cc55c994", %{
        "fingerprint" => ["{{ default }}", "tenant-b"]
      })

      assert [2, 1, 1] =
               project
               |> project_issues()
               |> Enum.map(& &1.occurrence_count)
               |> Enum.sort(:desc)
    end

    test "moves an issue with a pre-v2 fingerprint to the new one", %{
      conn: conn,
      project: project
    } do
      payload = error_payload("75a2f0e6085d44ef7a7c8a67cc55c991")
      legacy_issue = issue_fixture(project, %{fingerprint: "RuntimeError|boom|job.ex"})
      assert legacy_issue.fingerprint == Argus.Ingest.legacy_fingerprint_for_payload(payload)

      post_event(conn, project, payload["event_id"], payload)

      assert [issue] = project_issues(project)
      assert issue.id == legacy_issue.id
      assert issue.fingerprint == Argus.Ingest.fingerprint_for_payload(payload)
      assert issue.occurrence_count == legacy_issue.occurrence_count + 1
    end

    test "reads envelopes larger than a single read_body chunk", %{
      conn: conn,
      project: project
    } do
      event_id = "60a2f0e6085d44ef7a7c8a67cc55c999"
      # Plug.Conn.read_body returns {:more, ...} past 8_000_000 bytes by default.
      padding = String.duplicate("a", 8_500_000)

      payload_json =
        event_id |> error_payload(%{"extra" => %{"blob" => padding}}) |> Jason.encode!()

      conn =
        conn
        |> put_req_header("content-type", "application/x-sentry-envelope")
        |> post(
          ~p"/api/#{project.id}/envelope/?sentry_key=#{project.dsn_key}",
          build_envelope(
            %{"event_id" => event_id},
            [%{"type" => "event", "length" => byte_size(payload_json)}, payload_json]
          )
        )

      assert %{"id" => ^event_id} = json_response(conn, 200)
    end
  end

  defp post_event(conn, project, event_id, overrides) do
    payload_json = event_id |> error_payload(overrides) |> Jason.encode!()

    conn
    |> put_req_header("content-type", "application/x-sentry-envelope")
    |> post(
      ~p"/api/#{project.id}/envelope/?sentry_key=#{project.dsn_key}",
      build_envelope(
        %{"event_id" => event_id},
        [%{"type" => "event", "length" => byte_size(payload_json)}, payload_json]
      )
    )
    |> json_response(200)
  end

  defp project_issues(project) do
    Repo.all(from error_event in ErrorEvent, where: error_event.project_id == ^project.id)
  end

  defp error_payload(event_id, overrides \\ %{}) do
    Map.merge(
      %{
        "event_id" => event_id,
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now(:second)),
        "level" => "error",
        "platform" => "elixir",
        "sdk" => %{"name" => "sentry-elixir", "version" => "1.0.0"},
        "request" => %{"url" => "https://example.com/jobs/1"},
        "contexts" => %{"runtime" => %{"name" => "BEAM"}},
        "tags" => %{"environment" => "test"},
        "extra" => %{"job_id" => 1},
        "exception" => %{
          "values" => [
            %{
              "type" => "RuntimeError",
              "value" => "boom",
              "stacktrace" => %{
                "frames" => [
                  %{"filename" => "job.ex", "function" => "perform", "lineno" => 12}
                ]
              }
            }
          ]
        }
      },
      overrides
    )
  end

  defp build_envelope(headers, [item_headers, payload]) do
    Jason.encode!(headers) <> "\n" <> Jason.encode!(item_headers) <> "\n" <> payload
  end

  defp brotli_encode(data) do
    case :brotli.encode(data) do
      {:ok, encoded} -> encoded
      encoded when is_binary(encoded) -> encoded
    end
  end
end
