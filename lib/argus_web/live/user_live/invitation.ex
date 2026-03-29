defmodule ArgusWeb.UserLive.Invitation do
  use ArgusWeb, :live_view

  alias Argus.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="border border-zinc-200 bg-white px-8 py-10 sm:px-10">
        <div class="space-y-8">
          <div class="space-y-3 text-center">
            <p class="text-xs uppercase tracking-[0.22em] text-zinc-500">Argus invitation</p>
            <h1 class="text-3xl font-semibold tracking-tight text-zinc-950">Join Argus</h1>
            <p class="text-sm leading-6 text-zinc-500">
              {@invitation.invited_by.name} invited {@invitation.email} to the workspace.
            </p>
          </div>

          <.form
            for={@form}
            id="invitation-form"
            action={~p"/invitations/#{@token}"}
            method="post"
            phx-change="validate"
            class="space-y-5"
          >
            <.input
              field={@form[:password]}
              type="password"
              label="Password"
              autocomplete="new-password"
              required
              phx-mounted={JS.focus()}
            />
            <.input
              field={@form[:password_confirmation]}
              type="password"
              label="Confirm password"
              autocomplete="new-password"
              required
            />
            <.button class="w-full">Accept invitation</.button>
          </.form>

          <p class="text-center text-xs uppercase tracking-[0.18em] text-zinc-500">
            This link expires {Calendar.strftime(@invitation.expires_at, "%b %-d, %Y at %H:%M UTC")}
          </p>
        </div>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    case Accounts.get_invitation_by_token(token) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "That invitation is invalid or has expired.")
         |> push_navigate(to: ~p"/login")}

      invitation ->
        form = to_form(%{"password" => "", "password_confirmation" => ""}, as: :user)

        {:ok, assign(socket, invitation: invitation, token: token, form: form)}
    end
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    changeset =
      socket.assigns.invitation.user
      |> Accounts.change_user_password(params, hash_password: false)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :user))}
  end
end
