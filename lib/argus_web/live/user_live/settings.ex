defmodule ArgusWeb.UserLive.Settings do
  use ArgusWeb, :live_view

  alias Argus.Accounts
  alias Argus.Accounts.Scope
  alias ArgusWeb.AppShell

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} sidebar={@sidebar}>
      <.header>
        Your settings
        <:subtitle>Update your profile details and rotate your password.</:subtitle>
      </.header>

      <div class="grid gap-6 xl:grid-cols-[1.1fr_0.9fr]">
        <section class="border border-zinc-200 bg-white p-6">
          <h2 class="text-lg font-semibold text-zinc-950">Profile</h2>
          <.form
            for={@profile_form}
            id="profile-form"
            phx-change="validate-profile"
            phx-submit="save-profile"
            class="mt-6 space-y-5"
          >
            <.input field={@profile_form[:name]} type="text" label="Name" required />
            <.input
              field={@profile_form[:email]}
              type="email"
              label="Email"
              required
              autocomplete="username"
            />
            <div class="flex justify-end">
              <.button variant="secondary">Save profile</.button>
            </div>
          </.form>
        </section>

        <section class="border border-zinc-200 bg-white p-6">
          <h2 class="text-lg font-semibold text-zinc-950">Password</h2>
          <.form
            for={@password_form}
            id="password-form"
            action={~p"/settings/password"}
            method="post"
            phx-change="validate-password"
            phx-submit="save-password"
            phx-trigger-action={@trigger_submit}
            class="mt-6 space-y-5"
          >
            <.input
              field={@password_form[:password]}
              type="password"
              label="New password"
              autocomplete="new-password"
              required
            />
            <.input
              field={@password_form[:password_confirmation]}
              type="password"
              label="Confirm password"
              autocomplete="new-password"
              required
            />
            <div class="flex justify-end">
              <.button>Password update</.button>
            </div>
          </.form>
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    {:ok,
     socket
     |> assign(:sidebar, AppShell.build(user))
     |> assign(
       :profile_form,
       to_form(Accounts.change_user_profile(user, %{}, validate_unique: false), as: :user)
     )
     |> assign(
       :password_form,
       to_form(Accounts.change_user_password(user, %{}, hash_password: false), as: :user)
     )
     |> assign(:trigger_submit, false)}
  end

  @impl true
  def handle_event("validate-profile", %{"user" => params}, socket) do
    form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_profile(params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form(as: :user)

    {:noreply, assign(socket, :profile_form, form)}
  end

  def handle_event("save-profile", %{"user" => params}, socket) do
    case Accounts.update_user_profile(socket.assigns.current_scope.user, params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:current_scope, Scope.for_user(user))
         |> assign(:sidebar, AppShell.build(user))
         |> assign(
           :profile_form,
           to_form(Accounts.change_user_profile(user, %{}, validate_unique: false), as: :user)
         )
         |> put_flash(:info, "Profile updated.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :profile_form, to_form(changeset, as: :user))}
    end
  end

  def handle_event("validate-password", %{"user" => params}, socket) do
    form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form(as: :user)

    {:noreply, assign(socket, :password_form, form)}
  end

  def handle_event("save-password", %{"user" => params}, socket) do
    changeset = Accounts.change_user_password(socket.assigns.current_scope.user, params)

    if changeset.valid? do
      {:noreply, assign(socket, :trigger_submit, true)}
    else
      {:noreply, assign(socket, :password_form, to_form(changeset, as: :user))}
    end
  end
end
