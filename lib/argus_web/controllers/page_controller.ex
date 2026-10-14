defmodule ArgusWeb.PageController do
  use ArgusWeb, :controller

  alias Argus.Accounts
  alias ArgusWeb.UserAuth

  def home(%{assigns: %{current_scope: %{user: %Accounts.User{} = user}}} = conn, _params) do
    redirect(conn, to: UserAuth.signed_in_path(user))
  end

  def home(conn, _params) do
    render(conn, :home)
  end

  def not_found(conn, _params) do
    send_resp(conn, :not_found, "Not found")
  end
end
