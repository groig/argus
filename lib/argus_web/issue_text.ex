defmodule ArgusWeb.IssueText do
  @moduledoc """
  Plain-text rendering of issues and occurrences.

  Shared by the issue page (copy button and template helpers) and the agent API, so the text
  agents read matches what users copy.
  """

  use ArgusWeb, :verified_routes

  def occurrence_user(occurrence) do
    occurrence.raw_payload
    |> Map.get("user", occurrence.user_context || %{})
    |> normalize_map()
  end

  def occurrence_request(occurrence) do
    occurrence.raw_payload
    |> Map.get("request", %{})
    |> normalize_map()
  end

  def occurrence_sdk(occurrence) do
    occurrence.raw_payload
    |> Map.get("sdk", %{})
    |> normalize_map()
  end

  def occurrence_extra(occurrence) do
    occurrence.raw_payload
    |> Map.get("extra", %{})
    |> normalize_map()
  end

  def context_summary(nil, issue) do
    contexts = issue.contexts || %{}

    %{
      runtime: contexts["runtime"] || %{},
      os: contexts["os"] || %{},
      browser: contexts["browser"] || %{},
      trace: contexts["trace"] || %{}
    }
  end

  def context_summary(occurrence, _issue) do
    contexts =
      occurrence.raw_payload
      |> Map.get("contexts", %{})
      |> normalize_map()

    %{
      runtime: contexts["runtime"] || %{},
      os: contexts["os"] || %{},
      browser: contexts["browser"] || %{},
      trace: contexts["trace"] || %{}
    }
  end

  def primary_exception_title(occurrence) do
    with [%{} = exception | _] <- occurrence.exception_values do
      [exception["type"], exception["value"]]
      |> Enum.reject(&blank?/1)
      |> Enum.join(": ")
    else
      _ -> nil
    end
  end

  def handled_exception?(occurrence) do
    occurrence.exception_values
    |> List.first()
    |> get_in(["mechanism", "handled"])
    |> case do
      nil -> false
      value -> value
    end
  end

  def stack_frames(exception) do
    exception
    |> get_in(["stacktrace", "frames"])
    |> case do
      frames when is_list(frames) -> Enum.reverse(frames)
      _ -> []
    end
  end

  def visible_stack_frames(frames, "all"), do: frames

  def visible_stack_frames(frames, "in_app") do
    in_app_frames = Enum.filter(frames, & &1["in_app"])
    if in_app_frames == [], do: frames, else: in_app_frames
  end

  def toggleable_frames?(frames) do
    in_app_count = Enum.count(frames, & &1["in_app"])
    in_app_count > 0 and in_app_count < length(frames)
  end

  def frame_scope_note(frames, frame_mode) do
    in_app_count = Enum.count(frames, & &1["in_app"])
    total_count = length(frames)

    cond do
      total_count == 0 ->
        "No frames captured."

      frame_mode == "all" ->
        "Showing all #{total_count} frames."

      in_app_count == 0 ->
        "No in-app frames captured. Showing all #{total_count} frames."

      true ->
        "Showing #{in_app_count} in-app frames out of #{total_count} total."
    end
  end

  def selected_frame_index([]), do: 0

  def selected_frame_index(frames) do
    Enum.find_index(frames, fn frame -> frame["in_app"] end) || 0
  end

  def frame_location(frame) do
    [
      frame["module"] || frame["filename"],
      frame["function"],
      frame["lineno"] && "line #{frame["lineno"]}"
    ]
    |> Enum.reject(&blank?/1)
    |> Enum.join(" / ")
  end

  def code_context(frame) do
    pre_context = frame["pre_context"] || []
    post_context = frame["post_context"] || []

    lines =
      case frame["context_line"] do
        nil -> pre_context ++ post_context
        context_line -> pre_context ++ [context_line] ++ post_context
      end

    start_line = max((frame["lineno"] || 1) - length(pre_context), 1)
    current_line = frame["lineno"]

    lines
    |> Enum.with_index(start_line)
    |> Enum.map(fn {text, number} ->
      %{text: text, number: number, current: current_line == number}
    end)
  end

  def frame_vars(frame) do
    frame
    |> Map.get("vars", %{})
    |> normalize_map()
  end

  def format_breadcrumb_timestamp(nil), do: "Unknown time"

  def format_breadcrumb_timestamp(value) do
    case DateTime.from_iso8601(value) do
      {:ok, timestamp, _offset} -> Calendar.strftime(timestamp, "%H:%M:%S")
      _ -> value
    end
  end

  def query_breadcrumbs(occurrence) do
    occurrence.breadcrumbs
    |> Enum.filter(&query_breadcrumb?/1)
  end

  def query_breadcrumb?(breadcrumb) do
    category = Map.get(breadcrumb, "category")
    type = Map.get(breadcrumb, "type")

    category == "query" ||
      type == "query" ||
      (is_binary(category) && String.contains?(category, "query"))
  end

  def modules_count(modules) when is_map(modules), do: map_size(modules)
  def modules_count(_modules), do: nil

  def issue_copy_text(project, issue, nil, _frame_mode) do
    [
      "Argus Issue",
      "Title: #{issue.title}",
      "URL: #{issue_url(project, issue)}",
      "Project: #{project.name}",
      "Status: #{issue.status}",
      "Level: #{issue.level}",
      "Assignee: #{assignee_name(issue.assignee)}",
      "Culprit: #{issue.culprit || "-"}",
      "Fingerprint: #{issue.fingerprint}",
      "First seen: #{format_datetime(issue.first_seen_at)}",
      "Last seen: #{format_datetime(issue.last_seen_at)}",
      "Occurrences: #{issue.occurrence_count}",
      "",
      "No event data captured."
    ]
    |> Enum.join("\n")
  end

  def issue_copy_text(project, issue, occurrence, frame_mode) do
    payload = occurrence.raw_payload || %{}

    [
      issue_copy_summary(project, issue),
      event_copy_summary(occurrence, issue),
      exception_copy_text(occurrence, frame_mode),
      map_copy_section("User", occurrence_user(occurrence)),
      map_copy_section("Request", occurrence_request(occurrence)),
      map_copy_section("SDK", occurrence_sdk(occurrence)),
      map_copy_section("Tags", normalize_map(payload["tags"] || issue.tags)),
      map_copy_section("Contexts", normalize_map(payload["contexts"] || issue.contexts)),
      map_copy_section("Extra", occurrence_extra(occurrence)),
      breadcrumbs_copy_text(occurrence)
    ]
    |> Enum.reject(&blank?/1)
    |> Enum.join("\n\n")
  end

  def issue_copy_summary(project, issue) do
    [
      "Argus Issue",
      "Title: #{issue.title}",
      "URL: #{issue_url(project, issue)}",
      "Project: #{project.name}",
      "Status: #{issue.status}",
      "Level: #{issue.level}",
      "Assignee: #{assignee_name(issue.assignee)}",
      "Culprit: #{issue.culprit || "-"}",
      "Fingerprint: #{issue.fingerprint}",
      "First seen: #{format_datetime(issue.first_seen_at)}",
      "Last seen: #{format_datetime(issue.last_seen_at)}",
      "Occurrences: #{issue.occurrence_count}"
    ]
    |> Enum.join("\n")
  end

  def event_copy_summary(occurrence, issue) do
    [
      "Selected Event",
      "Event ID: #{occurrence.event_id}",
      "Timestamp: #{format_datetime(occurrence.timestamp)}",
      "Request URL: #{occurrence.request_url || "-"}",
      "Exception: #{primary_exception_title(occurrence) || issue.title}"
    ]
    |> Enum.join("\n")
  end

  def exception_copy_text(occurrence, frame_mode) do
    occurrence.exception_values
    |> Enum.with_index(1)
    |> Enum.map(fn {exception, index} ->
      frames = stack_frames(exception)
      visible_frames = visible_stack_frames(frames, frame_mode)

      [
        "Exception #{index}: #{exception["type"] || "Captured exception"}",
        exception["value"] && "Message: #{exception["value"]}",
        "Handled: #{handled_exception?(occurrence)}",
        "Traceback: #{frame_scope_note(frames, frame_mode)}",
        frames_copy_text(visible_frames)
      ]
      |> Enum.reject(&blank?/1)
      |> Enum.join("\n")
    end)
    |> case do
      [] -> nil
      sections -> ["Exceptions" | sections] |> Enum.join("\n\n")
    end
  end

  def frames_copy_text([]), do: "No frames captured."

  def frames_copy_text(frames) do
    frames
    |> Enum.with_index(1)
    |> Enum.map(fn {frame, index} ->
      [
        "Frame #{index}: #{frame_location(frame)}",
        code_context_copy_text(frame),
        frame_vars_copy_text(frame)
      ]
      |> Enum.reject(&blank?/1)
      |> Enum.join("\n")
    end)
    |> Enum.join("\n\n")
  end

  def code_context_copy_text(frame) do
    frame
    |> code_context()
    |> case do
      [] ->
        nil

      lines ->
        body =
          lines
          |> Enum.map(fn line ->
            marker = if line.current, do: "=>", else: "  "
            "#{marker} #{line.number}: #{line.text}"
          end)
          |> Enum.join("\n")

        "Code:\n#{indent(body, 2)}"
    end
  end

  def frame_vars_copy_text(frame) do
    frame
    |> frame_vars()
    |> case do
      vars when map_size(vars) == 0 ->
        nil

      vars ->
        "Local variables:\n#{map_copy_lines(vars, 2)}"
    end
  end

  def map_copy_section(_title, data) when data in [nil, %{}], do: nil

  def map_copy_section(title, data) when is_map(data) do
    "#{title}\n#{map_copy_lines(data, 2)}"
  end

  def map_copy_lines(data, spaces) when is_map(data) do
    data
    |> map_entries()
    |> Enum.map(fn {key, value} ->
      "#{String.duplicate(" ", spaces)}#{key}: #{format_value(value)}"
    end)
    |> Enum.join("\n")
  end

  def breadcrumbs_copy_text(occurrence) do
    occurrence
    |> query_breadcrumbs()
    |> case do
      [] ->
        nil

      breadcrumbs ->
        body =
          breadcrumbs
          |> Enum.map(fn breadcrumb ->
            [
              "- #{format_breadcrumb_timestamp(breadcrumb["timestamp"])} #{breadcrumb["message"] || breadcrumb["category"] || breadcrumb["type"] || "Breadcrumb"}",
              map_size(Map.get(breadcrumb, "data", %{})) > 0 &&
                map_copy_lines(breadcrumb["data"], 2)
            ]
            |> Enum.reject(&blank?/1)
            |> Enum.join("\n")
          end)
          |> Enum.join("\n")

        "Query Breadcrumbs\n#{body}"
    end
  end

  def issue_url(project, issue) do
    url(~p"/projects/#{project.slug}/issues/#{issue.id}")
  end

  def format_datetime(nil), do: "-"
  def format_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  def indent(text, spaces) do
    padding = String.duplicate(" ", spaces)

    text
    |> String.split("\n")
    |> Enum.map_join("\n", &(padding <> &1))
  end

  def map_entries(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
  end

  def normalize_map(map) when is_map(map), do: map
  def normalize_map(_map), do: %{}

  def format_value(nil), do: "-"
  def format_value(value) when is_binary(value), do: value
  def format_value(value) when is_atom(value), do: Atom.to_string(value)
  def format_value(value) when is_boolean(value), do: to_string(value)
  def format_value(value) when is_integer(value) or is_float(value), do: to_string(value)
  def format_value(value), do: inspect(value)

  def blank?(value), do: value in [nil, "", []]

  def assignee_name(nil), do: "Unassigned"
  def assignee_name(assignee), do: assignee.name
end
