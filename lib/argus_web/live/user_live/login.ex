defmodule ArgusWeb.UserLive.Login do
  use ArgusWeb, :live_view

  alias ArgusWeb.UserAuth

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="border border-zinc-200 bg-white px-8 py-10 sm:px-10">
        <div class="space-y-8">
          <div class="space-y-3 text-center">
            <p class="text-xs uppercase tracking-[0.22em] text-zinc-500">Argus</p>
            <h1 class="text-3xl font-semibold tracking-tight text-zinc-950">Log in</h1>
            <p class="text-sm leading-6 text-zinc-500">
              Use the invitation-issued account credentials for your team.
            </p>
          </div>

          <.form
            for={@form}
            id="login-form"
            action={~p"/login"}
            phx-submit="submit"
            phx-trigger-action={@trigger_submit}
            class="space-y-5"
          >
            <.input
              field={@form[:email]}
              type="email"
              label="Email"
              autocomplete="username"
              required
              phx-mounted={JS.focus()}
            />
            <.input
              field={@form[:password]}
              type="password"
              label="Password"
              autocomplete="current-password"
              required
            />
            <label class="flex items-center gap-3 text-sm text-zinc-600">
              <input type="hidden" name={@form[:remember_me].name} value="false" />
              <input
                id="remember-me"
                type="checkbox"
                name={@form[:remember_me].name}
                value="true"
                checked
                class="h-4 w-4 rounded-sm border-zinc-300 text-zinc-950 focus:ring-zinc-400"
              />
              <span>Keep me signed in on this device</span>
            </label>
            <.button class="w-full">Log in</.button>
          </.form>
        </div>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: UserAuth.signed_in_path(user))}
  end

  def mount(_params, _session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email, "password" => "", "remember_me" => "true"}, as: :user)

    {:ok, assign(socket, form: form, trigger_submit: false)}
  end

  @impl true
  def handle_event("submit", %{"user" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: :user), trigger_submit: true)}
  end
end
