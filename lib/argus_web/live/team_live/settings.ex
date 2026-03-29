defmodule ArgusWeb.TeamLive.Settings do
  use ArgusWeb, :live_view

  alias Argus.Accounts
  alias Argus.Projects
  alias Argus.Teams
  alias ArgusWeb.AppShell

  @empty_project_stats %{issue_count: 0, unresolved_count: 0, log_count: 0, last_issue: nil}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} sidebar={@sidebar}>
      <.header>
        {@team.name}
        <:subtitle>Manage members and projects for this team.</:subtitle>
        <:actions>
          <.button
            :if={@tab == "projects"}
            id="open-project-modal"
            type="button"
            phx-click="open-project-modal"
          >
            Create project
          </.button>
        </:actions>
      </.header>

      <section class="border border-zinc-200 bg-white">
        <div class="flex flex-wrap items-center gap-5 border-b border-zinc-200 px-6 pt-4">
          <.link
            patch={~p"/teams/#{@team.id}/settings?tab=projects"}
            class={tab_class(@tab == "projects")}
          >
            Projects
          </.link>
          <.link patch={~p"/teams/#{@team.id}/settings?tab=users"} class={tab_class(@tab == "users")}>
            Users
          </.link>
        </div>

        <div class="p-6">
          <%= if @tab == "projects" do %>
            <div class="space-y-4">
              <div>
                <h2 class="text-lg font-semibold tracking-tight text-zinc-950">Projects</h2>
                <p class="mt-1 text-sm text-zinc-500">
                  Open issues, logs, or project settings.
                </p>
              </div>

              <%= if @projects == [] do %>
                <.empty_state
                  title="No projects yet"
                  description="Create the first project for this team to start receiving issues and logs."
                  icon="hero-command-line"
                />
              <% else %>
                <.table id="team-projects" rows={@projects}>
                  <:col :let={project} label="Project">
                    <div class="space-y-1">
                      <p class="font-medium text-zinc-950">{project.name}</p>
                      <p class="font-mono text-xs text-zinc-500">{project.slug}</p>
                    </div>
                  </:col>
                  <:col :let={project} label="Issues">
                    {project_stat(@project_stats, project.id, :issue_count)}
                  </:col>
                  <:col :let={project} label="Logs">
                    {project_stat(@project_stats, project.id, :log_count)}
                  </:col>
                  <:col :let={project} label="Credentials">
                    <.copy_to_clipboard
                      value={Projects.issue_dsn(project)}
                      label={truncate_dsn(Projects.issue_dsn(project))}
                      toast_message={"#{project.name} DSN copied"}
                      compact
                    />
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
                      <.overflow_menu id={"team-project-actions-#{project.id}"}>
                        <:item navigate={~p"/projects/#{project.slug}/settings"}>
                          Project settings
                        </:item>
                      </.overflow_menu>
                    </div>
                  </:col>
                </.table>
              <% end %>
            </div>
          <% end %>

          <%= if @tab == "users" do %>
            <div class="space-y-6">
              <div>
                <h2 class="text-lg font-semibold tracking-tight text-zinc-950">Users</h2>
                <p class="mt-1 text-sm text-zinc-500">
                  Adjust team roles and add existing workspace users to this team.
                </p>
              </div>

              <.table id="team-members" rows={@members}>
                <:col :let={member} label="Name">
                  <div class="space-y-1">
                    <p class="font-medium text-zinc-950">{member.user.name}</p>
                    <p class="text-sm text-zinc-500">{member.user.email}</p>
                  </div>
                </:col>
                <:col :let={member} label="Role">
                  <.form
                    for={member_role_form(member)}
                    id={"team-member-role-#{member.id}"}
                    phx-change="update-role"
                  >
                    <input type="hidden" name="team_member[member_id]" value={member.id} />
                    <.input
                      id={"team-member-role-select-#{member.id}"}
                      field={member_role_form(member)[:role]}
                      type="select"
                      options={[{"Member", "member"}, {"Admin", "admin"}]}
                      class="max-w-[9rem]"
                    />
                  </.form>
                </:col>
                <:col :let={member} label="Actions" class="whitespace-nowrap">
                  <.action_button
                    phx-click="remove-member"
                    phx-value-id={member.user_id}
                    icon="hero-user-minus-mini"
                    class="hover:border-red-200 hover:bg-red-50 hover:text-red-700"
                  >
                    Remove
                  </.action_button>
                </:col>
              </.table>

              <section class="border border-zinc-200 bg-slate-50 p-5">
                <div class="space-y-1">
                  <h3 class="text-base font-semibold tracking-tight text-zinc-950">
                    Add existing user
                  </h3>
                  <p class="text-sm text-zinc-500">
                    Users must already exist in Argus before they can be added to a team.
                  </p>
                </div>

                <.form
                  for={@member_form}
                  id="member-form"
                  phx-submit="add-member"
                  class="mt-5 space-y-5"
                >
                  <.input field={@member_form[:email]} type="email" label="User email" required />
                  <.input
                    field={@member_form[:role]}
                    type="select"
                    label="Role"
                    options={[{"Member", "member"}, {"Admin", "admin"}]}
                  />

                  <div class="flex justify-end">
                    <.button variant="secondary">Add member</.button>
                  </div>
                </.form>
              </section>
            </div>
          <% end %>
        </div>
      </section>

      <.modal id="project-modal" open={@project_modal_open} title="Create project">
        <.form for={@project_form} id="project-form" phx-submit="create-project" class="space-y-5">
          <.input
            id="create-project-name"
            field={@project_form[:name]}
            type="text"
            label="Project name"
            required
          />

          <div class="flex justify-end gap-3">
            <.button type="button" variant="ghost" phx-click="close-project-modal">Cancel</.button>
            <.button>Create project</.button>
          </div>
        </.form>
      </.modal>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_scope.user

    case Teams.get_team_for_user(user, id) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/projects")}

      team ->
        if user.role == :admin || Teams.team_admin?(user, team) do
          {:ok,
           socket
           |> assign(:team, team)
           |> assign(:project_modal_open, false)
           |> load_data()}
        else
          {:ok, push_navigate(socket, to: ArgusWeb.UserAuth.signed_in_path(user))}
        end
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :tab, normalize_tab(params["tab"]))}
  end

  @impl true
  def handle_event("open-project-modal", _params, socket) do
    {:noreply, assign(socket, :project_modal_open, true)}
  end

  def handle_event("close-project-modal", _params, socket) do
    {:noreply, assign(socket, :project_modal_open, false)}
  end

  def handle_event("create-project", %{"project" => params}, socket) do
    case Projects.create_project(socket.assigns.team, params) do
      {:ok, project} ->
        {:noreply,
         socket
         |> assign(:project_modal_open, false)
         |> assign_forms()
         |> load_data()
         |> put_flash(:info, "Project created.")
         |> push_navigate(to: ~p"/projects/#{project.slug}/settings")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:project_modal_open, true)
         |> assign(:project_form, to_form(changeset, as: :project))}
    end
  end

  def handle_event("add-member", %{"member" => %{"email" => email, "role" => role}}, socket) do
    case Accounts.get_user_by_email(email) do
      nil ->
        {:noreply, put_flash(socket, :error, "No user exists with that email.")}

      user ->
        {:ok, _member} =
          Teams.add_member(socket.assigns.team, user, String.to_existing_atom(role))

        {:noreply,
         socket
         |> load_data()
         |> put_flash(:info, "Member added.")}
    end
  end

  def handle_event(
        "update-role",
        %{"team_member" => %{"member_id" => member_id, "role" => role}},
        socket
      ) do
    member =
      Enum.find(socket.assigns.members, fn team_member ->
        team_member.id == String.to_integer(member_id)
      end)

    {:ok, _member} = Teams.update_member_role(member, String.to_existing_atom(role))

    {:noreply, socket |> load_data() |> put_flash(:info, "Role updated.")}
  end

  def handle_event("remove-member", %{"id" => user_id}, socket) do
    Teams.remove_member(socket.assigns.team, String.to_integer(user_id))

    {:noreply, socket |> load_data() |> put_flash(:info, "Member removed.")}
  end

  defp load_data(socket) do
    user = socket.assigns.current_scope.user
    team = socket.assigns.team
    projects = Projects.list_projects_for_team(user, team)

    socket
    |> assign(:tab, socket.assigns[:tab] || "projects")
    |> assign(:projects, projects)
    |> assign(:project_stats, Projects.project_stats(projects))
    |> assign(:members, Teams.list_members(team))
    |> assign(:sidebar, AppShell.build(user, team: team))
    |> assign_forms()
  end

  defp assign_forms(socket) do
    socket
    |> assign(:project_form, to_form(%{"name" => ""}, as: :project))
    |> assign(:member_form, to_form(%{"email" => "", "role" => "member"}, as: :member))
  end

  defp normalize_tab(tab) when tab in ~w(projects users), do: tab
  defp normalize_tab(_), do: "projects"

  defp project_stat(project_stats, project_id, key) do
    project_stats
    |> Map.get(project_id, @empty_project_stats)
    |> Map.get(key, 0)
  end

  defp truncate_dsn(dsn) do
    if String.length(dsn) > 42 do
      String.slice(dsn, 0, 42) <> "…"
    else
      dsn
    end
  end

  defp tab_class(true),
    do: "border-b-2 border-zinc-950 px-0 pb-3 text-sm font-medium text-zinc-950"

  defp tab_class(false),
    do:
      "border-b-2 border-transparent px-0 pb-3 text-sm text-zinc-500 transition hover:border-zinc-300 hover:text-zinc-900"

  defp member_role_form(member) do
    to_form(%{"member_id" => member.id, "role" => to_string(member.role)}, as: :team_member)
  end
end
