defmodule ArgusWeb.AdminLive.Index do
  use ArgusWeb, :live_view

  alias Argus.Accounts
  alias Argus.Accounts.User
  alias Argus.Mailer
  alias Argus.Projects
  alias Argus.Teams
  alias Argus.Teams.Team
  alias ArgusWeb.AppShell
  alias ArgusWeb.UserAuth

  @role_options [{"Member", "member"}, {"Admin", "admin"}]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} sidebar={@sidebar}>
      <.header>
        Admin
        <:subtitle>Manage users, teams, and projects.</:subtitle>
        <:actions>
          <.button
            id="open-add-user-modal"
            type="button"
            phx-click="open-modal"
            phx-value-modal="add-user"
          >
            <.icon name="hero-user-plus-mini" class="size-4" /> Add user
          </.button>
          <.button
            id="open-team-modal"
            type="button"
            phx-click="open-modal"
            phx-value-modal="team"
            variant="secondary"
          >
            Create team
          </.button>
        </:actions>
      </.header>

      <section class="border border-zinc-200 bg-white shadow-[0_1px_3px_rgba(15,23,42,0.08)]">
        <div
          id="admin-tabs"
          class="flex items-center gap-5 overflow-x-auto border-b border-zinc-200 px-4 pt-4 whitespace-nowrap sm:px-6"
        >
          <.link patch={~p"/admin?tab=users"} class={tab_class(@tab == "users")}>Users</.link>
          <.link patch={~p"/admin?tab=teams"} class={tab_class(@tab == "teams")}>Teams</.link>
          <.link patch={~p"/admin?tab=projects"} class={tab_class(@tab == "projects")}>
            Projects
          </.link>
          <.link patch={~p"/admin?tab=system"} class={tab_class(@tab == "system")}>
            System
          </.link>
        </div>

        <div class="min-w-0 p-4 sm:p-6">
          <%= if @tab == "users" do %>
            <div class="space-y-4">
              <div>
                <h2 class="text-lg font-semibold tracking-tight text-zinc-950">Users</h2>
                <p class="mt-1 text-sm text-zinc-500">
                  Active and pending accounts across the entire workspace.
                </p>
              </div>

              <.table id="admin-users" rows={@users}>
                <:col :let={user} label="Name">{user.name}</:col>
                <:col :let={user} label="Email">{user.email}</:col>
                <:col :let={user} label="Role">
                  <.badge kind={user.role}>{user.role}</.badge>
                </:col>
                <:col :let={user} label="Teams">
                  <span :if={user.team_members == []} class="text-zinc-400">No team</span>
                  {Enum.map_join(user.team_members, ", ", & &1.team.name)}
                </:col>
                <:col :let={user} label="Invited by">{latest_inviter_name(user)}</:col>
                <:col :let={user} label="Status">
                  <.badge kind={if user.confirmed_at, do: :active, else: :pending}>
                    {if user.confirmed_at, do: "active", else: "pending"}
                  </.badge>
                </:col>
                <:col :let={user} label="Actions" class="whitespace-nowrap">
                  <.action_button
                    type="button"
                    phx-click="open-modal"
                    phx-value-modal="user"
                    phx-value-id={user.id}
                    icon="hero-cog-6-tooth-mini"
                    id={"edit-user-#{user.id}"}
                  >
                    Edit user
                  </.action_button>
                </:col>
              </.table>
              <.empty_state
                :if={length(@users) == 1}
                title="Invite your team"
                description="Invite your team to start collaborating."
                icon="hero-user-plus"
              />
            </div>
          <% end %>

          <%= if @tab == "teams" do %>
            <div class="space-y-4">
              <div>
                <h2 class="text-lg font-semibold tracking-tight text-zinc-950">Teams</h2>
                <p class="mt-1 text-sm text-zinc-500">
                  Member counts and project ownership across your workspace.
                </p>
              </div>

              <.table id="admin-teams" rows={@teams}>
                <:col :let={team} label="Name">{team.name}</:col>
                <:col :let={team} label="Members">
                  <div class="flex items-center gap-3">
                    <div class="flex -space-x-2">
                      <span
                        :for={team_member <- Enum.take(team.team_members, 4)}
                        title={team_member.user.name || team_member.user.email}
                        class="flex size-7 items-center justify-center rounded-full border border-white bg-zinc-100 text-[11px] font-semibold uppercase text-zinc-700 ring-1 ring-zinc-200"
                      >
                        {String.first(team_member.user.name || team_member.user.email)}
                      </span>
                    </div>
                    <span class="text-sm text-zinc-600">{length(team.team_members)}</span>
                  </div>
                </:col>
                <:col :let={team} label="Projects">{Map.get(@team_project_counts, team.id, 0)}</:col>
                <:col :let={team} label="Health">
                  <.badge kind={
                    if Map.get(@team_unresolved_counts, team.id, 0) > 0,
                      do: :unresolved,
                      else: :resolved
                  }>
                    {Map.get(@team_unresolved_counts, team.id, 0)} unresolved
                  </.badge>
                </:col>
                <:col :let={team} label="Actions">
                  <.action_button
                    navigate={~p"/teams/#{team.id}/settings?tab=projects"}
                    icon="hero-cog-6-tooth-mini"
                  >
                    Settings
                  </.action_button>
                </:col>
              </.table>
            </div>
          <% end %>

          <%= if @tab == "projects" do %>
            <div class="space-y-4">
              <div>
                <h2 class="text-lg font-semibold tracking-tight text-zinc-950">Projects</h2>
                <p class="mt-1 text-sm text-zinc-500">
                  Open issues, logs, or project settings.
                </p>
              </div>

              <.table id="admin-projects" rows={@projects}>
                <:col :let={project} label="Project">{project.name}</:col>
                <:col :let={project} label="Team">{project.team.name}</:col>
                <:col :let={project} label="Issues">
                  {project_stat(@project_stats, project.id, :issue_count)}
                </:col>
                <:col :let={project} label="Logs">
                  {project_stat(@project_stats, project.id, :log_count)}
                </:col>
                <:col :let={project} label="Actions" class="whitespace-nowrap">
                  <div class="flex flex-wrap items-center gap-2">
                    <.action_button
                      navigate={~p"/projects/#{project.slug}/issues"}
                      icon="hero-bug-ant-mini"
                    >
                      Issues
                    </.action_button>
                    <.action_button
                      navigate={~p"/projects/#{project.slug}/logs"}
                      icon="hero-document-text-mini"
                    >
                      Logs
                    </.action_button>
                    <.overflow_menu id={"project-actions-#{project.id}"}>
                      <:item navigate={~p"/projects/#{project.slug}/settings"}>
                        Project settings
                      </:item>
                    </.overflow_menu>
                  </div>
                </:col>
              </.table>
            </div>
          <% end %>

          <%= if @tab == "system" do %>
            <div class="space-y-4">
              <div>
                <h2 class="text-lg font-semibold tracking-tight text-zinc-950">System</h2>
                <p class="mt-1 text-sm text-zinc-500">
                  Runtime version details for the deployed Argus instance.
                </p>
              </div>

              <section
                id="system-version"
                class="grid gap-4 border border-zinc-200 bg-slate-50 p-4 sm:grid-cols-2"
              >
                <div>
                  <p class="text-xs font-semibold uppercase text-zinc-500">Application version</p>
                  <p id="system-app-version" class="mt-2 font-mono text-sm text-zinc-950">
                    {@system_version.app}
                  </p>
                </div>
                <div>
                  <p class="text-xs font-semibold uppercase text-zinc-500">Git revision</p>
                  <p id="system-revision" class="mt-2 font-mono text-sm text-zinc-950">
                    {@system_version.revision}
                  </p>
                </div>
              </section>
            </div>
          <% end %>
        </div>
      </section>

      <.modal
        id="add-user-modal"
        open={@add_user_modal_open}
        title="Add user"
        size="lg"
        on_cancel={JS.push("close-modal", value: %{modal: "add-user"})}
      >
        <%= if @invite_result do %>
          <div id="invite-result" class="space-y-6">
            <div class="flex items-start gap-3">
              <div class={[
                "flex size-9 shrink-0 items-center justify-center rounded-full",
                invite_result_tone(@invite_result.email_status)
              ]}>
                <.icon name={invite_result_icon(@invite_result.email_status)} class="size-5" />
              </div>
              <div class="min-w-0">
                <p class="font-medium text-zinc-950">
                  {@invite_result.name} was invited
                </p>
                <p id="invite-result-message" class="mt-0.5 text-sm text-zinc-500">
                  {invite_result_message(@invite_result)}
                </p>
              </div>
            </div>

            <div class="space-y-2">
              <p class="text-xs font-semibold uppercase tracking-wide text-zinc-500">
                Invitation link
              </p>
              <.copy_to_clipboard
                id="invite-result-copy"
                value={@invite_result.url}
                toast_message="Invitation link copied"
              />
              <p class="text-xs text-zinc-500">
                Valid for 72 hours. Whoever opens it chooses the password for this account, so share it only with {@invite_result.email}.
              </p>
            </div>

            <div class="flex justify-end gap-3">
              <.button
                id="add-another-user"
                type="button"
                variant="ghost"
                phx-click="add-another-user"
              >
                Add another
              </.button>
              <.button
                id="invite-result-done"
                type="button"
                phx-click="close-modal"
                phx-value-modal="add-user"
              >
                Done
              </.button>
            </div>
          </div>
        <% else %>
          <.form
            for={@add_user_form}
            id="add-user-form"
            phx-change="validate-new-user"
            phx-submit="create-user"
            class="space-y-5"
          >
            <fieldset class="space-y-2">
              <legend class="text-sm font-medium text-zinc-600">How do they get access?</legend>
              <div class="grid gap-2 sm:grid-cols-2">
                <.method_option
                  id="add-user-method-invite"
                  value="invite"
                  checked={@add_user_method == "invite"}
                  icon="hero-link"
                  title="Invitation link"
                  description={
                    if @email_enabled,
                      do: "We email a link and they choose their password.",
                      else: "You share a link and they choose their password."
                  }
                />
                <.method_option
                  id="add-user-method-password"
                  value="password"
                  checked={@add_user_method == "password"}
                  icon="hero-key"
                  title="Set a password"
                  description="The account is active right away. No email needed."
                />
              </div>
            </fieldset>

            <div class="grid gap-4 sm:grid-cols-2">
              <.input field={@add_user_form[:name]} type="text" label="Name" required />
              <.input field={@add_user_form[:email]} type="email" label="Email" required />
            </div>

            <div
              :if={@add_user_method == "password"}
              id="add-user-password-fields"
              class="grid gap-4 sm:grid-cols-2"
            >
              <.input
                field={@add_user_form[:password]}
                type="password"
                label="Password"
                autocomplete="new-password"
                required
              />
              <.input
                field={@add_user_form[:password_confirmation]}
                type="password"
                label="Confirm password"
                autocomplete="new-password"
                required
              />
            </div>

            <.input
              field={@add_user_form[:role]}
              type="select"
              label="Global role"
              options={@role_options}
            />

            <div class="grid gap-4 sm:grid-cols-[minmax(0,1fr)_10rem]">
              <.input
                field={@add_user_form[:team_id]}
                type="select"
                label="Team"
                prompt="No team"
                options={team_options(@teams)}
              />
              <.input
                field={@add_user_form[:team_role]}
                type="select"
                label="Team role"
                options={@role_options}
              />
            </div>

            <p
              :if={not @email_enabled and @add_user_method == "invite"}
              id="email-disabled-hint"
              class="flex items-start gap-2 border border-amber-200 bg-amber-50 px-3 py-2 text-sm text-amber-800"
            >
              <.icon name="hero-envelope-mini" class="mt-0.5 size-4 shrink-0" />
              Email delivery is not configured. You'll get a link to share with them yourself.
            </p>

            <div class="flex justify-end gap-3">
              <.button
                type="button"
                variant="ghost"
                phx-click="close-modal"
                phx-value-modal="add-user"
              >
                Cancel
              </.button>
              <.button id="add-user-submit" phx-disable-with="Saving...">
                {add_user_submit_label(@add_user_method, @email_enabled)}
              </.button>
            </div>
          </.form>
        <% end %>
      </.modal>

      <.modal
        id="team-modal"
        open={@team_modal_open}
        title="Create team"
        on_cancel={JS.push("close-modal", value: %{modal: "team"})}
      >
        <.form for={@team_form} id="team-form" phx-submit="create-team" class="space-y-5">
          <.input field={@team_form[:name]} type="text" label="Team name" required />

          <div class="flex justify-end gap-3">
            <.button type="button" variant="ghost" phx-click="close-modal" phx-value-modal="team">
              Cancel
            </.button>
            <.button>Create team</.button>
          </div>
        </.form>
      </.modal>

      <.modal
        id="user-modal"
        open={@user_modal_open}
        title="Edit user"
        subtitle={@selected_user && @selected_user.email}
        size="lg"
        on_cancel={JS.push("close-modal", value: %{modal: "user"})}
      >
        <%= if @selected_user do %>
          <div class="space-y-8">
            <div id="user-status" class="flex flex-wrap items-center gap-3">
              <.badge kind={if @selected_user.confirmed_at, do: :active, else: :pending}>
                {if @selected_user.confirmed_at, do: "active", else: "pending"}
              </.badge>
              <span class="text-sm text-zinc-500">
                {if @selected_user.confirmed_at,
                  do: "Can log in with their password.",
                  else: "Has not set a password yet, so they can't log in."}
              </span>
            </div>

            <section class="space-y-4">
              <.section_heading
                title="Profile"
                description="Name, email, and global role. Admins have full access to every team and project."
              />

              <.form
                for={@edit_user_form}
                id="edit-user-form"
                phx-change="validate-user"
                phx-submit="save-user"
                class="space-y-4"
              >
                <div class="grid gap-4 sm:grid-cols-2">
                  <.input field={@edit_user_form[:name]} type="text" label="Name" required />
                  <.input field={@edit_user_form[:email]} type="email" label="Email" required />
                </div>
                <div class="space-y-2 sm:max-w-[calc(50%-0.5rem)]">
                  <.input
                    field={@edit_user_form[:role]}
                    type="select"
                    label="Global role"
                    options={@role_options}
                    disabled={self?(@selected_user, @current_scope)}
                  />
                  <p :if={self?(@selected_user, @current_scope)} class="text-xs text-zinc-500">
                    You can't change your own global role.
                  </p>
                </div>
                <p :if={is_nil(@selected_user.confirmed_at)} class="text-xs text-zinc-500">
                  Changing the email of a pending user invalidates their current invitation link.
                </p>
                <div class="flex justify-end">
                  <.button id="save-user" phx-disable-with="Saving...">Save changes</.button>
                </div>
              </.form>
            </section>

            <section
              :if={not self?(@selected_user, @current_scope)}
              id="user-password"
              class="space-y-4 border-t border-zinc-200 pt-6"
            >
              <.section_heading
                title={
                  if @selected_user.confirmed_at,
                    do: "Reset password",
                    else: "Activate with a password"
                }
                description={
                  if @selected_user.confirmed_at,
                    do: "Set a new password for them. They will be signed out on every device.",
                    else:
                      "Set a password to activate the account without email. Share it with them securely."
                }
              />

              <.form
                for={@password_form}
                id="set-user-password-form"
                phx-submit="set-user-password"
                class="grid gap-4 sm:grid-cols-2"
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
                <div class="flex justify-end sm:col-span-2">
                  <.button
                    id="set-user-password-submit"
                    variant="secondary"
                    phx-disable-with="Saving..."
                  >
                    {if @selected_user.confirmed_at,
                      do: "Reset password",
                      else: "Set password & activate"}
                  </.button>
                </div>
              </.form>
            </section>

            <section
              :if={is_nil(@selected_user.confirmed_at)}
              id="user-invitation"
              class="space-y-4 border-t border-zinc-200 pt-6"
            >
              <.section_heading
                title="Invitation link"
                description="Or let them choose their own password: share this link."
              />

              <%= if @pending_invitation do %>
                <div class="space-y-2">
                  <.copy_to_clipboard
                    id="user-invitation-copy"
                    value={invitation_url(@pending_invitation)}
                    toast_message="Invitation link copied"
                  />
                  <p class="text-xs text-zinc-500">
                    Expires {format_datetime(@pending_invitation.expires_at)}.
                  </p>
                </div>
              <% else %>
                <div
                  id="user-invitation-missing"
                  class="border border-dashed border-zinc-300 px-4 py-4 text-sm text-zinc-500"
                >
                  No active link. It expired or the email changed. Generate a new one.
                </div>
              <% end %>

              <div class="flex flex-wrap gap-3">
                <.button
                  id={"resend-user-invitation-#{@selected_user.id}"}
                  type="button"
                  variant="secondary"
                  phx-click="resend-user-invitation"
                  phx-value-id={@selected_user.id}
                >
                  <.icon name="hero-arrow-path-mini" class="size-4" />
                  {if @email_enabled, do: "Generate and email new link", else: "Generate new link"}
                </.button>
              </div>
            </section>

            <section class="space-y-3 border-t border-zinc-200 pt-6">
              <.section_heading
                title="Team memberships"
                description="Add this user to teams, adjust their team role, or remove access."
              />

              <%= if @selected_user.team_members == [] do %>
                <div class="border border-dashed border-zinc-300 px-4 py-6 text-sm text-zinc-500">
                  This user is not assigned to any team yet.
                </div>
              <% else %>
                <div class="space-y-3">
                  <div
                    :for={team_member <- @selected_user.team_members}
                    id={"user-team-member-#{team_member.id}"}
                    class="flex flex-col gap-4 border border-zinc-200 px-4 py-4 sm:flex-row sm:items-center sm:justify-between"
                  >
                    <div>
                      <p class="text-sm font-medium text-zinc-950">{team_member.team.name}</p>
                      <p class="mt-1 text-xs text-zinc-500">Team access</p>
                    </div>

                    <div class="flex flex-wrap items-center gap-2">
                      <.form
                        for={user_team_role_form(team_member)}
                        id={"user-team-role-#{team_member.id}"}
                        phx-change="update-user-team-role"
                      >
                        <input
                          type="hidden"
                          name="user_team_role[team_member_id]"
                          value={team_member.id}
                        />
                        <.input
                          id={"user-team-role-select-#{team_member.id}"}
                          field={user_team_role_form(team_member)[:role]}
                          type="select"
                          options={@role_options}
                          class="max-w-[9rem]"
                        />
                      </.form>

                      <.action_button
                        id={"remove-user-team-member-#{team_member.id}"}
                        type="button"
                        phx-click="remove-user-team-membership"
                        phx-value-id={team_member.id}
                        icon="hero-user-minus-mini"
                        class="hover:border-red-200 hover:bg-red-50 hover:text-red-700"
                      >
                        Remove
                      </.action_button>
                    </div>
                  </div>
                </div>
              <% end %>
            </section>

            <section :if={available_team_options(@selected_user, @teams) != []} class="space-y-3">
              <.section_heading
                title="Add to team"
                description="Assign this user to another team without leaving the users tab."
              />

              <.form
                for={@user_team_form}
                id="user-team-form"
                phx-submit="add-user-team"
                class="grid gap-4 sm:grid-cols-[minmax(0,1fr)_10rem_auto]"
              >
                <.input
                  field={@user_team_form[:team_id]}
                  type="select"
                  label="Team"
                  options={available_team_options(@selected_user, @teams)}
                />
                <.input
                  field={@user_team_form[:role]}
                  type="select"
                  label="Role"
                  options={@role_options}
                />
                <div class="flex items-end">
                  <.button variant="secondary">Add membership</.button>
                </div>
              </.form>
            </section>

            <section
              :if={not self?(@selected_user, @current_scope)}
              class="space-y-3 border-t border-zinc-200 pt-6"
            >
              <.section_heading
                title="Danger zone"
                description="Delete this user and remove their invitations, sessions, and team memberships."
              />

              <div class="flex flex-wrap gap-3">
                <.button
                  id={"delete-user-#{@selected_user.id}"}
                  type="button"
                  variant="danger"
                  phx-click="delete-user"
                  phx-value-id={@selected_user.id}
                >
                  Delete user
                </.button>
              </div>
            </section>
          </div>
        <% end %>

        <:actions>
          <.button
            id="user-modal-done"
            type="button"
            variant="ghost"
            phx-click="close-modal"
            phx-value-modal="user"
          >
            Close
          </.button>
        </:actions>
      </.modal>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :value, :string, required: true
  attr :checked, :boolean, default: false
  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true

  defp method_option(assigns) do
    ~H"""
    <label
      for={@id}
      class={[
        "group flex cursor-pointer items-start gap-3 rounded-sm border px-4 py-3 transition duration-150",
        if(@checked,
          do: "border-sky-500 bg-sky-50/70 ring-2 ring-sky-500/15",
          else: "border-zinc-200 hover:border-zinc-300 hover:bg-zinc-50"
        )
      ]}
    >
      <input
        id={@id}
        type="radio"
        name="user[method]"
        value={@value}
        checked={@checked}
        class="sr-only"
      />
      <.icon
        name={@icon}
        class={[
          "mt-0.5 size-5 shrink-0 transition",
          if(@checked, do: "text-sky-600", else: "text-zinc-400 group-hover:text-zinc-500")
        ]}
      />
      <span>
        <span class="block text-sm font-medium text-zinc-950">{@title}</span>
        <span class="mt-0.5 block text-xs leading-5 text-zinc-500">{@description}</span>
      </span>
    </label>
    """
  end

  attr :title, :string, required: true
  attr :description, :string, required: true

  defp section_heading(assigns) do
    ~H"""
    <div>
      <h3 class="text-base font-semibold text-zinc-950">{@title}</h3>
      <p class="mt-1 text-sm text-zinc-500">{@description}</p>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    if user.role != :admin do
      {:ok, push_navigate(socket, to: UserAuth.signed_in_path(user))}
    else
      {:ok,
       socket
       |> assign(:sidebar, AppShell.build(user, section: :admin))
       |> assign(:role_options, @role_options)
       |> assign(:email_enabled, Mailer.enabled?())
       |> assign(:add_user_modal_open, false)
       |> assign(:team_modal_open, false)
       |> assign(:user_modal_open, false)
       |> assign(:selected_user_id, nil)
       |> assign_forms()
       |> load_data()}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :tab, normalize_tab(params["tab"]))}
  end

  @impl true
  def handle_event("open-modal", %{"modal" => "add-user"}, socket) do
    {:noreply, socket |> reset_add_user() |> assign(:add_user_modal_open, true)}
  end

  def handle_event("open-modal", %{"modal" => "team"}, socket) do
    {:noreply, assign(socket, :team_modal_open, true)}
  end

  def handle_event("open-modal", %{"modal" => "user", "id" => user_id}, socket) do
    socket =
      socket
      |> assign(:selected_user_id, String.to_integer(user_id))
      |> load_data()

    case socket.assigns.selected_user do
      nil ->
        {:noreply, put_flash(socket, :error, "User not found.")}

      user ->
        {:noreply,
         socket
         |> assign_user_forms(user)
         |> assign(:user_modal_open, true)}
    end
  end

  def handle_event("close-modal", %{"modal" => "add-user"}, socket) do
    {:noreply, socket |> assign(:add_user_modal_open, false) |> reset_add_user()}
  end

  def handle_event("close-modal", %{"modal" => "team"}, socket) do
    {:noreply, assign(socket, :team_modal_open, false)}
  end

  def handle_event("close-modal", %{"modal" => "user"}, socket) do
    {:noreply,
     socket
     |> assign(:user_modal_open, false)
     |> assign(:selected_user_id, nil)
     |> assign(:selected_user, nil)}
  end

  def handle_event("add-another-user", _params, socket) do
    {:noreply, reset_add_user(socket)}
  end

  def handle_event("validate-new-user", %{"user" => params}, socket) do
    method = normalize_method(params["method"])

    {:noreply,
     socket
     |> assign(:add_user_method, method)
     |> assign(:add_user_form, add_user_form(params, method, :validate))}
  end

  def handle_event("create-user", %{"user" => params}, socket) do
    case normalize_method(params["method"]) do
      "password" -> create_user_with_password(socket, params)
      "invite" -> invite_user(socket, params)
    end
  end

  def handle_event("resend-user-invitation", %{"id" => user_id}, socket) do
    inviter = socket.assigns.current_scope.user

    case Enum.find(socket.assigns.users, &(&1.id == String.to_integer(user_id))) do
      nil ->
        {:noreply, put_flash(socket, :error, "User not found.")}

      user ->
        case Accounts.resend_user_invitation(inviter, user, &url(~p"/invitations/#{&1}")) do
          {:ok, _invitation, email_status} ->
            {kind, message} = resend_flash(email_status)
            {:noreply, socket |> load_data() |> put_flash(kind, message)}

          {:error, :already_active} ->
            {:noreply, put_flash(socket, :error, "Only pending users can be reinvited.")}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Could not generate a new invitation link.")}
        end
    end
  end

  def handle_event("create-team", %{"team" => params}, socket) do
    case Teams.create_team(params) do
      {:ok, _team} ->
        {:noreply,
         socket
         |> assign(:team_modal_open, false)
         |> assign_forms()
         |> load_data()
         |> put_flash(:info, "Team created.")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:team_modal_open, true)
         |> assign(:team_form, to_form(changeset, as: :team))}
    end
  end

  def handle_event("validate-user", %{"edit_user" => params}, socket) do
    case socket.assigns.selected_user do
      nil ->
        {:noreply, socket}

      user ->
        form =
          user
          |> Accounts.change_admin_user(params, socket.assigns.current_scope.user)
          |> Map.put(:action, :validate)
          |> to_form(as: :edit_user)

        {:noreply, assign(socket, :edit_user_form, form)}
    end
  end

  def handle_event("save-user", %{"edit_user" => params}, socket) do
    case socket.assigns.selected_user do
      nil ->
        {:noreply, put_flash(socket, :error, "User not found.")}

      user ->
        case Accounts.admin_update_user(user, params, socket.assigns.current_scope.user) do
          {:ok, updated_user} ->
            {:noreply,
             socket
             |> load_data()
             |> assign(:edit_user_form, edit_user_form(updated_user, socket))
             |> put_flash(:info, "User updated.")}

          {:error, changeset} ->
            {:noreply, assign(socket, :edit_user_form, to_form(changeset, as: :edit_user))}
        end
    end
  end

  def handle_event("set-user-password", %{"user_password" => params}, socket) do
    user = socket.assigns.selected_user

    cond do
      is_nil(user) ->
        {:noreply, put_flash(socket, :error, "User not found.")}

      self?(user, socket.assigns.current_scope) ->
        {:noreply, put_flash(socket, :error, "Change your own password from your settings.")}

      true ->
        case Accounts.admin_set_user_password(user, params) do
          {:ok, {_user, expired_tokens}} ->
            UserAuth.disconnect_sessions(expired_tokens)

            message =
              if user.confirmed_at,
                do: "Password reset. They were signed out everywhere.",
                else: "Password set. The account is active."

            {:noreply,
             socket
             |> load_data()
             |> assign(:password_form, password_form())
             |> put_flash(:info, message)}

          {:error, changeset} ->
            {:noreply, assign(socket, :password_form, to_form(changeset, as: :user_password))}
        end
    end
  end

  def handle_event(
        "update-user-team-role",
        %{"user_team_role" => %{"team_member_id" => team_member_id, "role" => role}},
        socket
      ) do
    case find_selected_team_member(socket, team_member_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Membership not found.")}

      team_member ->
        {:ok, _team_member} = Teams.update_member_role(team_member, String.to_existing_atom(role))
        {:noreply, socket |> load_data() |> put_flash(:info, "Team role updated.")}
    end
  end

  def handle_event("remove-user-team-membership", %{"id" => team_member_id}, socket) do
    case find_selected_team_member(socket, team_member_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Membership not found.")}

      team_member ->
        Teams.remove_member(team_member.team, team_member.user_id)
        {:noreply, socket |> load_data() |> put_flash(:info, "Team membership removed.")}
    end
  end

  def handle_event(
        "add-user-team",
        %{"user_team" => %{"team_id" => team_id, "role" => role}},
        socket
      ) do
    with %User{} = user <- socket.assigns.selected_user,
         %Team{} = team <- Teams.get_team(team_id),
         {:ok, _membership} <- Teams.add_member(team, user, String.to_existing_atom(role)) do
      {:noreply, socket |> load_data() |> put_flash(:info, "Team membership added.")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not add team membership.")}
    end
  end

  def handle_event("delete-user", %{"id" => user_id}, socket) do
    user_id = String.to_integer(user_id)

    cond do
      user_id == socket.assigns.current_scope.user.id ->
        {:noreply, put_flash(socket, :error, "You cannot delete your own account here.")}

      user = Enum.find(socket.assigns.users, &(&1.id == user_id)) ->
        {:ok, _user} = Accounts.delete_user(user)

        {:noreply,
         socket
         |> assign(:user_modal_open, false)
         |> assign(:selected_user_id, nil)
         |> load_data()
         |> put_flash(:info, "User deleted.")}

      true ->
        {:noreply, put_flash(socket, :error, "User not found.")}
    end
  end

  defp create_user_with_password(socket, params) do
    case Accounts.admin_create_user(params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:add_user_modal_open, false)
         |> reset_add_user()
         |> load_data()
         |> put_flash(:info, "#{user.name} was added and can log in now.")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:add_user_method, "password")
         |> assign(:add_user_form, to_form(changeset, as: :user))}
    end
  end

  defp invite_user(socket, params) do
    inviter = socket.assigns.current_scope.user

    case Accounts.deliver_user_invitation(inviter, params, &url(~p"/invitations/#{&1}")) do
      {:ok, invitation, email_status} ->
        {:noreply,
         socket
         |> assign(:invite_result, %{
           name: invitation.user.name,
           email: invitation.email,
           url: invitation_url(invitation),
           email_status: email_status
         })
         |> load_data()}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:add_user_method, "invite")
         |> assign(:add_user_form, to_form(changeset, as: :user))}
    end
  end

  defp assign_forms(socket) do
    socket
    |> reset_add_user()
    |> assign(:team_form, to_form(Team.changeset(%Team{}, %{}), as: :team))
  end

  defp reset_add_user(socket) do
    method = if socket.assigns.email_enabled, do: "invite", else: "password"

    socket
    |> assign(:invite_result, nil)
    |> assign(:add_user_method, method)
    |> assign(
      :add_user_form,
      add_user_form(
        %{"role" => "member", "method" => method, "team_id" => "", "team_role" => "member"},
        method,
        nil
      )
    )
  end

  # Validation only: the password is checked but not hashed until the user is created.
  defp add_user_form(params, method, action) do
    changeset = User.invited_user_changeset(%User{}, params, validate_unique: false)

    changeset =
      if method == "password",
        do: User.password_changeset(changeset, params, hash_password: false),
        else: changeset

    changeset
    |> Map.put(:action, action)
    |> to_form(as: :user)
  end

  defp assign_user_forms(socket, user) do
    socket
    |> assign(:edit_user_form, edit_user_form(user, socket))
    |> assign(:password_form, password_form())
  end

  defp edit_user_form(user, socket) do
    user
    |> Accounts.change_admin_user(%{}, socket.assigns.current_scope.user)
    |> to_form(as: :edit_user)
  end

  defp password_form do
    to_form(%{"password" => "", "password_confirmation" => ""}, as: :user_password)
  end

  defp load_data(socket) do
    user = socket.assigns.current_scope.user
    projects = Projects.list_all_projects_for_user(user)
    users = Accounts.list_users()
    teams = Teams.list_teams()
    selected_user = selected_user(users, socket.assigns[:selected_user_id])
    project_stats = Projects.project_stats(projects)

    socket
    |> assign(:tab, socket.assigns[:tab] || "users")
    |> assign(:users, users)
    |> assign(:teams, teams)
    |> assign(:selected_user, selected_user)
    |> assign(
      :pending_invitation,
      selected_user && Accounts.get_pending_invitation(selected_user)
    )
    |> assign(:user_team_form, user_team_form(selected_user, teams))
    |> assign(:projects, projects)
    |> assign(:project_stats, project_stats)
    |> assign(:system_version, system_version())
    |> assign(
      :team_project_counts,
      Enum.frequencies_by(projects, & &1.team_id)
    )
    |> assign(:team_unresolved_counts, team_unresolved_counts(projects, project_stats))
  end

  defp normalize_method("password"), do: "password"
  defp normalize_method(_method), do: "invite"

  defp self?(%User{id: id}, %{user: %User{id: id}}), do: true
  defp self?(_user, _scope), do: false

  defp team_options(teams), do: Enum.map(teams, &{&1.name, Integer.to_string(&1.id)})

  defp invitation_url(invitation), do: url(~p"/invitations/#{invitation.token}")

  defp format_datetime(datetime), do: Calendar.strftime(datetime, "%b %-d, %Y at %H:%M UTC")

  defp add_user_submit_label("password", _email_enabled), do: "Create user"
  defp add_user_submit_label(_invite, true), do: "Send invitation"
  defp add_user_submit_label(_invite, false), do: "Create invitation link"

  defp invite_result_message(%{email_status: :sent, email: email}),
    do: "We emailed the invitation to #{email}. You can also share the link below."

  defp invite_result_message(%{email_status: :disabled}),
    do: "Email delivery is not configured. Copy the link below and share it with them."

  defp invite_result_message(%{email_status: :failed}),
    do: "The invitation email could not be sent. Copy the link below and share it with them."

  defp invite_result_tone(:sent), do: "bg-emerald-50 text-emerald-600"
  defp invite_result_tone(:disabled), do: "bg-sky-50 text-sky-600"
  defp invite_result_tone(:failed), do: "bg-amber-50 text-amber-600"

  defp invite_result_icon(:sent), do: "hero-envelope"
  defp invite_result_icon(:disabled), do: "hero-link"
  defp invite_result_icon(:failed), do: "hero-exclamation-triangle"

  defp resend_flash(:sent), do: {:info, "A new invitation link was emailed."}
  defp resend_flash(:disabled), do: {:info, "New invitation link ready to copy."}

  defp resend_flash(:failed),
    do: {:error, "New invitation link ready, but the email could not be sent. Copy it instead."}

  defp latest_inviter_name(user) do
    user.received_invitations
    |> List.first()
    |> case do
      nil -> "-"
      invitation -> (invitation.invited_by && invitation.invited_by.name) || "-"
    end
  end

  defp normalize_tab(tab) when tab in ~w(users teams projects system), do: tab
  defp normalize_tab(_), do: "users"

  defp system_version do
    %{
      app: Application.spec(:argus, :vsn) |> to_string(),
      revision: System.get_env("ARGUS_REVISION", "unknown")
    }
  end

  defp user_team_role_form(team_member) do
    to_form(%{"team_member_id" => team_member.id, "role" => to_string(team_member.role)},
      as: :user_team_role
    )
  end

  defp user_team_form(nil, _teams),
    do: to_form(%{"team_id" => "", "role" => "member"}, as: :user_team)

  defp user_team_form(user, teams) do
    team_id =
      user
      |> available_team_options(teams)
      |> List.first()
      |> case do
        nil -> ""
        {_name, team_id} -> team_id
      end

    to_form(%{"team_id" => team_id, "role" => "member"}, as: :user_team)
  end

  defp available_team_options(user, teams) do
    assigned_team_ids = MapSet.new(Enum.map(user.team_members, & &1.team_id))

    Enum.reduce(teams, [], fn team, acc ->
      if MapSet.member?(assigned_team_ids, team.id) do
        acc
      else
        acc ++ [{team.name, Integer.to_string(team.id)}]
      end
    end)
  end

  defp selected_user(_users, nil), do: nil
  defp selected_user(users, user_id), do: Enum.find(users, &(&1.id == user_id))

  defp find_selected_team_member(socket, team_member_id) do
    team_member_id = String.to_integer(team_member_id)

    socket.assigns.selected_user
    |> case do
      nil -> nil
      user -> Enum.find(user.team_members, &(&1.id == team_member_id))
    end
  end

  defp project_stat(project_stats, project_id, key) do
    project_stats
    |> Map.get(project_id, %{})
    |> Map.get(key, 0)
  end

  defp team_unresolved_counts(projects, project_stats) do
    Enum.reduce(projects, %{}, fn project, acc ->
      unresolved_count = project_stat(project_stats, project.id, :unresolved_count)
      Map.update(acc, project.team_id, unresolved_count, &(&1 + unresolved_count))
    end)
  end

  defp tab_class(true),
    do: "border-b-[3px] border-sky-600 px-0 pb-3 text-sm font-semibold text-zinc-950"

  defp tab_class(false),
    do:
      "border-b-2 border-transparent px-0 pb-3 text-sm text-zinc-500 transition hover:border-zinc-300 hover:text-zinc-900"
end
