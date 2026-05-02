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

      <section
        id="logs-page-shortcuts"
        phx-hook="KeyboardShortcuts"
        class={[
          "overflow-hidden border border-t-4 border-zinc-200 bg-white shadow-[0_1px_3px_rgba(15,23,42,0.08)]",
          project_accent_border_class(@project)
        ]}
      >
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
                  "border-emerald-200 bg-emerald-50 text-emerald-700",
                !@tail_mode &&
                  "border-zinc-200 bg-white text-zinc-600 hover:border-emerald-200 hover:text-emerald-700"
              ]}
            >
              <span class={[
                "relative flex h-5 w-9 items-center border transition",
                @tail_mode && "border-emerald-500 bg-emerald-500",
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
                  @tail_mode && "animate-pulse bg-emerald-500",
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
                class={[
                  "align-top transition hover:bg-sky-50/45",
                  @highlight_log_id == log_event.id && "bg-emerald-50/70"
                ]}
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
                  <div class="flex max-w-md flex-wrap gap-2">
                    <span
                      :for={{key, value} <- metadata_pills(log_event)}
                      title={"#{key}: #{value}"}
                      class="inline-flex max-w-full items-center gap-1.5 rounded-full bg-zinc-100 px-2.5 py-1 text-xs text-zinc-600 ring-1 ring-zinc-200"
                    >
                      <span class="text-zinc-400">{key}</span>
                      <span class="truncate font-mono text-zinc-800">{value}</span>
                    </span>
                    <span :if={metadata_pills(log_event) == []} class="text-xs text-zinc-400">
                      No metadata
                    </span>
                  </div>
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

      <.modal id="logs-shortcuts-modal" open={@shortcuts_modal_open} title="Keyboard shortcuts">
        <div class="space-y-3">
          <.shortcut_row keys="G then I" label="Go to issues" />
          <.shortcut_row keys="G then L" label="Go to logs" />
          <.shortcut_row keys="?" label="Show shortcuts" />
        </div>
        <:actions>
          <.button type="button" variant="ghost" phx-click="close-shortcuts">Close</.button>
        </:actions>
      </.modal>
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
         |> assign(:highlight_log_id, nil)
         |> assign(:shortcuts_modal_open, false)
         |> assign(:page_size, @page_size)
         |> load_logs(filters, page)}
    end
  end

  @impl true
  def handle_event("filter", %{"filters" => filters}, socket) do
    {:noreply,
     socket
     |> assign(:filter_form, to_form(filters, as: :filters))
     |> assign(:highlight_log_id, nil)
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

  def handle_event("shortcut", %{"key" => "g i"}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/projects/#{socket.assigns.project.slug}/issues")}
  end

  def handle_event("shortcut", %{"key" => "g l"}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/projects/#{socket.assigns.project.slug}/logs")}
  end

  def handle_event("shortcut", %{"key" => "help"}, socket) do
    {:noreply, assign(socket, :shortcuts_modal_open, true)}
  end

  def handle_event("shortcut", _params, socket), do: {:noreply, socket}

  def handle_event("close-shortcuts", _params, socket) do
    {:noreply, assign(socket, :shortcuts_modal_open, false)}
  end

  @impl true
  def handle_info({:log_event_created, log_event}, socket) do
    if socket.assigns.tail_mode do
      {:noreply, socket |> assign(:highlight_log_id, log_event.id) |> reload_logs()}
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

  defp metadata_pills(log_event) do
    attributes =
      log_event.metadata
      |> normalize_map()
      |> Map.get("attributes", %{})
      |> normalize_map()

    [
      {"route", attributes["http.route"]},
      {"function", attributes["code.function_name"]},
      {"env", log_event.environment || attributes["deployment.environment"]},
      {"release", log_event.release || attributes["sentry.release"]},
      {"logger", log_event.logger_name || attributes["logger.name"]},
      {"origin", log_event.origin}
    ]
    |> Enum.reject(fn {_key, value} -> blank?(value) end)
    |> Enum.take(3)
    |> Enum.map(fn {key, value} -> {key, maybe_truncate(to_string(value), 36)} end)
  end

  defp maybe_truncate(value, max) when byte_size(value) > max,
    do: String.slice(value, 0, max) <> "..."

  defp maybe_truncate(value, _max), do: value

  defp normalize_map(map) when is_map(map), do: map
  defp normalize_map(_map), do: %{}
  defp blank?(value), do: value in [nil, "", []]

  attr :keys, :string, required: true
  attr :label, :string, required: true

  defp shortcut_row(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-4">
      <span class="text-sm text-zinc-600">{@label}</span>
      <kbd class="rounded-sm border border-zinc-200 bg-slate-50 px-2 py-1 font-mono text-xs text-zinc-700">
        {@keys}
      </kbd>
    </div>
    """
  end
end
