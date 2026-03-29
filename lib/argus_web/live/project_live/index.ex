defmodule ArgusWeb.ProjectLive.Index do
  use ArgusWeb, :live_view

  alias Argus.Projects
  alias Argus.Teams
  alias ArgusWeb.AppShell

  @empty_stats %{issue_count: 0, unresolved_count: 0, log_count: 0, last_issue: nil}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} sidebar={@sidebar}>
      <.header>
        {if @active_team, do: @active_team.name, else: "Workspace"}
        <:subtitle>
          Project health, unresolved issues, and recent regressions.
        </:subtitle>
        <:actions>
          <.button
            :if={@active_team && @can_manage_team?}
            navigate={~p"/teams/#{@active_team.id}/settings"}
            variant="secondary"
          >
            Manage team
          </.button>
        </:actions>
      </.header>

      <%= cond do %>
        <% @teams == [] and @current_scope.user.role == :admin -> %>
          <.empty_state
            title="No teams yet"
            description="Create a team to start organizing projects, issues, and logs."
            icon="hero-building-office-2"
          >
            <:action>
              <.button navigate={~p"/admin"}>Open admin panel</.button>
            </:action>
          </.empty_state>
        <% @teams == [] -> %>
          <.empty_state
            title="No teams assigned"
            description="Ask a global admin to add you to a team."
            icon="hero-user-group"
          />
        <% @projects == [] and @active_team && @can_manage_team? -> %>
          <.empty_state
            title="No projects yet"
            description={"#{@active_team.name} does not have any projects yet."}
            icon="hero-command-line"
          >
            <:action>
              <.button navigate={~p"/teams/#{@active_team.id}/settings"}>Create project</.button>
            </:action>
          </.empty_state>
        <% @projects == [] -> %>
          <.empty_state
            title="No projects yet"
            description="A team admin needs to create the first project for this team."
            icon="hero-command-line"
          />
        <% true -> %>
          <div class="space-y-6">
            <section class="grid gap-4 xl:grid-cols-5">
              <div class="border border-zinc-200 bg-white p-5">
                <p class="text-[11px] font-semibold uppercase tracking-[0.18em] text-zinc-500">
                  Projects
                </p>
                <p class="mt-3 text-3xl font-semibold tracking-tight text-zinc-950">
                  {@summary.project_count}
                </p>
              </div>
              <div class="border border-zinc-200 border-l-4 border-l-sky-500 bg-white p-5 xl:col-span-2">
                <p class="text-[11px] font-semibold uppercase tracking-[0.18em] text-sky-700">
                  Unresolved issues
                </p>
                <p class="mt-3 text-4xl font-semibold tracking-tight text-zinc-950">
                  {@summary.unresolved_count}
                </p>
              </div>
              <div class="border border-zinc-200 bg-white p-5">
                <p class="text-[11px] font-semibold uppercase tracking-[0.18em] text-zinc-500">
                  Grouped issues
                </p>
                <p class="mt-3 text-3xl font-semibold tracking-tight text-zinc-950">
                  {@summary.issue_count}
                </p>
              </div>
              <div class="border border-zinc-200 bg-white p-5">
                <p class="text-[11px] font-semibold uppercase tracking-[0.18em] text-zinc-500">
                  Latest issue
                </p>
                <div class="mt-3">
                  <%= if @summary.latest_issue_at do %>
                    <.relative_time
                      at={@summary.latest_issue_at}
                      class="text-base font-medium text-zinc-950"
                    />
                  <% else %>
                    <p class="text-base font-medium text-zinc-950">No issues yet</p>
                  <% end %>
                </div>
              </div>
            </section>

            <div class="grid gap-6 xl:grid-cols-[1.3fr_0.7fr]">
              <section class="border border-zinc-200 bg-white p-6">
                <div class="flex items-end justify-between gap-4">
                  <div>
                    <h2 class="text-lg font-semibold tracking-tight text-zinc-950">Projects</h2>
                    <p class="mt-1 text-sm text-zinc-500">
                      Open issues, inspect logs, or edit project settings.
                    </p>
                  </div>
                </div>

                <div class="mt-6 grid gap-4 xl:grid-cols-2">
                  <article
                    :for={project <- @projects}
                    id={"project-card-#{project.id}"}
                    class="border border-zinc-200 bg-slate-50 p-5 transition hover:border-sky-200 hover:bg-white"
                  >
                    <div class="flex items-start justify-between gap-4">
                      <div class="min-w-0">
                        <p class="text-base font-semibold text-zinc-950">{project.name}</p>
                        <p class="mt-1 font-mono text-xs text-zinc-500">{project.slug}</p>
                      </div>
                      <.badge kind={
                        if project_stat(@project_stats, project.id, :unresolved_count) > 0,
                          do: :error,
                          else: :resolved
                      }>
                        {project_stat(@project_stats, project.id, :unresolved_count)} unresolved
                      </.badge>
                    </div>

                    <div class="mt-5 grid grid-cols-3 gap-3 border-t border-zinc-200 pt-4">
                      <div>
                        <p class="text-[11px] font-semibold uppercase tracking-[0.16em] text-zinc-500">
                          Issues
                        </p>
                        <p class="mt-2 text-lg font-semibold text-zinc-950">
                          {project_stat(@project_stats, project.id, :issue_count)}
                        </p>
                      </div>
                      <div>
                        <p class="text-[11px] font-semibold uppercase tracking-[0.16em] text-zinc-500">
                          Logs
                        </p>
                        <p class="mt-2 text-lg font-semibold text-zinc-950">
                          {project_stat(@project_stats, project.id, :log_count)}
                        </p>
                      </div>
                      <div>
                        <p class="text-[11px] font-semibold uppercase tracking-[0.16em] text-zinc-500">
                          Last issue
                        </p>
                        <div class="mt-2">
                          <%= if last_issue = last_issue(@project_stats, project.id) do %>
                            <.relative_time
                              at={last_issue.last_seen_at}
                              format="compact"
                              class="text-sm font-medium text-zinc-950"
                            />
                          <% else %>
                            <p class="text-sm font-medium text-zinc-950">Never</p>
                          <% end %>
                        </div>
                      </div>
                    </div>

                    <div class="mt-5 border-t border-zinc-200 pt-4">
                      <%= if last_issue = last_issue(@project_stats, project.id) do %>
                        <p class="text-sm font-medium text-zinc-950">{last_issue.title}</p>
                        <p class="mt-1 font-mono text-xs text-zinc-500">
                          {last_issue.culprit || "No culprit captured"}
                        </p>
                      <% else %>
                        <p class="text-sm text-zinc-500">
                          No issues captured yet. This project is ready to ingest events.
                        </p>
                      <% end %>
                    </div>

                    <div class="mt-5 flex flex-wrap gap-2">
                      <.button navigate={~p"/projects/#{project.slug}/issues"}>Issues</.button>
                      <.button navigate={~p"/projects/#{project.slug}/logs"} variant="secondary">
                        Logs
                      </.button>
                      <.button
                        :if={@can_manage_team?}
                        navigate={~p"/projects/#{project.slug}/settings"}
                        variant="ghost"
                      >
                        Settings
                      </.button>
                    </div>
                  </article>
                </div>
              </section>

              <section class="border border-zinc-200 bg-white p-6">
                <div>
                  <h2 class="text-lg font-semibold tracking-tight text-zinc-950">Recent issues</h2>
                  <p class="mt-1 text-sm text-zinc-500">
                    The latest grouped issues across this team's projects.
                  </p>
                </div>

                <div class="mt-6 space-y-3">
                  <%= if @recent_issues == [] do %>
                    <.empty_state
                      title="No recent issues"
                      description="This team has not captured any grouped issues yet."
                      icon="hero-bug-ant"
                    />
                  <% end %>

                  <.link
                    :for={issue <- @recent_issues}
                    navigate={~p"/projects/#{issue.project.slug}/issues/#{issue.id}"}
                    class="block border border-zinc-200 bg-slate-50 px-4 py-4 transition hover:border-sky-200 hover:bg-white"
                  >
                    <div class="flex items-start justify-between gap-4">
                      <div class="min-w-0">
                        <p class="text-sm font-medium text-zinc-950">{issue.title}</p>
                        <p class="mt-1 font-mono text-xs text-zinc-500">
                          {issue.project.name} / {issue.culprit || "No culprit captured"}
                        </p>
                      </div>
                      <.badge kind={issue.level}>{issue.level}</.badge>
                    </div>
                    <div class="mt-3 flex items-center justify-between gap-3">
                      <.badge kind={issue.status}>{issue.status}</.badge>
                      <.relative_time at={issue.last_seen_at} />
                    </div>
                  </.link>
                </div>
              </section>
            </div>
          </div>
      <% end %>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    {:ok,
     socket
     |> assign(:teams, [])
     |> assign(:team, nil)
     |> assign(:active_team, nil)
     |> assign(:projects, [])
     |> assign(:project_stats, %{})
     |> assign(:recent_issues, [])
     |> assign(:summary, %{
       project_count: 0,
       unresolved_count: 0,
       issue_count: 0,
       latest_issue_at: nil
     })
     |> assign(:can_manage_team?, false)
     |> assign(:sidebar, AppShell.build(user))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    user = socket.assigns.current_scope.user
    teams = Teams.list_teams_for_user(user)
    active_team = choose_team(user, teams, params["team_id"])
    projects = if active_team, do: Projects.list_projects_for_team(user, active_team), else: []
    project_stats = Projects.project_stats(projects)
    recent_issues = Projects.recent_error_events_for_projects(projects)

    {:noreply,
     socket
     |> assign(:teams, teams)
     |> assign(:team, active_team)
     |> assign(:active_team, active_team)
     |> assign(:projects, projects)
     |> assign(:project_stats, project_stats)
     |> assign(:recent_issues, recent_issues)
     |> assign(:summary, build_summary(projects, project_stats, recent_issues))
     |> assign(
       :can_manage_team?,
       active_team && (user.role == :admin || Teams.team_admin?(user, active_team))
     )
     |> assign(:sidebar, AppShell.build(user, team: active_team))}
  end

  defp build_summary(projects, project_stats, recent_issues) do
    Enum.reduce(
      projects,
      %{
        project_count: length(projects),
        unresolved_count: 0,
        issue_count: 0,
        latest_issue_at: nil
      },
      fn project, acc ->
        stats = Map.get(project_stats, project.id, @empty_stats)

        %{
          project_count: acc.project_count,
          unresolved_count: acc.unresolved_count + stats.unresolved_count,
          issue_count: acc.issue_count + stats.issue_count,
          latest_issue_at: acc.latest_issue_at
        }
      end
    )
    |> Map.put(:latest_issue_at, recent_issues |> List.first() |> then(&(&1 && &1.last_seen_at)))
  end

  defp choose_team(_user, teams, nil), do: List.first(teams)

  defp choose_team(user, teams, team_id),
    do: Teams.get_team_for_user(user, team_id) || List.first(teams)

  defp project_stat(project_stats, project_id, key) do
    project_stats
    |> Map.get(project_id, @empty_stats)
    |> Map.get(key, 0)
  end

  defp last_issue(project_stats, project_id) do
    project_stats
    |> Map.get(project_id, @empty_stats)
    |> Map.get(:last_issue)
  end
end
