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

    project =
      configure_webhook!(project, ~s({
        "text": "{{event_label}} in {{project.name}}: {{issue.message}}",
        "issue": "{{issue}}",
        "tags": "{{tags}}",
        "missing": "{{missing.path}}"
      }))
      |> Repo.preload(team: [team_members: :user])

    issue = Repo.preload(issue, assignee: [], project: [team: [team_members: :user]])
    issue = %{issue | project: project}

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
    assert payload["text"] == "A new issue was detected in #{project.name}: Checkout broke"
    assert payload["issue"]["title"] == issue.title
    assert payload["issue"]["request_path"] == "/jobs/1"
    assert payload["tags"] == %{"environment" => "test"}
    assert payload["missing"] == nil
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

  test "delivers assignment notifications to the new assignee and posts assignment webhook metadata" do
    %{team: team, project: project} = workspace_fixture()
    actor = user_fixture(%{name: "Assigning User"})
    assignee = user_fixture(%{name: "Assigned Person"})
    fallback_member = user_fixture(%{name: "Fallback Member"})

    membership_fixture(team, actor)
    membership_fixture(team, assignee)
    membership_fixture(team, fallback_member)

    issue = insert_issue(project, assignee_id: assignee.id)
    flush_emails()

    project =
      configure_webhook!(project, lifecycle_template())
      |> Repo.preload(team: [team_members: :user])

    issue = Repo.preload(issue, assignee: [], project: [team: [team_members: :user]])
    issue = %{issue | project: project}

    Req.Test.stub(Argus.IssueWebhookStub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(self(), {:webhook_request, Jason.decode!(body)})
      Req.Test.json(conn, %{"ok" => true})
    end)

    assert :ok =
             IssueNotifier.deliver(issue, :assigned,
               actor: actor,
               change: %{field: :assignee_id, from: nil, to: assignee.id}
             )

    assert_email_sent(fn email ->
      email.to == [{assignee.name, assignee.email}] and
        email.subject =~ "Issue assigned" and
        email.text_body =~ "Changed by: #{actor.name}"
    end)

    refute_email_sent(fn email ->
      email.to == [{fallback_member.name, fallback_member.email}] and
        email.subject =~ "Issue assigned"
    end)

    assert_receive {:webhook_request, payload}
    assert payload["event"] == "issue_assigned"
    assert payload["event_label"] == "An issue was assigned"
    assert payload["actor_email"] == actor.email
    assert payload["assignee_email"] == assignee.email
    assert payload["change_field"] == "assignee_id"
    assert payload["change_from"] == nil
    assert payload["change_to"] == assignee.id
  end

  test "delivers unassignment notifications to confirmed team members and posts the webhook" do
    %{team: team, project: project} = workspace_fixture()
    actor = user_fixture(%{name: "Assigning User"})
    assignee = user_fixture(%{name: "Assigned Person"})
    confirmed_member = user_fixture(%{name: "Confirmed Member"})
    pending_member = pending_user_fixture(%{name: "Pending Member"})

    membership_fixture(team, actor)
    membership_fixture(team, assignee)
    membership_fixture(team, confirmed_member)
    membership_fixture(team, pending_member)

    issue = insert_issue(project)
    flush_emails()

    project =
      configure_webhook!(project, lifecycle_template())
      |> Repo.preload(team: [team_members: :user])

    issue = Repo.preload(issue, assignee: [], project: [team: [team_members: :user]])
    issue = %{issue | project: project}

    Req.Test.stub(Argus.IssueWebhookStub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(self(), {:webhook_request, Jason.decode!(body)})
      Req.Test.json(conn, %{"ok" => true})
    end)

    assert :ok =
             IssueNotifier.deliver(issue, :unassigned,
               actor: actor,
               change: %{field: :assignee_id, from: assignee.id, to: nil}
             )

    assert_email_sent(fn email ->
      email.to == [{confirmed_member.name, confirmed_member.email}] and
        email.subject =~ "Issue unassigned"
    end)

    refute_email_sent(fn email ->
      email.to == [{pending_member.name, pending_member.email}] and
        email.subject =~ "Issue unassigned"
    end)

    assert_receive {:webhook_request, payload}
    assert payload["event"] == "issue_unassigned"
    assert payload["actor_email"] == actor.email
    assert payload["change_field"] == "assignee_id"
    assert payload["change_from"] == assignee.id
    assert payload["change_to"] == nil
  end

  test "delivers status notifications to the assignee and posts status webhook metadata" do
    %{team: team, project: project} = workspace_fixture()
    actor = user_fixture(%{name: "Resolving User"})
    assignee = user_fixture(%{name: "Assigned Person"})
    fallback_member = user_fixture(%{name: "Fallback Member"})

    membership_fixture(team, actor)
    membership_fixture(team, assignee)
    membership_fixture(team, fallback_member)

    issue = insert_issue(project, assignee_id: assignee.id)
    flush_emails()

    project =
      configure_webhook!(project, lifecycle_template())
      |> Repo.preload(team: [team_members: :user])

    issue =
      issue
      |> Repo.preload(assignee: [], project: [team: [team_members: :user]])
      |> Map.put(:status, :resolved)

    issue = %{issue | project: project}

    Req.Test.stub(Argus.IssueWebhookStub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(self(), {:webhook_request, Jason.decode!(body)})
      Req.Test.json(conn, %{"ok" => true})
    end)

    assert :ok =
             IssueNotifier.deliver(issue, :resolved,
               actor: actor,
               change: %{field: :status, from: :unresolved, to: :resolved}
             )

    assert_email_sent(fn email ->
      email.to == [{assignee.name, assignee.email}] and
        email.subject =~ "Issue resolved" and
        email.text_body =~ "Change: status from unresolved to resolved"
    end)

    refute_email_sent(fn email ->
      email.to == [{fallback_member.name, fallback_member.email}] and
        email.subject =~ "Issue resolved"
    end)

    assert_receive {:webhook_request, payload}
    assert payload["event"] == "issue_resolved"
    assert payload["actor_email"] == actor.email
    assert payload["assignee_email"] == assignee.email
    assert payload["change_field"] == "status"
    assert payload["change_from"] == "unresolved"
    assert payload["change_to"] == "resolved"
  end

  test "context assignment changes trigger targeted emails and webhooks" do
    %{user: actor, team: team, project: project} = workspace_fixture()
    assignee = user_fixture(%{name: "Assigned Person"})
    fallback_member = user_fixture(%{name: "Fallback Member"})
    membership_fixture(team, assignee)
    membership_fixture(team, fallback_member)
    issue = insert_issue(project)
    flush_emails()

    project = configure_webhook!(project, lifecycle_template())
    test_pid = self()

    Req.Test.stub(Argus.IssueWebhookStub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:webhook_request, Jason.decode!(body)})
      Req.Test.json(conn, %{"ok" => true})
    end)

    assert {:ok, assigned_issue} =
             Projects.assign_error_event(actor, issue, assignee.id, sync?: true)

    assert assigned_issue.assignee_id == assignee.id

    assert_email_sent(fn email ->
      email.to == [{assignee.name, assignee.email}] and
        email.subject =~ "Issue assigned"
    end)

    refute_email_sent(fn email ->
      email.to == [{fallback_member.name, fallback_member.email}] and
        email.subject =~ "Issue assigned"
    end)

    assert_receive {:webhook_request, payload}
    assert payload["event"] == "issue_assigned"
    assert payload["issue_id"] == assigned_issue.id
    assert payload["actor_email"] == actor.email
    assert payload["assignee_email"] == assignee.email
    assert payload["change_to"] == assignee.id

    assert project.id == assigned_issue.project_id
  end

  test "bulk status changes notify only changed issues" do
    %{user: actor, project: project} = workspace_fixture()
    unresolved_issue = insert_issue(project)
    resolved_issue = insert_issue(project, fingerprint: "RuntimeError|resolved|billing.jobs.sync")

    {:ok, resolved_issue} = Projects.update_error_event_status(resolved_issue, :resolved)
    flush_emails()

    project = configure_webhook!(project, lifecycle_template())
    test_pid = self()

    Req.Test.stub(Argus.IssueWebhookStub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:webhook_request, Jason.decode!(body)})
      Req.Test.json(conn, %{"ok" => true})
    end)

    assert 1 =
             Projects.bulk_update_error_event_status(
               project,
               [unresolved_issue.id, resolved_issue.id],
               :resolved,
               actor: actor,
               sync?: true
             )

    assert_email_sent(fn email ->
      email.to == [{actor.name, actor.email}] and
        email.subject =~ "Issue resolved"
    end)

    assert_receive {:webhook_request, payload}
    assert payload["event"] == "issue_resolved"
    assert payload["issue_id"] == unresolved_issue.id
    assert payload["actor_email"] == actor.email
    assert payload["change_from"] == "unresolved"
    assert payload["change_to"] == "resolved"

    refute_receive {:webhook_request, _payload}
  end

  test "does not post a webhook when the project has no webhook configured" do
    %{project: project} = workspace_fixture()
    issue = insert_issue(project)
    issue = Repo.preload(issue, assignee: [], project: [team: [team_members: :user]])

    Req.Test.stub(Argus.IssueWebhookStub, fn conn ->
      send(self(), :unexpected_webhook_request)
      Req.Test.json(conn, %{"ok" => true})
    end)

    assert :ok = IssueNotifier.deliver(issue, :created)

    refute_receive :unexpected_webhook_request
  end

  test "sends a project webhook test payload through the configured template" do
    %{project: project} = workspace_fixture()

    project =
      configure_webhook!(
        project,
        ~s({"text":"{{event_label}} for {{project.slug}}","project_id":"{{project.id}}"})
      )

    Req.Test.stub(Argus.IssueWebhookStub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(self(), {:webhook_test_request, Jason.decode!(body)})
      Req.Test.json(conn, %{"ok" => true})
    end)

    assert :ok = IssueNotifier.send_test_webhook(project)

    assert_receive {:webhook_test_request, payload}
    assert payload["text"] == "Test issue webhook for #{project.slug}"
    assert payload["project_id"] == project.id
  end

  test "returns not configured for project webhook tests without a URL" do
    %{project: project} = workspace_fixture()

    assert {:error, :not_configured} = IssueNotifier.send_test_webhook(project)
  end

  defp insert_issue(project, attrs \\ []) do
    timestamp = ~U[2026-03-28 22:00:00Z]

    issue_attrs = %{
      fingerprint: Keyword.get(attrs, :fingerprint, "RuntimeError|boom|billing.jobs.sync"),
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

  defp configure_webhook!(project, template) do
    {:ok, project} =
      Projects.update_project_webhook(project, %{
        "webhook_url" => "https://hooks.argus.test/issues",
        "webhook_body_template" => template
      })

    project
  end

  defp lifecycle_template do
    ~s({
      "event": "{{event}}",
      "event_label": "{{event_label}}",
      "issue_id": "{{issue.id}}",
      "actor_email": "{{actor.email}}",
      "assignee_email": "{{assignee.email}}",
      "change_field": "{{change.field}}",
      "change_from": "{{change.from}}",
      "change_to": "{{change.to}}"
    })
  end
end
