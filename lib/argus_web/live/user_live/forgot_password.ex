defmodule ArgusWeb.UserLive.ForgotPassword do
  use ArgusWeb, :live_view

  alias Argus.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="border border-zinc-200 bg-white px-8 py-10 sm:px-10">
        <div class="space-y-8">
          <div class="space-y-3 text-center">
            <p class="text-xs uppercase tracking-[0.22em] text-zinc-500">Argus</p>
            <h1 class="text-3xl font-semibold tracking-tight text-zinc-950">Forgot your password?</h1>
            <p :if={@email_enabled} class="text-sm leading-6 text-zinc-500">
              Enter your account email and we'll send you a link to choose a new one.
            </p>
          </div>

          <p
            :if={!@email_enabled}
            id="reset-password-email-disabled"
            class="border border-zinc-200 bg-slate-50 px-4 py-3 text-center text-sm leading-6 text-zinc-600"
          >
            This workspace doesn't send email. Ask a workspace admin to reset your password from the admin panel.
          </p>

          <.form
            :if={@email_enabled}
            for={@form}
            id="reset-password-form"
            phx-submit="send_email"
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
            <.button class="w-full" phx-disable-with="Sending...">Send reset link</.button>
          </.form>

          <p class="text-center text-sm">
            <.link
              id="back-to-login-link"
              navigate={~p"/login"}
              class="text-zinc-500 underline-offset-4 transition hover:text-zinc-950 hover:underline"
            >
              Back to log in
            </.link>
          </p>
        </div>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       form: to_form(%{"email" => ""}, as: :user),
       email_enabled: Argus.Mailer.enabled?()
     )}
  end

  @impl true
  def handle_event("send_email", _params, %{assigns: %{email_enabled: false}} = socket) do
    {:noreply,
     put_flash(
       socket,
       :error,
       "This workspace doesn't send email. Ask a workspace admin to reset your password."
     )}
  end

  def handle_event("send_email", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_reset_password_instructions(user, &url(~p"/reset-password/#{&1}"))
    end

    # Same response either way, so the form can't be used to discover which emails exist.
    {:noreply,
     socket
     |> put_flash(
       :info,
       "If that email belongs to an active account, a reset link is on its way."
     )
     |> push_navigate(to: ~p"/login")}
  end
end
