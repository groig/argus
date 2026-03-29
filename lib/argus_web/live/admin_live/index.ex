defmodule ArgusWeb.AdminLive.Index do
  use ArgusWeb, :live_view

  alias Argus.Accounts
  alias Argus.Accounts.User
  alias Argus.Projects
  alias Argus.Projects.IssueNotifier
  alias Argus.Teams
  alias Argus.Teams.Team
  alias ArgusWeb.AppShell

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} sidebar={@sidebar}>
      <.header>
        Admin
        <:subtitle>Manage users, teams, and projects.</:subtitle>
        <:actions>
          <.button
            id="open-invite-modal"
            type="button"
            phx-click="open-modal"
            phx-value-modal="invite"
          >
            Invite user
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

      <section
        id="admin-webhook-config"
        class="mb-6 grid gap-4 border border-zinc-200 bg-white px-6 py-5 lg:grid-cols-[minmax(0,1fr)_auto] lg:items-end"
      >
        <div class="space-y-3">
          <div class="flex flex-wrap items-center gap-3">
            <h2 class="text-lg font-semibold tracking-tight text-zinc-950">Issue webhook</h2>
            <.badge kind={if @webhook_url, do: :resolved, else: :warning}>
              {if @webhook_url, do: "configured", else: "not configured"}
            </.badge>
          </div>
          <p class="text-sm text-zinc-500">
            Argus posts issue lifecycle events to this endpoint. Use the test button to verify the integration without ingesting a real event.
          </p>
          <p
            id="admin-webhook-url"
            class="break-all border border-zinc-200 bg-slate-50 px-4 py-3 font-mono text-xs text-zinc-700"
          >
            {@webhook_url || "No webhook URL configured."}
          </p>
        </div>

        <div class="flex items-end">
          <.button
            id="send-test-webhook"
            type="button"
            variant="secondary"
            phx-click="send-test-webhook"
            disabled={is_nil(@webhook_url)}
          >
            Send test event
          </.button>
        </div>
      </section>

      <section class="border border-zinc-200 bg-white">
        <div
          id="admin-tabs"
          class="flex flex-wrap items-center gap-5 border-b border-zinc-200 px-6 pt-4"
        >
          <.link patch={~p"/admin?tab=users"} class={tab_class(@tab == "users")}>Users</.link>
          <.link patch={~p"/admin?tab=teams"} class={tab_class(@tab == "teams")}>Teams</.link>
          <.link patch={~p"/admin?tab=projects"} class={tab_class(@tab == "projects")}>
            Projects
          </.link>
        </div>

        <div class="p-6">
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
                  {Enum.map_join(user.team_members, ", ", & &1.team.name)}
                </:col>
                <:col :let={user} label="Invited by">{latest_inviter_name(user)}</:col>
                <:col :let={user} label="Status">
                  <.badge kind={if user.confirmed_at, do: :resolved, else: :warning}>
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
                  >
                    Manage
                  </.action_button>
                </:col>
              </.table>
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
                <:col :let={team} label="Members">{length(team.team_members)}</:col>
                <:col :let={team} label="Projects">{Map.get(@team_project_counts, team.id, 0)}</:col>
                <:col :let={team} label="Manage">
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
        </div>
      </section>

      <.modal id="invite-user-modal" open={@invite_modal_open} title="Invite user">
        <.form
          for={@invitation_form}
          id="invite-user-form"
          phx-submit="invite-user"
          class="space-y-5"
        >
          <.input field={@invitation_form[:name]} type="text" label="Name" required />
          <.input field={@invitation_form[:email]} type="email" label="Email" required />
          <.input
            field={@invitation_form[:role]}
            type="select"
            label="Role"
            options={[{"Member", "member"}, {"Admin", "admin"}]}
          />

          <div class="flex justify-end gap-3">
            <.button type="button" variant="ghost" phx-click="close-modal" phx-value-modal="invite">
              Cancel
            </.button>
            <.button>Send invitation</.button>
          </div>
        </.form>
      </.modal>

      <.modal id="team-modal" open={@team_modal_open} title="Create team">
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

      <.modal id="user-modal" open={@user_modal_open} title="Manage user">
        <%= if @selected_user do %>
          <div class="space-y-6">
            <section class="grid gap-4 sm:grid-cols-2">
              <div class="border border-zinc-200 bg-slate-50 px-4 py-4">
                <p class="text-[11px] font-semibold uppercase tracking-[0.16em] text-zinc-500">
                  User
                </p>
                <p class="mt-2 text-sm font-medium text-zinc-950">{@selected_user.name}</p>
                <p class="mt-1 text-sm text-zinc-500">{@selected_user.email}</p>
              </div>
              <div class="border border-zinc-200 bg-slate-50 px-4 py-4">
                <p class="text-[11px] font-semibold uppercase tracking-[0.16em] text-zinc-500">
                  Status
                </p>
                <div class="mt-2">
                  <.badge kind={if @selected_user.confirmed_at, do: :resolved, else: :warning}>
                    {if @selected_user.confirmed_at, do: "active", else: "pending"}
                  </.badge>
                </div>
              </div>
            </section>

            <section class="space-y-3">
              <div>
                <h3 class="text-base font-semibold text-zinc-950">Global role</h3>
                <p class="mt-1 text-sm text-zinc-500">
                  Controls full access to every team and project in Argus.
                </p>
              </div>

              <.form
                for={user_role_form(@selected_user)}
                id="manage-user-role-form"
                phx-change="update-user-role"
                class="max-w-[14rem]"
              >
                <input type="hidden" name="user_role[user_id]" value={@selected_user.id} />
                <.input
                  id={"manage-user-role-select-#{@selected_user.id}"}
                  field={user_role_form(@selected_user)[:role]}
                  type="select"
                  options={[{"Member", "member"}, {"Admin", "admin"}]}
                  disabled={@selected_user.id == @current_scope.user.id}
                />
              </.form>
            </section>

            <section :if={is_nil(@selected_user.confirmed_at)} class="space-y-3">
              <div>
                <h3 class="text-base font-semibold text-zinc-950">Invitation</h3>
                <p class="mt-1 text-sm text-zinc-500">
                  Pending users can receive a fresh invitation email with a new token.
                </p>
              </div>

              <div class="flex flex-wrap gap-3">
                <.button
                  id={"resend-user-invitation-#{@selected_user.id}"}
                  type="button"
                  variant="secondary"
                  phx-click="resend-user-invitation"
                  phx-value-id={@selected_user.id}
                >
                  Resend invitation
                </.button>
              </div>
            </section>

            <section class="space-y-3">
              <div>
                <h3 class="text-base font-semibold text-zinc-950">Team memberships</h3>
                <p class="mt-1 text-sm text-zinc-500">
                  Add this user to teams, adjust their team role, or remove access.
                </p>
              </div>

              <%= if @selected_user.team_members == [] do %>
                <div class="border border-dashed border-zinc-300 px-4 py-6 text-sm text-zinc-500">
                  This user is not assigned to any team yet.
                </div>
              <% else %>
                <div class="space-y-3">
                  <div
                    :for={team_member <- @selected_user.team_members}
                    class="flex flex-col gap-4 border border-zinc-200 px-4 py-4 lg:flex-row lg:items-center lg:justify-between"
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
                          options={[{"Member", "member"}, {"Admin", "admin"}]}
                          class="max-w-[9rem]"
                        />
                      </.form>

                      <.action_button
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
              <div>
                <h3 class="text-base font-semibold text-zinc-950">Add to team</h3>
                <p class="mt-1 text-sm text-zinc-500">
                  Assign this user to another team without leaving the users tab.
                </p>
              </div>

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
                  options={[{"Member", "member"}, {"Admin", "admin"}]}
                />
                <div class="flex items-end">
                  <.button variant="secondary">Add membership</.button>
                </div>
              </.form>
            </section>

            <section
              :if={@selected_user.id != @current_scope.user.id}
              class="space-y-3 border-t border-zinc-200 pt-6"
            >
              <div>
                <h3 class="text-base font-semibold text-zinc-950">Danger zone</h3>
                <p class="mt-1 text-sm text-zinc-500">
                  Delete this user and remove their invitations, sessions, and team memberships.
                </p>
              </div>

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
          <.button type="button" variant="ghost" phx-click="close-modal" phx-value-modal="user">
            Close
          </.button>
        </:actions>
      </.modal>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    if user.role != :admin do
      {:ok, push_navigate(socket, to: ArgusWeb.UserAuth.signed_in_path(user))}
    else
      {:ok,
       socket
       |> assign(:sidebar, AppShell.build(user))
       |> assign(:invite_modal_open, false)
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
  def handle_event("open-modal", %{"modal" => "invite"}, socket) do
    {:noreply, assign(socket, :invite_modal_open, true)}
  end

  def handle_event("open-modal", %{"modal" => "team"}, socket) do
    {:noreply, assign(socket, :team_modal_open, true)}
  end

  def handle_event("open-modal", %{"modal" => "user", "id" => user_id}, socket) do
    {:noreply,
     socket
     |> assign(:selected_user_id, String.to_integer(user_id))
     |> assign(:user_modal_open, true)
     |> load_data()}
  end

  def handle_event("close-modal", %{"modal" => "invite"}, socket) do
    {:noreply, assign(socket, :invite_modal_open, false)}
  end

  def handle_event("close-modal", %{"modal" => "team"}, socket) do
    {:noreply, assign(socket, :team_modal_open, false)}
  end

  def handle_event("close-modal", %{"modal" => "user"}, socket) do
    {:noreply, assign(socket, :user_modal_open, false)}
  end

  def handle_event("invite-user", %{"user" => params}, socket) do
    inviter = socket.assigns.current_scope.user

    case Accounts.deliver_user_invitation(inviter, params, fn token ->
           url(~p"/invitations/#{token}")
         end) do
      {:ok, _invitation} ->
        {:noreply,
         socket
         |> assign(:invite_modal_open, false)
         |> assign_forms()
         |> load_data()
         |> put_flash(:info, "Invitation sent.")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:invite_modal_open, true)
         |> assign(:invitation_form, to_form(changeset, as: :user))}
    end
  end

  def handle_event("resend-user-invitation", %{"id" => user_id}, socket) do
    inviter = socket.assigns.current_scope.user

    case Enum.find(socket.assigns.users, &(&1.id == String.to_integer(user_id))) do
      nil ->
        {:noreply, put_flash(socket, :error, "User not found.")}

      user ->
        case Accounts.resend_user_invitation(inviter, user, fn token ->
               url(~p"/invitations/#{token}")
             end) do
          {:ok, _invitation} ->
            {:noreply, socket |> load_data() |> put_flash(:info, "Invitation resent.")}

          {:error, :already_active} ->
            {:noreply, put_flash(socket, :error, "Only pending users can be reinvited.")}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Could not resend the invitation.")}
        end
    end
  end

  def handle_event("send-test-webhook", _params, socket) do
    case IssueNotifier.send_test_webhook() do
      :ok ->
        {:noreply, put_flash(socket, :info, "Test webhook sent.")}

      {:error, :not_configured} ->
        {:noreply, put_flash(socket, :error, "No issue webhook URL is configured.")}

      {:error, {:unexpected_status, status}} ->
        {:noreply,
         put_flash(socket, :error, "Webhook test returned an unexpected status: #{status}.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not send the test webhook.")}
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

  def handle_event(
        "update-user-role",
        %{"user_role" => %{"user_id" => user_id, "role" => role}},
        socket
      ) do
    user_id = String.to_integer(user_id)

    cond do
      user_id == socket.assigns.current_scope.user.id ->
        {:noreply, put_flash(socket, :error, "You cannot change your own global role here.")}

      user = Enum.find(socket.assigns.users, &(&1.id == user_id)) ->
        {:ok, _user} = Accounts.update_user_role(user, String.to_existing_atom(role))
        {:noreply, socket |> load_data() |> put_flash(:info, "User role updated.")}

      true ->
        {:noreply, put_flash(socket, :error, "User not found.")}
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
         %{} = team <- Teams.get_team!(String.to_integer(team_id)),
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

  defp assign_forms(socket) do
    invitation_form =
      %User{}
      |> User.invited_user_changeset(%{"role" => "member"}, validate_unique: false)
      |> to_form(as: :user)

    team_form = to_form(Team.changeset(%Team{}, %{}), as: :team)

    socket
    |> assign(:invitation_form, invitation_form)
    |> assign(:team_form, team_form)
  end

  defp load_data(socket) do
    user = socket.assigns.current_scope.user
    projects = Projects.list_all_projects_for_user(user)
    users = Accounts.list_users()
    teams = Teams.list_teams()
    selected_user = selected_user(users, socket.assigns[:selected_user_id])

    socket
    |> assign(:tab, socket.assigns[:tab] || "users")
    |> assign(:webhook_url, IssueNotifier.configured_webhook_url())
    |> assign(:users, users)
    |> assign(:teams, teams)
    |> assign(:selected_user, selected_user)
    |> assign(:user_team_form, user_team_form(selected_user, teams))
    |> assign(:projects, projects)
    |> assign(:project_stats, Projects.project_stats(projects))
    |> assign(
      :team_project_counts,
      Enum.frequencies_by(projects, & &1.team_id)
    )
  end

  defp latest_inviter_name(user) do
    user.received_invitations
    |> List.first()
    |> case do
      nil -> "-"
      invitation -> (invitation.invited_by && invitation.invited_by.name) || "-"
    end
  end

  defp normalize_tab(tab) when tab in ~w(users teams projects), do: tab
  defp normalize_tab(_), do: "users"

  defp user_role_form(user) do
    to_form(%{"user_id" => user.id, "role" => to_string(user.role)}, as: :user_role)
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

  defp tab_class(true),
    do: "border-b-2 border-zinc-950 px-0 pb-3 text-sm font-medium text-zinc-950"

  defp tab_class(false),
    do:
      "border-b-2 border-transparent px-0 pb-3 text-sm text-zinc-500 transition hover:border-zinc-300 hover:text-zinc-900"
end
