defmodule Argus.Ingest.Envelope do
  @moduledoc false

  def parse_headers(body) when is_binary(body) do
    parse_json_line(body)
  end

  def parse(body) when is_binary(body) do
    with {:ok, headers, rest} <- parse_headers(body) do
      parse_items(rest, %{headers: headers, items: []})
    end
  end

  defp parse_items(<<>>, envelope), do: {:ok, %{envelope | items: Enum.reverse(envelope.items)}}

  defp parse_items(binary, envelope) do
    binary = trim_leading_newlines(binary)

    if binary == "" do
      {:ok, %{envelope | items: Enum.reverse(envelope.items)}}
    else
      with {:ok, item_headers, rest} <- parse_json_line(binary),
           {:ok, payload, remainder} <- read_payload(rest, item_headers) do
        parse_items(remainder, %{
          envelope
          | items: [%{headers: item_headers, payload: payload} | envelope.items]
        })
      end
    end
  end

  defp read_payload(binary, %{"length" => length}) when is_integer(length) and length >= 0 do
    if byte_size(binary) < length do
      {:error, :truncated_payload}
    else
      <<payload::binary-size(length), remainder::binary>> = binary
      {:ok, payload, trim_single_leading_newline(remainder)}
    end
  end

  defp read_payload(binary, _headers) do
    case :binary.match(binary, "\n") do
      {offset, 1} ->
        <<payload::binary-size(offset), _newline, remainder::binary>> = binary
        {:ok, payload, remainder}

      :nomatch ->
        {:ok, binary, <<>>}
    end
  end

  defp parse_json_line(binary) do
    case :binary.match(binary, "\n") do
      {offset, 1} ->
        <<line::binary-size(offset), _newline, rest::binary>> = binary
        decode_json_line(line, rest)

      :nomatch ->
        decode_json_line(binary, <<>>)
    end
  end

  defp decode_json_line("", _rest), do: {:error, :invalid_json_line}

  defp decode_json_line(line, rest) do
    case Jason.decode(line) do
      {:ok, decoded} when is_map(decoded) -> {:ok, decoded, rest}
      _ -> {:error, :invalid_json_line}
    end
  end

  defp trim_leading_newlines(<<"\n", rest::binary>>), do: trim_leading_newlines(rest)
  defp trim_leading_newlines(binary), do: binary

  defp trim_single_leading_newline(<<"\n", rest::binary>>), do: rest
  defp trim_single_leading_newline(binary), do: binary
end
