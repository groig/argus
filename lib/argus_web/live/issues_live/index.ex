defmodule ArgusWeb.IssuesLive.Index do
  use ArgusWeb, :live_view

  alias Argus.Projects
  alias Argus.Teams
  alias ArgusWeb.AppShell

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} sidebar={@sidebar}>
      <.header>
        {@project.name}
        <:subtitle>Grouped issues for {@project.team.name}. New events stream in live.</:subtitle>
        <:actions>
          <.button navigate={~p"/projects/#{@project.slug}/logs"} variant="secondary">Logs</.button>
          <.button
            :if={@can_manage_project?}
            navigate={~p"/projects/#{@project.slug}/settings"}
            variant="ghost"
          >
            Settings
          </.button>
        </:actions>
      </.header>

      <section class="overflow-hidden border border-zinc-200 bg-white">
        <div class="border-b border-zinc-200 bg-slate-50 px-6 py-5">
          <div class="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
            <.form
              for={@filter_form}
              id="issue-filters"
              phx-change="filter"
              class="grid gap-4 sm:grid-cols-3 lg:w-3/4"
            >
              <.input
                field={@filter_form[:search]}
                type="search"
                label="Search title"
                placeholder="Search issues"
              />
              <.input
                field={@filter_form[:level]}
                type="select"
                label="Level"
                options={[
                  {"All levels", "all"},
                  {"Error", "error"},
                  {"Warning", "warning"},
                  {"Info", "info"}
                ]}
              />
              <.input
                field={@filter_form[:status]}
                type="select"
                label="Status"
                options={[
                  {"All statuses", "all"},
                  {"Unresolved", "unresolved"},
                  {"Resolved", "resolved"},
                  {"Ignored", "ignored"}
                ]}
              />
            </.form>

            <div class="flex flex-wrap items-center gap-3">
              <.button
                variant="secondary"
                size="sm"
                phx-click="bulk-status"
                phx-value-status="resolved"
                disabled={MapSet.size(@selected_ids) == 0}
              >
                Resolve selected
              </.button>
              <.button
                variant="secondary"
                size="sm"
                phx-click="bulk-status"
                phx-value-status="ignored"
                disabled={MapSet.size(@selected_ids) == 0}
              >
                Ignore selected
              </.button>
            </div>
          </div>
        </div>

        <div class="overflow-hidden bg-white">
          <table class="min-w-full divide-y divide-zinc-200 text-sm">
            <thead class="bg-slate-50 text-left text-[11px] font-semibold uppercase tracking-[0.16em] text-zinc-500">
              <tr>
                <th class="w-12 px-4 py-3.5"></th>
                <th class="px-4 py-3.5">Issue</th>
                <th class="px-4 py-3.5">Assignee</th>
                <th class="px-4 py-3.5">Level</th>
                <th class="px-4 py-3.5">Count</th>
                <th class="px-4 py-3.5">Last seen</th>
              </tr>
            </thead>
            <tbody id="issues" phx-update="stream" class="divide-y divide-zinc-100 bg-white">
              <tr :if={@issue_count == 0}>
                <td colspan="6" class="px-6 py-16">
                  <.empty_state
                    title="No issues match these filters"
                    description="Try broadening the search or waiting for a new event."
                    icon="hero-funnel"
                  />
                </td>
              </tr>
              <tr
                :for={{dom_id, issue} <- @streams.issues}
                id={dom_id}
                class="align-top transition hover:bg-slate-50"
              >
                <td class="px-4 py-4">
                  <input
                    type="checkbox"
                    checked={MapSet.member?(@selected_ids, issue.id)}
                    phx-click="toggle-select"
                    phx-value-id={issue.id}
                    class="h-4 w-4 rounded-sm border-zinc-300 text-sky-600 focus:ring-sky-500"
                  />
                </td>
                <td class="px-4 py-4">
                  <.link
                    navigate={~p"/projects/#{@project.slug}/issues/#{issue.id}"}
                    class="block space-y-1"
                  >
                    <p class="font-semibold text-zinc-950">{issue.title}</p>
                    <p class="font-mono text-xs text-zinc-500">
                      {issue.culprit || "No culprit captured"}
                    </p>
                  </.link>
                </td>
                <td class="px-4 py-4">
                  <%= if issue.assignee do %>
                    <div class="space-y-1">
                      <p class="text-sm font-medium text-zinc-950">{issue.assignee.name}</p>
                      <p class="text-xs text-zinc-500">{issue.assignee.email}</p>
                    </div>
                  <% else %>
                    <span class="text-sm text-zinc-400">Unassigned</span>
                  <% end %>
                </td>
                <td class="px-4 py-4">
                  <.badge kind={issue.level}>{issue.level}</.badge>
                </td>
                <td class="px-4 py-4 font-medium text-zinc-700">{issue.occurrence_count}</td>
                <td class="px-4 py-4"><.relative_time at={issue.last_seen_at} /></td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"slug" => slug} = params, _session, socket) do
    user = socket.assigns.current_scope.user

    case Projects.get_project_for_user_by_slug(user, slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/projects")}

      project ->
        if connected?(socket), do: Projects.subscribe_to_issues(project)

        filters = normalize_filters(params)
        issues = Projects.list_error_events(project, filters)

        {:ok,
         socket
         |> assign(:project, project)
         |> assign(
           :can_manage_project?,
           user.role == :admin || Teams.team_admin?(user, project.team)
         )
         |> assign(:sidebar, AppShell.build(user, project: project))
         |> assign(:filter_form, to_form(filters, as: :filters))
         |> assign(:selected_ids, MapSet.new())
         |> assign(:issue_count, length(issues))
         |> stream(:issues, issues)}
    end
  end

  @impl true
  def handle_event("filter", %{"filters" => filters}, socket) do
    issues = Projects.list_error_events(socket.assigns.project, filters)

    {:noreply,
     socket
     |> assign(:filter_form, to_form(filters, as: :filters))
     |> assign(:selected_ids, MapSet.new())
     |> assign(:issue_count, length(issues))
     |> stream(:issues, issues, reset: true)}
  end

  def handle_event("toggle-select", %{"id" => id}, socket) do
    selected_ids =
      socket.assigns.selected_ids
      |> toggle_integer(id)

    {:noreply, assign(socket, :selected_ids, selected_ids)}
  end

  def handle_event("bulk-status", %{"status" => status}, socket) do
    Projects.bulk_update_error_event_status(
      socket.assigns.project,
      MapSet.to_list(socket.assigns.selected_ids),
      String.to_existing_atom(status)
    )

    {:noreply, socket |> assign(:selected_ids, MapSet.new()) |> reload_issues()}
  end

  @impl true
  def handle_info({:error_event_updated, _error_event}, socket) do
    {:noreply, reload_issues(socket)}
  end

  defp reload_issues(socket) do
    filters = socket.assigns.filter_form.params || normalize_filters(%{})
    issues = Projects.list_error_events(socket.assigns.project, filters)

    socket
    |> assign(:issue_count, length(issues))
    |> stream(:issues, issues, reset: true)
  end

  defp normalize_filters(params) do
    %{
      "search" => Map.get(params, "search", ""),
      "level" => Map.get(params, "level", "all"),
      "status" => Map.get(params, "status", "all")
    }
  end

  defp toggle_integer(set, id) do
    id = String.to_integer(id)
    if MapSet.member?(set, id), do: MapSet.delete(set, id), else: MapSet.put(set, id)
  end
end
