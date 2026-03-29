defmodule ArgusWeb.InvitationController do
  use ArgusWeb, :controller

  alias Argus.Accounts
  alias ArgusWeb.UserAuth

  def accept(conn, %{"token" => token, "user" => user_params}) do
    case Accounts.accept_user_invitation(token, user_params) do
      {:ok, {user, expired_tokens}} ->
        UserAuth.disconnect_sessions(expired_tokens)

        conn
        |> put_flash(:info, "Welcome to Argus.")
        |> UserAuth.log_in_user(user, user_params)

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_flash(:error, format_errors(changeset))
        |> redirect(to: ~p"/invitations/#{token}")

      {:error, :invalid_or_expired} ->
        conn
        |> put_flash(:error, "That invitation is invalid or has expired.")
        |> redirect(to: ~p"/login")
    end
  end

  defp format_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.flat_map(fn {_field, messages} -> messages end)
    |> Enum.join(", ")
  end
end
