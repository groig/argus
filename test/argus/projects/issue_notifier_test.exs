defmodule Argus.Projects.IssueNotifierTest do
  use Argus.DataCase, async: false

  import Swoosh.X.TestAssertions

  alias Argus.Projects.IssueNotifier
  alias Argus.Projects
  alias Argus.Repo

  import Argus.AccountsFixtures
  import Argus.WorkspaceFixtures

  setup :set_swoosh_global

  setup do
    previous_config = Application.get_env(:argus, IssueNotifier, [])

    Application.put_env(:argus, IssueNotifier,
      webhook_url: "https://hooks.argus.test/issues",
      req_options: [plug: {Req.Test, Argus.IssueWebhookStub}]
    )

    on_exit(fn ->
      Application.put_env(:argus, IssueNotifier, previous_config || [])
    end)

    :ok
  end

  test "delivers created issue notifications to the assignee and posts the webhook" do
    %{team: team, project: project} = workspace_fixture()
    assignee = user_fixture(%{name: "Assigned Person"})
    fallback_member = user_fixture()
    membership_fixture(team, assignee)
    membership_fixture(team, fallback_member)

    issue = insert_issue(project, assignee_id: assignee.id)
    issue = Repo.preload(issue, assignee: [], project: [team: [team_members: :user]])

    Req.Test.stub(Argus.IssueWebhookStub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(self(), {:webhook_request, Jason.decode!(body)})
      Req.Test.json(conn, %{"ok" => true})
    end)

    assert :ok = IssueNotifier.deliver(issue, :created)

    assert_email_sent(fn email ->
      email.to == [{assignee.name, assignee.email}]
    end)

    refute_email_sent(fn email ->
      email.to == [{fallback_member.name, fallback_member.email}]
    end)

    assert_receive {:webhook_request, payload}
    assert payload["event"] == "issue_created"
    assert payload["issue"]["title"] == issue.title
    assert payload["issue"]["message"] == "Checkout broke"
    assert payload["issue"]["reason"] == "boom"
    assert payload["issue"]["code_path"] == "billing.jobs.sync.perform/2:44"
    assert payload["issue"]["request_path"] == "/jobs/1"
    assert payload["project"]["slug"] == project.slug
    assert payload["assignee"]["id"] == assignee.id
    assert payload["occurrence"]["event_id"] =~ "evt-"
    assert payload["occurrence"]["message"] == "Checkout broke"
    assert payload["occurrence"]["reason"] == "boom"
    assert payload["occurrence"]["code_path"] == "billing.jobs.sync.perform/2:44"
    assert payload["request"]["path"] == "/jobs/1"
  end

  test "notifies confirmed team members when the issue is unassigned" do
    %{team: team, project: project} = workspace_fixture()
    confirmed_member = user_fixture(%{name: "Confirmed Member"})
    pending_member = pending_user_fixture(%{name: "Pending Member"})
    membership_fixture(team, confirmed_member)
    membership_fixture(team, pending_member)

    issue = insert_issue(project)
    issue = Repo.preload(issue, assignee: [], project: [team: [team_members: :user]])

    Req.Test.stub(Argus.IssueWebhookStub, fn conn ->
      Req.Test.json(conn, %{"ok" => true})
    end)

    assert :ok = IssueNotifier.deliver(issue, :reopened)

    assert_email_sent(fn email ->
      email.to == [{confirmed_member.name, confirmed_member.email}]
    end)

    refute_email_sent(fn email ->
      email.to == [{pending_member.name, pending_member.email}]
    end)
  end

  test "sends a dedicated webhook test payload" do
    Req.Test.stub(Argus.IssueWebhookStub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(self(), {:webhook_test_request, Jason.decode!(body)})
      Req.Test.json(conn, %{"ok" => true})
    end)

    assert :ok = IssueNotifier.send_test_webhook()

    assert_receive {:webhook_test_request, payload}
    assert payload["event"] == "webhook_test"
    assert payload["issue"]["message"] == "This is a test webhook from Argus."
    assert payload["issue"]["reason"] == "Test exception for webhook delivery"
    assert payload["issue"]["code_path"] == "ArgusWeb.AdminLive.Index.handle_event/3"
    assert payload["project"]["slug"] == "sample-project"
    assert payload["occurrence"]["message"] == "This is a test webhook from Argus."
    assert payload["occurrence"]["reason"] == "Test exception for webhook delivery"
    assert payload["occurrence"]["code_path"] == "ArgusWeb.AdminLive.Index.handle_event/3"
    assert payload["request"]["path"] == "/admin"
    assert payload["url"] =~ "/admin"
  end

  defp insert_issue(project, attrs \\ []) do
    timestamp = ~U[2026-03-28 22:00:00Z]

    issue_attrs = %{
      fingerprint: "RuntimeError|boom|billing.jobs.sync",
      title: "RuntimeError: boom",
      culprit: "billing.jobs.sync",
      level: :error,
      platform: "elixir",
      sdk: %{"name" => "sentry-elixir", "version" => "1.0.0"},
      request: %{"url" => "https://example.com/jobs/1", "method" => "POST"},
      contexts: %{"runtime" => %{"name" => "BEAM"}},
      tags: %{"environment" => "test"},
      extra: %{"job_id" => "job-123"},
      first_seen_at: timestamp,
      last_seen_at: timestamp,
      occurrence_count: 1,
      status: :unresolved,
      assignee_id: Keyword.get(attrs, :assignee_id)
    }

    occurrence_attrs = %{
      event_id: "evt-#{System.unique_integer([:positive])}",
      timestamp: timestamp,
      request_url: "https://example.com/jobs/1",
      user_context: %{"email" => "jobs@example.com"},
      exception_values: [
        %{
          "type" => "RuntimeError",
          "value" => "boom",
          "mechanism" => %{"handled" => false},
          "stacktrace" => %{
            "frames" => [
              %{
                "function" => "perform/2",
                "module" => "billing.jobs.sync",
                "filename" => "billing/jobs/sync.ex",
                "lineno" => 44,
                "in_app" => true
              }
            ]
          }
        }
      ],
      breadcrumbs: [],
      raw_payload: %{
        "message" => "Checkout broke",
        "request" => %{"url" => "https://example.com/jobs/1", "method" => "POST"},
        "sdk" => issue_attrs.sdk,
        "tags" => issue_attrs.tags,
        "contexts" => issue_attrs.contexts,
        "extra" => issue_attrs.extra
      },
      minidump_attachment: nil
    }

    {:ok, %{issue: issue}} =
      Projects.upsert_issue_and_occurrence(project, issue_attrs, occurrence_attrs)

    issue
  end
end
