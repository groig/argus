defmodule ArgusWeb.Plugs.ApiAuth do
  @moduledoc """
  Authenticates agent API requests with a personal API token.

  Accepts `Authorization: Bearer <token>` and assigns `current_scope` for the token's owner.
  """

  import Plug.Conn

  alias Argus.Accounts
  alias Argus.Accounts.Scope

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> raw] <- get_req_header(conn, "authorization"),
         %{} = user <- Accounts.get_user_by_api_token(String.trim(raw)) do
      assign(conn, :current_scope, Scope.for_user(user))
    else
      _ ->
        conn
        |> put_resp_content_type("text/markdown")
        |> put_resp_header("www-authenticate", "Bearer")
        |> send_resp(
          :unauthorized,
          "# Unauthorized\n\nSend a personal API token as `Authorization: Bearer <token>`. " <>
            "Create one under Settings → API tokens.\n"
        )
        |> halt()
    end
  end
end
