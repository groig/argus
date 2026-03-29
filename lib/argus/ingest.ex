defmodule Argus.Ingest do
  @moduledoc """
  Sentry-compatible event and envelope ingestion.

  This layer favors SDK compatibility over strict validation. It authenticates from DSN data,
  accepts the payload shapes real SDKs send, stores the parts it can understand, and avoids
  responses that would trigger retries. Grouping and issue lifecycle stay in `Argus.Projects`.
  """

  alias Argus.Ingest.Envelope
  alias Argus.Logs
  alias Argus.Projects
  alias Argus.Projects.Project

  def parse_auth_header_value("Sentry " <> rest) do
    rest
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reduce(%{}, fn pair, acc ->
      case String.split(pair, "=", parts: 2) do
        [key, value] -> Map.put(acc, key, value)
        _ -> acc
      end
    end)
  end

  def parse_auth_header_value(_), do: %{}

  def sentry_key_from_conn(conn) do
    cond do
      conn.params["sentry_key"] ->
        conn.params["sentry_key"]

      header = Plug.Conn.get_req_header(conn, "x-sentry-auth") |> List.first() ->
        header
        |> parse_auth_header_value()
        |> Map.get("sentry_key")

      true ->
        nil
    end
  end

  def sentry_key_from_envelope_body(body) when is_binary(body) do
    with {:ok, headers, _rest} <- Envelope.parse_headers(body),
         dsn when is_binary(dsn) <- Map.get(headers, "dsn") do
      sentry_key_from_dsn(dsn)
    else
      _ -> nil
    end
  end

  def sentry_key_from_dsn(dsn) when is_binary(dsn) do
    case URI.parse(dsn) do
      %URI{userinfo: userinfo} when is_binary(userinfo) and userinfo != "" ->
        userinfo
        |> String.split(":", parts: 2)
        |> List.first()

      _ ->
        nil
    end
  end

  def decode_body(body, nil), do: {:ok, body}
  def decode_body(body, ""), do: {:ok, body}
  def decode_body(body, "identity"), do: {:ok, body}

  def decode_body(body, encoding) when is_binary(encoding) do
    encoding
    |> normalize_encoding()
    |> decode_body_with_encoding(body)
  end

  defp decode_body_with_encoding(nil, body), do: {:ok, body}

  defp decode_body_with_encoding("identity", body), do: {:ok, body}

  defp decode_body_with_encoding("gzip", body) do
    try do
      {:ok, :zlib.gunzip(body)}
    rescue
      _ -> {:error, :invalid_encoding}
    end
  end

  defp decode_body_with_encoding("deflate", body) do
    try do
      z = :zlib.open()
      :ok = :zlib.inflateInit(z)
      inflated = :zlib.inflate(z, body)
      :zlib.close(z)
      {:ok, IO.iodata_to_binary(inflated)}
    rescue
      _ -> {:error, :invalid_encoding}
    end
  end

  defp decode_body_with_encoding("br", body) do
    case :brotli.decode(body) do
      {:ok, decoded_body} -> {:ok, decoded_body}
      _ -> {:error, :invalid_encoding}
    end
  rescue
    _ -> {:error, :invalid_encoding}
  end

  defp decode_body_with_encoding(_unsupported, _body), do: {:error, :unsupported_encoding}

  def ingest_store(%Project{} = project, payload) when is_map(payload) do
    event_payload =
      payload
      |> Map.new()
      |> Map.put_new("event_id", generate_event_id())

    issue_attrs = build_issue_attrs(event_payload)
    occurrence_attrs = build_occurrence_attrs(event_payload, nil)

    case Projects.upsert_issue_and_occurrence(project, issue_attrs, occurrence_attrs) do
      {:ok, %{issue: _error_event}} -> {:ok, %{id: event_payload["event_id"]}}
      _ -> {:error, :ingest_failed}
    end
  end

  def ingest_envelope(%Project{} = project, body) when is_binary(body) do
    with {:ok, envelope} <- Envelope.parse(body) do
      process_envelope(project, envelope)
    end
  end

  defp process_envelope(%Project{} = project, envelope) do
    envelope_event_id = Map.get(envelope.headers, "event_id")

    {event_payload, minidump_attachment, log_payloads} =
      Enum.reduce(envelope.items, {nil, nil, []}, fn item,
                                                     {event_payload, minidump_attachment,
                                                      log_payloads} ->
        type = item.headers["type"]

        cond do
          type == "event" and is_nil(event_payload) ->
            payload =
              item.payload
              |> decode_json_payload()
              |> case do
                {:ok, payload} when is_map(payload) ->
                  payload
                  |> Map.put_new("event_id", envelope_event_id || generate_event_id())

                _ ->
                  nil
              end

            {payload, minidump_attachment, log_payloads}

          type == "attachment" and item.headers["attachment_type"] == "event.minidump" ->
            {event_payload, item.payload, log_payloads}

          type == "log" ->
            case decode_json_payload(item.payload) do
              {:ok, payload} when is_map(payload) ->
                {event_payload, minidump_attachment, [payload | log_payloads]}

              _ ->
                {event_payload, minidump_attachment, log_payloads}
            end

          true ->
            {event_payload, minidump_attachment, log_payloads}
        end
      end)

    log_payloads
    |> Enum.reverse()
    |> Enum.each(&store_log_payload(project, &1))

    cond do
      is_map(event_payload) ->
        issue_attrs = build_issue_attrs(event_payload)
        occurrence_attrs = build_occurrence_attrs(event_payload, minidump_attachment)

        case Projects.upsert_issue_and_occurrence(project, issue_attrs, occurrence_attrs) do
          {:ok, %{issue: _error_event}} -> {:ok, %{id: event_payload["event_id"]}}
          _ -> {:error, :ingest_failed}
        end

      log_payloads != [] ->
        {:ok, :accepted}

      true ->
        {:ok, :accepted}
    end
  end

  defp store_log_payload(%Project{} = project, %{"items" => items}) when is_list(items) do
    Enum.each(items, fn item ->
      if is_map(item) do
        attrs =
          item
          |> Map.get("attributes", %{})
          |> normalize_log_attributes()

        timestamp = parse_timestamp(item["timestamp"]) || DateTime.utc_now(:second)

        Logs.create_log_event(project, %{
          level: normalize_level(Map.get(item, "level"), :info),
          message: Map.get(item, "body", "log message"),
          timestamp: timestamp,
          metadata: %{
            "attributes" => normalize_map(attrs),
            "trace_id" => Map.get(item, "trace_id"),
            "span_id" => Map.get(item, "span_id")
          },
          logger_name: attrs["logger.name"],
          message_template: attrs["sentry.message.template"],
          origin: attrs["sentry.origin"],
          release: attrs["sentry.release"],
          environment: attrs["sentry.environment"],
          sdk_name: attrs["sentry.sdk.name"],
          sdk_version: attrs["sentry.sdk.version"],
          sequence: parse_sequence(attrs["sentry.timestamp.sequence"]),
          trace_id: Map.get(item, "trace_id"),
          span_id: Map.get(item, "span_id")
        })
      end
    end)
  end

  defp store_log_payload(_project, _payload), do: :ok

  defp build_issue_attrs(payload) do
    timestamp = parse_timestamp(payload["timestamp"]) || DateTime.utc_now(:second)

    %{
      fingerprint: fingerprint_for_payload(payload),
      title: title_for_payload(payload),
      culprit:
        payload["culprit"] || payload["transaction"] || get_in(payload, ["request", "url"]),
      level: normalize_level(payload["level"], :error),
      platform: payload["platform"],
      sdk: normalize_map(payload["sdk"]),
      request: normalize_map(payload["request"]),
      contexts: normalize_map(payload["contexts"]),
      tags: normalize_tags(payload["tags"]),
      extra: normalize_map(payload["extra"]),
      first_seen_at: timestamp,
      last_seen_at: timestamp,
      occurrence_count: 1,
      status: :unresolved
    }
  end

  defp build_occurrence_attrs(payload, minidump_attachment) do
    %{
      event_id: payload["event_id"] || generate_event_id(),
      timestamp: parse_timestamp(payload["timestamp"]) || DateTime.utc_now(:second),
      request_url: get_in(payload, ["request", "url"]),
      user_context: normalize_map(payload["user"]),
      exception_values: exception_values(payload),
      breadcrumbs: breadcrumbs(payload),
      raw_payload: payload,
      minidump_attachment: minidump_attachment
    }
  end

  defp title_for_payload(payload) do
    with [%{} = exception | _] <- exception_values(payload) do
      type = exception["type"]
      value = exception["value"]

      case {blank?(type), blank?(value)} do
        {false, false} -> "#{type}: #{value}"
        {false, true} -> type
        _ -> payload["message"] || get_in(payload, ["logentry", "formatted"]) || "Captured event"
      end
    else
      _ ->
        payload["message"] || get_in(payload, ["logentry", "formatted"]) || payload["transaction"] ||
          "Captured event"
    end
  end

  defp fingerprint_for_payload(payload) do
    case exception_values(payload) do
      [%{} = exception | _] ->
        first_frame =
          exception
          |> get_in(["stacktrace", "frames"])
          |> case do
            frames when is_list(frames) -> List.first(frames) || %{}
            _ -> %{}
          end

        [
          exception["type"] || "error",
          exception["value"] || title_for_payload(payload),
          first_frame["module"] || first_frame["filename"] || first_frame["function"] || "frame"
        ]
        |> Enum.join("|")

      _ ->
        payload["message"] || get_in(payload, ["logentry", "formatted"]) ||
          title_for_payload(payload)
    end
  end

  defp exception_values(payload) do
    case get_in(payload, ["exception", "values"]) do
      values when is_list(values) -> Enum.filter(values, &is_map/1)
      _ -> []
    end
  end

  defp breadcrumbs(payload) do
    case get_in(payload, ["breadcrumbs", "values"]) || payload["breadcrumbs"] do
      values when is_list(values) -> Enum.filter(values, &is_map/1)
      _ -> []
    end
  end

  defp normalize_tags(tags) when is_map(tags), do: tags

  defp normalize_tags(tags) when is_list(tags) do
    Enum.reduce(tags, %{}, fn
      {key, value}, acc -> Map.put(acc, to_string(key), value)
      %{"key" => key, "value" => value}, acc -> Map.put(acc, key, value)
      _, acc -> acc
    end)
  end

  defp normalize_tags(_), do: %{}

  defp normalize_map(map) when is_map(map), do: map
  defp normalize_map(_), do: %{}

  defp normalize_log_attributes(attrs) when is_map(attrs) do
    Map.new(attrs, fn {key, value} -> {key, unwrap_log_attribute_value(value)} end)
  end

  defp normalize_log_attributes(_), do: %{}

  defp unwrap_log_attribute_value(%{"value" => value}), do: value
  defp unwrap_log_attribute_value(%{value: value}), do: value
  defp unwrap_log_attribute_value(value), do: value

  defp normalize_level(level, default) when is_binary(level) do
    case String.downcase(level) do
      "fatal" -> :error
      "error" -> :error
      "warning" -> :warning
      "warn" -> :warning
      "info" -> :info
      _ -> default
    end
  end

  defp normalize_level(_, default), do: default

  defp parse_timestamp(nil), do: nil
  defp parse_timestamp(%DateTime{} = value), do: truncate_datetime(value)

  defp parse_timestamp(value) when is_integer(value) do
    DateTime.from_unix!(value, :second)
  end

  defp parse_timestamp(value) when is_float(value) do
    value
    |> trunc()
    |> DateTime.from_unix!(:second)
  end

  defp parse_timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        truncate_datetime(datetime)

      _ ->
        case Integer.parse(value) do
          {unix, ""} -> DateTime.from_unix!(unix, :second)
          _ -> nil
        end
    end
  end

  defp parse_timestamp(_), do: nil

  defp parse_sequence(nil), do: 0
  defp parse_sequence(value) when is_integer(value), do: value

  defp parse_sequence(value) when is_binary(value) do
    case Integer.parse(value) do
      {sequence, _} -> sequence
      :error -> 0
    end
  end

  defp parse_sequence(_), do: 0

  defp normalize_encoding(encoding) do
    encoding
    |> String.downcase()
    |> String.split(",", trim: true)
    |> List.first()
    |> case do
      nil -> nil
      value -> String.trim(value)
    end
  end

  defp truncate_datetime(%DateTime{} = datetime) do
    DateTime.truncate(datetime, :second)
  end

  defp decode_json_payload(payload) do
    Jason.decode(payload)
  end

  defp generate_event_id do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
  end

  defp blank?(value), do: value in [nil, ""]
end
