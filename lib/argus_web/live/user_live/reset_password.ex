defmodule ArgusWeb.UserLive.ResetPassword do
  use ArgusWeb, :live_view

  alias Argus.Accounts
  alias ArgusWeb.UserAuth

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="border border-zinc-200 bg-white px-8 py-10 sm:px-10">
        <div class="space-y-8">
          <div class="space-y-3 text-center">
            <p class="text-xs uppercase tracking-[0.22em] text-zinc-500">Argus</p>
            <h1 class="text-3xl font-semibold tracking-tight text-zinc-950">Choose a new password</h1>
            <p class="text-sm leading-6 text-zinc-500">
              Resetting the password for {@user.email}. You'll be signed out everywhere else.
            </p>
          </div>

          <.form
            for={@form}
            id="new-password-form"
            phx-change="validate"
            phx-submit="reset"
            class="space-y-5"
          >
            <.input
              field={@form[:password]}
              type="password"
              label="New password"
              autocomplete="new-password"
              required
              phx-mounted={JS.focus()}
            />
            <.input
              field={@form[:password_confirmation]}
              type="password"
              label="Confirm new password"
              autocomplete="new-password"
              required
            />
            <.button class="w-full" phx-disable-with="Saving...">Reset password</.button>
          </.form>
        </div>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    case Accounts.get_user_by_reset_password_token(token) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "That reset link is invalid or has expired.")
         |> push_navigate(to: ~p"/reset-password")}

      user ->
        form = to_form(Accounts.change_user_password(user, %{}, hash_password: false), as: :user)
        {:ok, assign(socket, user: user, form: form)}
    end
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    changeset =
      socket.assigns.user
      |> Accounts.change_user_password(params, hash_password: false)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :user))}
  end

  def handle_event("reset", %{"user" => params}, socket) do
    case Accounts.reset_user_password(socket.assigns.user, params) do
      {:ok, {_user, expired_tokens}} ->
        UserAuth.disconnect_sessions(expired_tokens)

        {:noreply,
         socket
         |> put_flash(:info, "Password reset. Log in with your new password.")
         |> put_flash(:email, socket.assigns.user.email)
         |> push_navigate(to: ~p"/login")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :user))}
    end
  end
end
