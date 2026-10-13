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
        <:subtitle>Update your profile, rotate your password, and manage API tokens.</:subtitle>
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

      <section id="api-tokens" class="mt-6 border border-zinc-200 bg-white p-6">
        <div class="flex flex-wrap items-start justify-between gap-4">
          <div>
            <h2 class="text-lg font-semibold text-zinc-950">API tokens</h2>
            <p class="mt-1 max-w-2xl text-sm leading-6 text-zinc-600">
              Read-only access for agents and scripts to the projects you can see.
              Requests return Markdown; start at <code class="font-mono text-xs text-zinc-800">{url(~p"/api/v1")}</code>.
            </p>
          </div>
        </div>

        <div
          :if={@new_api_token}
          id="new-api-token"
          class="mt-6 border border-emerald-200 bg-emerald-50/60 p-4"
        >
          <p class="text-sm font-medium text-emerald-900">
            Copy your new token now. It won't be shown again.
          </p>
          <.copy_to_clipboard
            id="copy-new-api-token"
            value={@new_api_token}
            toast_message="Token copied"
            class="mt-3 bg-white"
          />
          <p class="mt-3 text-xs text-emerald-900/80">
            Use it as <code class="font-mono">Authorization: Bearer &lt;token&gt;</code>
          </p>
        </div>

        <.form
          for={@api_token_form}
          id="api-token-form"
          phx-submit="create-api-token"
          class="mt-6 flex flex-wrap items-end gap-3"
        >
          <div class="min-w-64 flex-1">
            <.input
              field={@api_token_form[:name]}
              type="text"
              label="Token name"
              placeholder="e.g. Claude Code on laptop"
              required
            />
          </div>
          <.button id="create-api-token-button" variant="secondary" class="mb-2">
            <.icon name="hero-key-mini" class="size-4" /> Create token
          </.button>
        </.form>

        <div
          id="api-token-list"
          phx-update="stream"
          class="mt-6 divide-y divide-zinc-100 border-t border-zinc-100"
        >
          <p id="api-tokens-empty" class="hidden py-4 text-sm text-zinc-500 only:block">
            No API tokens yet.
          </p>
          <div
            :for={{dom_id, api_token} <- @streams.api_tokens}
            id={dom_id}
            class="group flex items-center justify-between gap-4 py-3 transition-colors hover:bg-slate-50/60"
          >
            <div class="min-w-0">
              <p class="truncate text-sm font-medium text-zinc-900">{api_token.name}</p>
              <p class="mt-0.5 text-xs text-zinc-500">
                Created {Calendar.strftime(api_token.inserted_at, "%b %-d, %Y")} · {last_used_label(
                  api_token.last_used_at
                )}
              </p>
            </div>
            <.button
              id={"revoke-#{dom_id}"}
              type="button"
              variant="ghost"
              size="sm"
              phx-click="revoke-api-token"
              phx-value-id={api_token.id}
              data-confirm={"Revoke \"#{api_token.name}\"? Agents using it will lose access."}
            >
              Revoke
            </.button>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    {:ok,
     socket
     |> assign(:sidebar, AppShell.build(user, section: :account))
     |> assign(
       :profile_form,
       to_form(Accounts.change_user_profile(user, %{}, validate_unique: false), as: :user)
     )
     |> assign(
       :password_form,
       to_form(Accounts.change_user_password(user, %{}, hash_password: false), as: :user)
     )
     |> assign(:trigger_submit, false)
     |> assign(:new_api_token, nil)
     |> assign(:api_token_form, to_form(Accounts.change_api_token(), as: :api_token))
     |> stream(:api_tokens, Accounts.list_api_tokens(user))}
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
         |> assign(:sidebar, AppShell.build(user, section: :account))
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

  def handle_event("create-api-token", %{"api_token" => params}, socket) do
    case Accounts.create_api_token(socket.assigns.current_scope.user, params) do
      {:ok, {raw, api_token}} ->
        {:noreply,
         socket
         |> assign(:new_api_token, raw)
         |> assign(:api_token_form, to_form(Accounts.change_api_token(), as: :api_token))
         |> stream_insert(:api_tokens, api_token, at: 0)}

      {:error, changeset} ->
        {:noreply, assign(socket, :api_token_form, to_form(changeset, as: :api_token))}
    end
  end

  def handle_event("revoke-api-token", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user

    with {id, ""} <- Integer.parse(id),
         :ok <- Accounts.delete_api_token(user, id) do
      {:noreply,
       socket
       |> assign(:new_api_token, nil)
       |> stream_delete_by_dom_id(:api_tokens, "api_tokens-#{id}")
       |> put_flash(:info, "Token revoked.")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Token not found.")}
    end
  end

  def handle_event("save-password", %{"user" => params}, socket) do
    changeset = Accounts.change_user_password(socket.assigns.current_scope.user, params)

    if changeset.valid? do
      {:noreply, assign(socket, :trigger_submit, true)}
    else
      {:noreply, assign(socket, :password_form, to_form(changeset, as: :user))}
    end
  end

  defp last_used_label(nil), do: "Never used"

  defp last_used_label(last_used_at),
    do: "Last used " <> Calendar.strftime(last_used_at, "%b %-d, %Y %H:%M UTC")
end
