defmodule ArgusWeb.LogsLive.Index do
  use ArgusWeb, :live_view

  alias Argus.Logs
  alias Argus.Projects
  alias Argus.Teams
  alias ArgusWeb.AppShell

  @page_size 50

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} sidebar={@sidebar}>
      <.header>
        {@project.name} logs
        <:subtitle>
          Newest first, with a live tail and drill-down into individual log payloads.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/projects/#{@project.slug}/issues"} variant="secondary">
            Issues
          </.button>
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
              id="log-filters"
              phx-change="filter"
              class="grid gap-4 sm:grid-cols-2 lg:w-2/3"
            >
              <.input
                field={@filter_form[:search]}
                type="search"
                label="Search message"
                placeholder="Search logs"
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
            </.form>

            <button
              id="toggle-tail"
              type="button"
              phx-click="toggle-tail"
              class={[
                "inline-flex items-center gap-3 border px-3 py-2 text-sm font-medium transition",
                @tail_mode &&
                  "border-sky-200 bg-sky-50 text-sky-700",
                !@tail_mode &&
                  "border-zinc-200 bg-white text-zinc-600 hover:border-sky-200 hover:text-sky-700"
              ]}
            >
              <span class={[
                "relative flex h-5 w-9 items-center border transition",
                @tail_mode && "border-sky-500 bg-sky-500",
                !@tail_mode && "border-zinc-300 bg-zinc-200"
              ]}>
                <span class={[
                  "absolute h-3.5 w-3.5 bg-white transition",
                  @tail_mode && "translate-x-4",
                  !@tail_mode && "translate-x-0.5"
                ]} />
              </span>
              <span class="inline-flex items-center gap-2">
                <span class={[
                  "size-2 rounded-full",
                  @tail_mode && "bg-sky-500",
                  !@tail_mode && "bg-zinc-300"
                ]} /> Tail mode
              </span>
            </button>
          </div>
        </div>

        <div class="overflow-hidden bg-white">
          <table class="min-w-full divide-y divide-zinc-200 text-sm">
            <thead class="bg-slate-50 text-left text-[11px] font-semibold uppercase tracking-[0.16em] text-zinc-500">
              <tr>
                <th class="px-4 py-3.5">Timestamp</th>
                <th class="px-4 py-3.5">Level</th>
                <th class="px-4 py-3.5">Message</th>
                <th class="px-4 py-3.5">Metadata</th>
                <th class="px-4 py-3.5">Actions</th>
              </tr>
            </thead>
            <tbody id="logs" phx-update="stream" class="divide-y divide-zinc-100 bg-white">
              <tr :if={@log_count == 0}>
                <td colspan="5" class="px-6 py-16">
                  <.empty_state
                    title="No logs yet"
                    description="Send an envelope log item or broaden the filters."
                    icon="hero-document-text"
                  />
                </td>
              </tr>
              <tr
                :for={{dom_id, log_event} <- @streams.logs}
                id={dom_id}
                class="align-top transition hover:bg-slate-50"
              >
                <td class="px-4 py-4"><.relative_time at={log_event.timestamp} /></td>
                <td class="px-4 py-4">
                  <.badge kind={log_event.level}>{log_event.level}</.badge>
                </td>
                <td class="px-4 py-4">
                  <.link
                    navigate={~p"/projects/#{@project.slug}/logs/#{log_event.id}"}
                    class="block w-full text-left"
                  >
                    <p class="font-semibold text-zinc-950">{log_event.message}</p>
                    <p class="mt-1 font-mono text-xs text-zinc-500">
                      {log_event.logger_name || log_event.origin || "metadata available"}
                    </p>
                  </.link>
                </td>
                <td class="px-4 py-4">
                  <p class="max-w-md truncate font-mono text-xs text-zinc-500">
                    {truncate_metadata(log_event.metadata)}
                  </p>
                </td>
                <td class="px-4 py-4">
                  <.action_button
                    navigate={~p"/projects/#{@project.slug}/logs/#{log_event.id}"}
                    icon="hero-arrow-top-right-on-square-mini"
                  >
                    Open
                  </.action_button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div
          :if={@log_count > 0}
          id="logs-pagination"
          class="flex flex-col gap-3 border-t border-zinc-200 bg-slate-50 px-6 py-4 sm:flex-row sm:items-center sm:justify-between"
        >
          <p class="text-sm text-zinc-500">
            Showing {@page_start}-{@page_end} of {@log_count} logs
          </p>

          <div class="flex items-center gap-3">
            <.button
              id="logs-pagination-prev"
              type="button"
              variant="ghost"
              phx-click="paginate"
              phx-value-page={@page - 1}
              disabled={!@has_prev_page?}
            >
              Previous
            </.button>
            <p class="text-sm font-medium text-zinc-700">
              Page {@page} of {@total_pages}
            </p>
            <.button
              id="logs-pagination-next"
              type="button"
              variant="ghost"
              phx-click="paginate"
              phx-value-page={@page + 1}
              disabled={!@has_next_page?}
            >
              Next
            </.button>
          </div>
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
        filters = normalize_filters(params)
        page = normalize_page(params["page"])

        {:ok,
         socket
         |> assign(:project, project)
         |> assign(
           :can_manage_project?,
           user.role == :admin || Teams.team_admin?(user, project.team)
         )
         |> assign(:sidebar, AppShell.build(user, project: project))
         |> assign(:filter_form, to_form(filters, as: :filters))
         |> assign(:tail_mode, false)
         |> assign(:page_size, @page_size)
         |> load_logs(filters, page)}
    end
  end

  @impl true
  def handle_event("filter", %{"filters" => filters}, socket) do
    {:noreply,
     socket
     |> assign(:filter_form, to_form(filters, as: :filters))
     |> load_logs(filters, 1)}
  end

  def handle_event("paginate", %{"page" => page}, socket) do
    filters = socket.assigns.filter_form.params || normalize_filters(%{})

    {:noreply, load_logs(socket, filters, page)}
  end

  def handle_event("toggle-tail", _params, socket) do
    tail_mode = !socket.assigns.tail_mode

    if tail_mode do
      Logs.subscribe(socket.assigns.project)
    else
      Logs.unsubscribe(socket.assigns.project)
    end

    {:noreply, assign(socket, :tail_mode, tail_mode)}
  end

  @impl true
  def handle_info({:log_event_created, _log_event}, socket) do
    if socket.assigns.tail_mode do
      {:noreply, reload_logs(socket)}
    else
      {:noreply, socket}
    end
  end

  defp reload_logs(socket) do
    filters = socket.assigns.filter_form.params || normalize_filters(%{})
    load_logs(socket, filters, socket.assigns.page)
  end

  defp load_logs(socket, filters, page) do
    pagination =
      Logs.paginate_log_events(socket.assigns.project, filters, page, socket.assigns.page_size)

    page_start =
      if pagination.total_count == 0, do: 0, else: (pagination.page - 1) * pagination.per_page + 1

    page_end = min(pagination.page * pagination.per_page, pagination.total_count)

    socket
    |> assign(:page, pagination.page)
    |> assign(:total_pages, pagination.total_pages)
    |> assign(:log_count, pagination.total_count)
    |> assign(:has_prev_page?, pagination.page > 1)
    |> assign(:has_next_page?, pagination.page < pagination.total_pages)
    |> assign(:page_start, page_start)
    |> assign(:page_end, page_end)
    |> stream(:logs, pagination.entries, reset: true)
  end

  defp normalize_filters(params) do
    %{
      "search" => Map.get(params, "search", ""),
      "level" => Map.get(params, "level", "all")
    }
  end

  defp normalize_page(page) when is_integer(page) and page > 0, do: page

  defp normalize_page(page) when is_binary(page) do
    case Integer.parse(page) do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end

  defp normalize_page(_page), do: 1

  defp truncate_metadata(metadata) do
    metadata
    |> Jason.encode!()
    |> maybe_truncate(120)
  end

  defp maybe_truncate(value, max) when byte_size(value) > max,
    do: String.slice(value, 0, max) <> "…"

  defp maybe_truncate(value, _max), do: value
end
