defmodule ArgusWeb.IngestController do
  use ArgusWeb, :controller

  plug ArgusWeb.Plugs.IngestProject when action in [:store, :envelope]

  alias Argus.Ingest

  def options(conn, _params) do
    conn
    |> put_cors_headers()
    |> send_resp(200, "")
  end

  def store(conn, _params) do
    with {:ok, payload} <- read_store_payload(conn),
         {:ok, %{id: id}} <- Ingest.ingest_store(conn.assigns.project, payload) do
      conn
      |> put_cors_headers()
      |> json(%{id: id})
    else
      {:error, :unsupported_encoding} ->
        conn
        |> put_cors_headers()
        |> put_status(:bad_request)
        |> json(%{detail: "Unsupported content encoding"})

      {:error, :invalid_encoding} ->
        conn
        |> put_cors_headers()
        |> put_status(:bad_request)
        |> json(%{detail: "Could not decode request body"})

      _ ->
        conn
        |> put_cors_headers()
        |> put_status(:bad_request)
        |> json(%{detail: "Malformed event payload"})
    end
  end

  def envelope(conn, _params) do
    with {:ok, body} <- read_raw_body(conn),
         {:ok, decoded_body} <- decode_request_body(conn, body),
         {:ok, result} <- Ingest.ingest_envelope(conn.assigns.project, decoded_body) do
      conn = put_cors_headers(conn)

      case result do
        %{id: id} -> json(conn, %{id: id})
        :accepted -> send_resp(conn, 200, "")
      end
    else
      {:error, :unsupported_encoding} ->
        conn
        |> put_cors_headers()
        |> put_status(:bad_request)
        |> json(%{detail: "Unsupported content encoding"})

      {:error, :invalid_encoding} ->
        conn
        |> put_cors_headers()
        |> put_status(:bad_request)
        |> json(%{detail: "Could not decode request body"})

      _ ->
        conn
        |> put_cors_headers()
        |> put_status(:bad_request)
        |> json(%{detail: "Malformed envelope payload"})
    end
  end

  defp read_raw_body(%Plug.Conn{assigns: %{raw_body: body}}), do: {:ok, body}

  defp read_raw_body(conn) do
    case Plug.Conn.read_body(conn) do
      {:ok, body, _conn} -> {:ok, body}
      {:more, body, _conn} -> {:ok, body}
      error -> error
    end
  end

  defp read_store_payload(%Plug.Conn{body_params: %Plug.Conn.Unfetched{}} = conn) do
    with {:ok, body} <- read_raw_body(conn),
         {:ok, decoded_body} <- decode_request_body(conn, body),
         {:ok, payload} <- Jason.decode(decoded_body) do
      {:ok, payload}
    end
  end

  defp read_store_payload(%Plug.Conn{body_params: body_params} = conn) when is_map(body_params) do
    content_encoding =
      conn
      |> get_req_header("content-encoding")
      |> List.first()

    if content_encoding in [nil, "", "identity"] do
      {:ok, body_params}
    else
      with {:ok, body} <- read_raw_body(conn),
           {:ok, decoded_body} <- decode_request_body(conn, body),
           {:ok, payload} <- Jason.decode(decoded_body) do
        {:ok, payload}
      end
    end
  end

  defp decode_request_body(conn, body) do
    encoding =
      conn
      |> get_req_header("content-encoding")
      |> List.first()

    Ingest.decode_body(body, encoding)
  end

  defp put_cors_headers(conn) do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-methods", "POST, OPTIONS")
    |> put_resp_header(
      "access-control-allow-headers",
      "Content-Type, X-Sentry-Auth, Origin, Accept, Authorization, Content-Encoding, sentry-trace, baggage"
    )
  end
end
