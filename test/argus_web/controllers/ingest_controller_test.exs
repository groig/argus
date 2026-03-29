defmodule ArgusWeb.IngestControllerTest do
  use ArgusWeb.ConnCase, async: true

  import Ecto.Query

  alias Argus.Logs.LogEvent
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

    test "creates log events from envelope log items", %{conn: conn, project: project} do
      log_payload =
        Jason.encode!(%{
          "items" => [
            %{
              "timestamp" => DateTime.to_iso8601(DateTime.utc_now(:second)),
              "level" => "warning",
              "body" => "disk nearly full",
              "trace_id" => "trace-1",
              "span_id" => "span-1",
              "attributes" => %{
                "logger.name" => "Argus.Logger",
                "sentry.environment" => "test",
                "sentry.sdk.name" => "sentry-elixir"
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

      assert log_event.message == "disk nearly full"
      assert log_event.level == :warning
      assert log_event.logger_name == "Argus.Logger"
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
