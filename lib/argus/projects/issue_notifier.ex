defmodule Argus.Projects.IssueNotifier do
  @moduledoc """
  Email and webhook delivery for issue lifecycle events.

  Delivery runs outside the ingest transaction. If email or webhook delivery fails, Argus still
  stores the issue and returns success to the SDK.
  """

  import Ecto.Query, only: [from: 2]

  require Logger

  alias Argus.Accounts.User
  alias Argus.Mailer
  alias Argus.Projects.{ErrorEvent, ErrorOccurrence}
  alias Argus.Repo

  @task_supervisor Argus.TaskSupervisor

  def configured_webhook_url do
    Application.get_env(:argus, __MODULE__, [])
    |> Keyword.get(:webhook_url)
    |> present_string()
  end

  def send_test_webhook do
    case configured_webhook_url() do
      nil ->
        {:error, :not_configured}

      webhook_url ->
        case post_webhook(webhook_url, test_webhook_payload()) do
          :ok ->
            :ok

          {:error, {:unexpected_status, status, body}} ->
            Logger.warning(
              "issue webhook test returned unexpected status #{status}: #{inspect(body)}"
            )

            {:error, {:unexpected_status, status}}

          {:error, reason} ->
            Logger.warning("failed to deliver issue webhook test: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  def notify_async(%ErrorEvent{} = issue, disposition)
      when disposition in [:created, :reopened] do
    Task.Supervisor.start_child(@task_supervisor, fn ->
      deliver(issue, disposition)
    end)

    :ok
  rescue
    error ->
      Logger.warning("failed to start issue notification task: #{Exception.message(error)}")
      :ok
  end

  def deliver(%ErrorEvent{} = issue, disposition) when disposition in [:created, :reopened] do
    issue
    |> deliver_emails(disposition)
    |> deliver_webhook(disposition)

    :ok
  end

  defp deliver_emails(%ErrorEvent{} = issue, disposition) do
    Enum.each(recipients(issue), fn recipient ->
      case issue_email(issue, recipient, disposition) |> Mailer.deliver() do
        {:ok, _metadata} ->
          :ok

        {:error, reason} ->
          Logger.warning("failed to send issue notification email: #{inspect(reason)}")
      end
    end)

    issue
  end

  defp deliver_webhook(%ErrorEvent{} = issue, disposition) do
    case configured_webhook_url() do
      nil ->
        :ok

      webhook_url ->
        case post_webhook(webhook_url, webhook_payload(issue, disposition)) do
          :ok ->
            :ok

          {:error, {:unexpected_status, status, body}} ->
            Logger.warning("issue webhook returned unexpected status #{status}: #{inspect(body)}")

          {:error, reason} ->
            Logger.warning("failed to deliver issue webhook: #{inspect(reason)}")
        end
    end
  end

  defp recipients(%ErrorEvent{} = issue) do
    team_members =
      issue.project.team.team_members
      |> Enum.map(& &1.user)
      |> Enum.filter(&confirmed_user?/1)
      |> Enum.uniq_by(& &1.id)

    case issue.assignee do
      %User{} = assignee when not is_nil(assignee.confirmed_at) -> [assignee]
      _ -> team_members
    end
  end

  defp confirmed_user?(%User{confirmed_at: %DateTime{}}), do: true
  defp confirmed_user?(_user), do: false

  defp issue_email(%ErrorEvent{} = issue, %User{} = recipient, disposition) do
    project = issue.project
    action = disposition_text(disposition)
    url = issue_url(issue)

    text_body = """
    #{recipient.name},

    #{action} in #{project.name} (#{project.team.name}).

    Title: #{issue.title}
    Level: #{issue.level}
    Status: #{issue.status}
    Culprit: #{issue.culprit || "No culprit captured"}
    Occurrences: #{issue.occurrence_count}

    Open issue:
    #{url}
    """

    html_body = """
    <div style="font-family: ui-sans-serif, system-ui, sans-serif; color: #111827; line-height: 1.6; max-width: 560px; margin: 0 auto; padding: 24px;">
      <p style="margin: 0 0 12px 0;">#{recipient.name},</p>
      <p style="margin: 0 0 16px 0;"><strong>#{action}</strong> in <strong>#{project.name}</strong> (#{project.team.name}).</p>
      <div style="margin: 0 0 20px 0; padding: 16px; border: 1px solid #e5e7eb; background: #ffffff;">
        <p style="margin: 0 0 8px 0;"><strong>#{issue.title}</strong></p>
        <p style="margin: 0 0 4px 0; color: #4b5563;">Level: #{issue.level}</p>
        <p style="margin: 0 0 4px 0; color: #4b5563;">Status: #{issue.status}</p>
        <p style="margin: 0 0 4px 0; color: #4b5563;">Culprit: #{issue.culprit || "No culprit captured"}</p>
        <p style="margin: 0; color: #4b5563;">Occurrences: #{issue.occurrence_count}</p>
      </div>
      <p style="margin: 0;">
        <a href="#{url}" style="display: inline-block; background: #0ea5e9; color: #ffffff; text-decoration: none; padding: 10px 16px; font-weight: 600;">Open issue</a>
      </p>
    </div>
    """

    Swoosh.Email.new()
    |> Swoosh.Email.to({recipient.name, recipient.email})
    |> Swoosh.Email.from(Mailer.from())
    |> Swoosh.Email.subject(
      "[Argus] #{subject_prefix(disposition)} in #{project.name}: #{issue.title}"
    )
    |> Swoosh.Email.text_body(text_body)
    |> Swoosh.Email.html_body(html_body)
  end

  defp webhook_payload(%ErrorEvent{} = issue, disposition) do
    occurrence = latest_occurrence(issue)

    %{
      event: webhook_event(disposition),
      occurred_at: DateTime.to_iso8601(issue.last_seen_at),
      issue: issue_payload(issue, occurrence),
      project: %{
        id: issue.project.id,
        name: issue.project.name,
        slug: issue.project.slug
      },
      team: %{
        id: issue.project.team.id,
        name: issue.project.team.name
      },
      assignee: webhook_assignee(issue.assignee),
      occurrence: occurrence_payload(issue, occurrence),
      request: request_payload(issue, occurrence),
      sdk: sdk_payload(issue, occurrence),
      tags: tags_payload(issue, occurrence),
      contexts: contexts_payload(issue, occurrence),
      extra: extra_payload(issue, occurrence),
      url: issue_url(issue)
    }
  end

  defp webhook_assignee(nil), do: nil

  defp webhook_assignee(%User{} = assignee) do
    %{
      id: assignee.id,
      name: assignee.name,
      email: assignee.email
    }
  end

  defp issue_url(%ErrorEvent{} = issue) do
    "#{ArgusWeb.Endpoint.url()}/projects/#{issue.project.slug}/issues/#{issue.id}"
  end

  defp disposition_text(:created), do: "A new issue was detected"
  defp disposition_text(:reopened), do: "A resolved issue reappeared"

  defp subject_prefix(:created), do: "New issue"
  defp subject_prefix(:reopened), do: "Issue reappeared"

  defp webhook_event(:created), do: "issue_created"
  defp webhook_event(:reopened), do: "issue_reopened"

  defp test_webhook_payload do
    timestamp = DateTime.utc_now() |> DateTime.truncate(:second)
    request_url = "#{ArgusWeb.Endpoint.url()}/admin"
    request_path = "/admin"
    message = "This is a test webhook from Argus."
    reason = "Test exception for webhook delivery"
    code_path = "ArgusWeb.AdminLive.Index.handle_event/3"

    %{
      event: "webhook_test",
      occurred_at: DateTime.to_iso8601(timestamp),
      issue: %{
        id: 0,
        title: "RuntimeError: #{reason}",
        message: message,
        reason: reason,
        code_path: code_path,
        request_path: request_path,
        fingerprint: "webhook_test|RuntimeError|#{code_path}",
        level: :error,
        status: :unresolved,
        occurrence_count: 1,
        culprit: code_path,
        platform: "elixir"
      },
      project: %{
        id: 0,
        name: "Sample Project",
        slug: "sample-project"
      },
      team: %{
        id: 0,
        name: "Sample Team"
      },
      assignee: nil,
      occurrence: %{
        event_id: "webhook-test",
        timestamp: DateTime.to_iso8601(timestamp),
        request_url: request_url,
        request_path: request_path,
        message: message,
        reason: reason,
        code_path: code_path,
        exception: %{
          type: "RuntimeError",
          value: reason,
          handled: false
        }
      },
      request: %{
        url: request_url,
        path: request_path,
        method: "POST"
      },
      sdk: %{
        "name" => "argus",
        "version" => to_string(Application.spec(:argus, :vsn))
      },
      tags: %{
        "environment" => "test",
        "source" => "admin"
      },
      contexts: %{
        "runtime" => %{"name" => "BEAM"}
      },
      extra: %{
        "note" => "This payload is generated from the admin test button."
      },
      url: request_url
    }
  end

  defp post_webhook(webhook_url, payload) do
    case Req.post(
           Keyword.merge(req_options(),
             url: webhook_url,
             json: payload
           )
         ) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        :ok

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:unexpected_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp req_options do
    Application.get_env(:argus, __MODULE__, [])
    |> Keyword.get(:req_options, [])
  end

  defp latest_occurrence(%ErrorEvent{id: issue_id}) do
    Repo.one(
      from(occurrence in ErrorOccurrence,
        where: occurrence.error_event_id == ^issue_id,
        order_by: [desc: occurrence.timestamp, desc: occurrence.id],
        limit: 1
      )
    )
  end

  defp issue_payload(%ErrorEvent{} = issue, occurrence) do
    %{
      id: issue.id,
      title: issue.title,
      message: occurrence_message(issue, occurrence),
      reason: occurrence_reason(issue, occurrence),
      code_path: occurrence_code_path(issue, occurrence),
      request_path: request_path(issue, occurrence),
      fingerprint: issue.fingerprint,
      level: issue.level,
      status: issue.status,
      occurrence_count: issue.occurrence_count,
      culprit: issue.culprit,
      platform: issue.platform
    }
  end

  defp occurrence_payload(%ErrorEvent{} = issue, %ErrorOccurrence{} = occurrence) do
    %{
      event_id: occurrence.event_id,
      timestamp: DateTime.to_iso8601(occurrence.timestamp),
      request_url: request_url(issue, occurrence),
      request_path: request_path(issue, occurrence),
      message: occurrence_message(issue, occurrence),
      reason: occurrence_reason(issue, occurrence),
      code_path: occurrence_code_path(issue, occurrence),
      exception: exception_payload(occurrence)
    }
  end

  defp occurrence_payload(%ErrorEvent{} = issue, nil) do
    %{
      event_id: nil,
      timestamp: nil,
      request_url: request_url(issue, nil),
      request_path: request_path(issue, nil),
      message: occurrence_message(issue, nil),
      reason: occurrence_reason(issue, nil),
      code_path: occurrence_code_path(issue, nil),
      exception: nil
    }
  end

  defp request_payload(issue, occurrence) do
    request = request_details(issue, occurrence)

    %{
      url: request["url"],
      path: request["path"],
      method: request["method"]
    }
  end

  defp sdk_payload(issue, occurrence) do
    occurrence
    |> raw_payload_value("sdk")
    |> fallback_map(issue.sdk)
  end

  defp tags_payload(issue, occurrence) do
    occurrence
    |> raw_payload_value("tags")
    |> fallback_map(issue.tags)
  end

  defp contexts_payload(issue, occurrence) do
    occurrence
    |> raw_payload_value("contexts")
    |> fallback_map(issue.contexts)
  end

  defp extra_payload(issue, occurrence) do
    occurrence
    |> raw_payload_value("extra")
    |> fallback_map(issue.extra)
  end

  defp occurrence_message(%ErrorEvent{} = issue, %ErrorOccurrence{} = occurrence) do
    occurrence
    |> raw_payload()
    |> case do
      %{"message" => message} when is_binary(message) and message != "" ->
        message

      %{"logentry" => %{"formatted" => message}} when is_binary(message) and message != "" ->
        message

      _ ->
        primary_exception_title(occurrence) || issue.title
    end
  end

  defp occurrence_message(%ErrorEvent{} = issue, nil), do: issue.title

  defp occurrence_reason(%ErrorEvent{} = issue, %ErrorOccurrence{} = occurrence) do
    occurrence
    |> primary_exception()
    |> case do
      %{} = exception -> exception["value"] || occurrence_message(issue, occurrence)
      _ -> occurrence_message(issue, occurrence)
    end
  end

  defp occurrence_reason(%ErrorEvent{} = issue, nil), do: issue.title

  defp occurrence_code_path(%ErrorEvent{} = issue, %ErrorOccurrence{} = occurrence) do
    occurrence
    |> primary_exception()
    |> best_frame()
    |> frame_code_path()
    |> case do
      nil -> issue.culprit
      code_path -> code_path
    end
  end

  defp occurrence_code_path(%ErrorEvent{} = issue, nil), do: issue.culprit

  defp request_url(issue, occurrence) do
    request_details(issue, occurrence)["url"]
  end

  defp request_path(issue, occurrence) do
    request_details(issue, occurrence)["path"]
  end

  defp request_details(%ErrorEvent{} = issue, occurrence) do
    request =
      occurrence
      |> raw_payload_value("request")
      |> fallback_map(issue.request)

    url =
      occurrence
      |> case do
        %ErrorOccurrence{request_url: request_url} -> request_url
        _ -> nil
      end
      |> present_string()
      |> case do
        nil -> request["url"]
        request_url -> request_url
      end

    %{
      "url" => url,
      "path" => request_path_from_url(url),
      "method" => request["method"]
    }
  end

  defp exception_payload(%ErrorOccurrence{} = occurrence) do
    case primary_exception(occurrence) do
      %{} = exception ->
        %{
          type: exception["type"],
          value: exception["value"],
          handled: handled_exception?(occurrence)
        }

      _ ->
        nil
    end
  end

  defp primary_exception(%ErrorOccurrence{} = occurrence) do
    case occurrence.exception_values do
      [%{} = exception | _] -> exception
      _ -> nil
    end
  end

  defp primary_exception_title(%ErrorOccurrence{} = occurrence) do
    case primary_exception(occurrence) do
      %{} = exception ->
        [exception["type"], exception["value"]]
        |> Enum.reject(&blank?/1)
        |> Enum.join(": ")
        |> present_string()

      _ ->
        nil
    end
  end

  defp handled_exception?(%ErrorOccurrence{} = occurrence) do
    occurrence
    |> primary_exception()
    |> get_in(["mechanism", "handled"])
    |> case do
      nil -> false
      value -> value
    end
  end

  defp best_frame(%{} = exception) do
    frames =
      exception
      |> get_in(["stacktrace", "frames"])
      |> case do
        frames when is_list(frames) -> Enum.reverse(frames)
        _ -> []
      end

    Enum.find(frames, & &1["in_app"]) || List.first(frames)
  end

  defp best_frame(_exception), do: nil

  defp frame_code_path(nil), do: nil

  defp frame_code_path(frame) when is_map(frame) do
    base =
      cond do
        present_string(frame["module"]) && present_string(frame["function"]) ->
          "#{frame["module"]}.#{frame["function"]}"

        present_string(frame["filename"]) && present_string(frame["function"]) ->
          "#{frame["filename"]}:#{frame["function"]}"

        present_string(frame["module"]) ->
          frame["module"]

        present_string(frame["filename"]) ->
          frame["filename"]

        present_string(frame["function"]) ->
          frame["function"]

        true ->
          nil
      end

    case {base, frame["lineno"]} do
      {nil, _} -> nil
      {base, line} when is_integer(line) -> "#{base}:#{line}"
      {base, _} -> base
    end
  end

  defp frame_code_path(_frame), do: nil

  defp request_path_from_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{path: path, query: query} when is_binary(path) and path != "" and is_binary(query) ->
        path <> "?" <> query

      %URI{path: path} when is_binary(path) and path != "" ->
        path

      _ ->
        nil
    end
  end

  defp request_path_from_url(_url), do: nil

  defp raw_payload_value(%ErrorOccurrence{} = occurrence, key) when is_binary(key) do
    occurrence
    |> raw_payload()
    |> Map.get(key)
    |> normalize_map()
  end

  defp raw_payload_value(_occurrence, _key), do: %{}

  defp raw_payload(%ErrorOccurrence{raw_payload: payload}) when is_map(payload), do: payload
  defp raw_payload(_occurrence), do: %{}

  defp fallback_map(value, fallback) do
    value = normalize_map(value)
    if value == %{}, do: normalize_map(fallback), else: value
  end

  defp normalize_map(value) when is_map(value) do
    Map.new(value, fn {key, val} -> {to_string(key), val} end)
  end

  defp normalize_map(_value), do: %{}

  defp blank?(value), do: value in [nil, "", []]

  defp present_string(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present_string(_value), do: nil
end
