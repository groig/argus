defmodule ArgusWeb.Plugs.IngestProject do
  import Plug.Conn
  import Phoenix.Controller

  alias Argus.Ingest
  alias Argus.Projects

  def init(opts), do: opts

  def call(conn, _opts) do
    case load_project(conn) do
      {:ok, conn, project} ->
        assign(conn, :project, project)

      {:error, conn} ->
        conn
        |> drain_request_body()
        |> put_resp_header("access-control-allow-origin", "*")
        |> put_status(:forbidden)
        |> json(%{detail: "Project not found or key incorrect"})
        |> halt()
    end
  end

  defp load_project(conn) do
    project_id = conn.params["project_id"]

    with project_id when project_id not in [nil, ""] <- project_id,
         sentry_key when is_binary(sentry_key) <- Ingest.sentry_key_from_conn(conn),
         %{} = project <- Projects.get_project_by_id_and_dsn_key(project_id, sentry_key) do
      {:ok, conn, project}
    else
      _ ->
        load_project_from_envelope(conn, project_id)
    end
  end

  defp load_project_from_envelope(conn, project_id)
       when project_id in [nil, ""] or conn.method != "POST" do
    {:error, conn}
  end

  defp load_project_from_envelope(conn, project_id) do
    if envelope_request?(conn) do
      with {:ok, conn, raw_body} <- read_full_body(conn),
           {:ok, decoded_body} <- Ingest.decode_body(raw_body, content_encoding(conn)),
           sentry_key when is_binary(sentry_key) <-
             Ingest.sentry_key_from_envelope_body(decoded_body),
           %{} = project <- Projects.get_project_by_id_and_dsn_key(project_id, sentry_key) do
        {:ok, assign(conn, :raw_body, raw_body), project}
      else
        _ -> {:error, conn}
      end
    else
      {:error, conn}
    end
  end

  defp drain_request_body(%Plug.Conn{assigns: %{raw_body: _}} = conn), do: conn

  defp drain_request_body(conn) do
    case read_full_body(conn) do
      {:ok, conn, _body} -> conn
      {:error, _reason} -> conn
    end
  end

  defp read_full_body(%Plug.Conn{assigns: %{raw_body: raw_body}} = conn) do
    {:ok, conn, raw_body}
  end

  defp read_full_body(conn), do: do_read_full_body(conn, [])

  defp do_read_full_body(conn, chunks) do
    case read_body(conn) do
      {:ok, body, conn} ->
        {:ok, conn, IO.iodata_to_binary(Enum.reverse([body | chunks]))}

      {:more, body, conn} ->
        do_read_full_body(conn, [body | chunks])

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp content_encoding(conn) do
    conn
    |> get_req_header("content-encoding")
    |> List.first()
  end

  defp envelope_request?(conn) do
    List.last(conn.path_info) == "envelope"
  end
end
