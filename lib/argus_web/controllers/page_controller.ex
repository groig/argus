defmodule ArgusWeb.PageController do
  use ArgusWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  def not_found(conn, _params) do
    send_resp(conn, :not_found, "Not found")
  end
end
