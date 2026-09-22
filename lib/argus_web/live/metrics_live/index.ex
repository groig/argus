defmodule ArgusWeb.MetricsLive.Index do
  use ArgusWeb, :live_view

  alias Argus.Metrics
  alias Argus.Projects
  alias Argus.Teams
  alias ArgusWeb.AppShell

  @page_size 50

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} sidebar={@sidebar}>
      <.header>
        {@project.name} metrics
        <:subtitle>
          Sentry counters, gauges, and distributions with raw samples for inspection.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/projects/#{@project.slug}/issues"} variant="secondary">
            Issues
          </.button>
          <.button navigate={~p"/projects/#{@project.slug}/logs"} variant="secondary">
            Logs
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
        id="metrics-page-shortcuts"
        phx-hook="KeyboardShortcuts"
        class={[
          "overflow-hidden border border-t-4 border-zinc-200 bg-white shadow-[0_1px_3px_rgba(15,23,42,0.08)]",
          project_accent_border_class(@project)
        ]}
      >
        <div class="border-b border-zinc-200 bg-slate-50 px-4 py-4 sm:px-6 sm:py-5">
          <.form
            for={@filter_form}
            id="metric-filters"
            phx-change="filter"
            class="grid gap-4 sm:grid-cols-3"
          >
            <.input
              field={@filter_form[:name]}
              type="select"
              label="Metric"
              prompt="All metrics"
              options={@metric_name_options}
            />
            <.input
              field={@filter_form[:type]}
              type="select"
              label="Type"
              options={Metrics.metric_type_options()}
            />
            <.input
              field={@filter_form[:window]}
              type="select"
              label="Window"
              options={Metrics.window_options()}
            />
          </.form>
        </div>

        <div class="grid min-w-0 gap-6 bg-white p-4 sm:p-6">
          <div
            id="project-metrics-chart-panel"
            class="min-w-0 border border-zinc-200 bg-white shadow-[0_1px_2px_rgba(15,23,42,0.05)]"
          >
            <div class="flex flex-col gap-2 border-b border-zinc-200 bg-slate-50 px-5 py-4 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <h2 class="text-sm font-semibold text-zinc-950">
                  {chart_heading(@chart_data)}
                </h2>
                <p class="mt-1 text-xs text-zinc-500">
                  {chart_subtitle(@chart_data, @metric_count)}
                </p>
              </div>
              <.badge kind={metric_type_label(@chart_data.type)}>
                {metric_type_label(@chart_data.type)}
              </.badge>
            </div>

            <div :if={@metric_count == 0} id="metrics-empty-state" class="px-6 py-16">
              <.empty_state
                title="No metrics yet"
                description="Send a Sentry trace_metric envelope or broaden the filters."
                icon="hero-chart-bar"
              />
            </div>

            <div
              :if={@metric_count > 0}
              id="project-metrics-chart-frame"
              class="h-[380px] min-w-0 overflow-hidden px-2 pb-2 pt-4 sm:h-[460px] sm:px-4 sm:pb-4 sm:pt-5"
            >
              <LiveCharts.chart chart={@metric_chart} />
            </div>
          </div>

          <div class="min-w-0 overflow-hidden border border-zinc-200 bg-white shadow-[0_1px_2px_rgba(15,23,42,0.05)]">
            <table class="w-full divide-y divide-zinc-200 text-sm">
              <thead class="hidden bg-slate-50 text-left text-[11px] font-semibold uppercase tracking-[0.16em] text-zinc-500 md:table-header-group">
                <tr>
                  <th class="px-4 py-3.5">Timestamp</th>
                  <th class="px-4 py-3.5">Metric</th>
                  <th class="px-4 py-3.5">Type</th>
                  <th class="px-4 py-3.5">Value</th>
                  <th class="px-4 py-3.5">Attributes</th>
                  <th class="px-4 py-3.5">Trace</th>
                </tr>
              </thead>
              <tbody
                id="metric-points"
                phx-update="stream"
                class="bg-white md:divide-y md:divide-zinc-100"
              >
                <tr :if={@metric_count == 0} id="metric-points-empty-state">
                  <td colspan="6" class="px-6 py-12 text-center text-sm text-zinc-500">
                    No raw metric points match these filters.
                  </td>
                </tr>
                <tr
                  :for={{dom_id, metric_point} <- @streams.metric_points}
                  id={dom_id}
                  class="mb-3 block border border-zinc-200 bg-white align-top shadow-[0_1px_2px_rgba(15,23,42,0.05)] transition last:mb-0 hover:bg-sky-50/45 md:table-row md:border-0 md:shadow-none"
                >
                  <td class="block px-4 py-3 md:table-cell md:py-4">
                    <span class="mb-1 block text-[11px] font-semibold uppercase text-zinc-400 md:hidden">
                      Timestamp
                    </span>
                    <.relative_time at={metric_point.timestamp} />
                  </td>
                  <td class="block border-t border-zinc-100 px-4 py-3 md:table-cell md:border-t-0 md:py-4">
                    <span class="mb-1 block text-[11px] font-semibold uppercase text-zinc-400 md:hidden">
                      Metric
                    </span>
                    <p class="break-all font-mono text-xs font-semibold text-zinc-950">
                      {metric_point.name}
                    </p>
                    <p :if={metric_point.unit} class="mt-1 text-xs text-zinc-500">
                      unit: {metric_point.unit}
                    </p>
                  </td>
                  <td class="block border-t border-zinc-100 px-4 py-3 md:table-cell md:border-t-0 md:py-4">
                    <span class="mb-1 block text-[11px] font-semibold uppercase text-zinc-400 md:hidden">
                      Type
                    </span>
                    <.badge kind={Atom.to_string(metric_point.type)}>
                      {metric_point.type}
                    </.badge>
                  </td>
                  <td class="block border-t border-zinc-100 px-4 py-3 font-mono text-xs text-zinc-800 md:table-cell md:border-t-0 md:py-4">
                    <span class="mb-1 block font-sans text-[11px] font-semibold uppercase text-zinc-400 md:hidden">
                      Value
                    </span>
                    {format_metric_value(metric_point.value)}
                  </td>
                  <td class="block border-t border-zinc-100 px-4 py-3 md:table-cell md:border-t-0 md:py-4">
                    <span class="mb-1 block text-[11px] font-semibold uppercase text-zinc-400 md:hidden">
                      Attributes
                    </span>
                    <div class="flex max-w-md flex-wrap gap-2">
                      <span
                        :for={{key, value} <- attribute_pills(metric_point)}
                        title={"#{key}: #{value}"}
                        class="inline-flex max-w-full items-center gap-1.5 rounded-full bg-zinc-100 px-2.5 py-1 text-xs text-zinc-600 ring-1 ring-zinc-200"
                      >
                        <span class="text-zinc-400">{key}</span>
                        <span class="truncate font-mono text-zinc-800">{value}</span>
                      </span>
                      <span
                        :if={attribute_pills(metric_point) == []}
                        class="text-xs text-zinc-400"
                      >
                        No attributes
                      </span>
                    </div>
                  </td>
                  <td class="block border-t border-zinc-100 px-4 py-3 md:table-cell md:border-t-0 md:py-4">
                    <span class="mb-1 block text-[11px] font-semibold uppercase text-zinc-400 md:hidden">
                      Trace
                    </span>
                    <p class="max-w-full break-all font-mono text-xs text-zinc-500 md:max-w-48 md:truncate">
                      {metric_point.trace_id || "No trace"}
                    </p>
                    <p :if={metric_point.span_id} class="mt-1 font-mono text-xs text-zinc-400">
                      {metric_point.span_id}
                    </p>
                  </td>
                </tr>
              </tbody>
            </table>

            <div
              :if={@metric_count > 0}
              id="metrics-pagination"
              class="flex flex-col gap-3 border-t border-zinc-200 bg-slate-50 px-4 py-4 sm:flex-row sm:items-center sm:justify-between sm:px-6"
            >
              <p class="text-sm text-zinc-500">
                Showing {@page_start}-{@page_end} of {@metric_count} points
              </p>

              <div class="flex items-center gap-3">
                <.button
                  id="metrics-pagination-prev"
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
                  id="metrics-pagination-next"
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
          </div>
        </div>
      </section>

      <.modal id="metrics-shortcuts-modal" open={@shortcuts_modal_open} title="Keyboard shortcuts">
        <div class="space-y-3">
          <.shortcut_row keys="G then I" label="Go to issues" />
          <.shortcut_row keys="G then L" label="Go to logs" />
          <.shortcut_row keys="G then M" label="Go to metrics" />
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
        filters = default_filters(project, params)
        metric_names = Metrics.list_metric_names(project)

        {:ok,
         socket
         |> assign(:project, project)
         |> assign(
           :can_manage_project?,
           user.role == :admin || Teams.team_admin?(user, project.team)
         )
         |> assign(:sidebar, AppShell.build(user, project: project, section: :metrics))
         |> assign(:metric_name_options, metric_name_options(metric_names))
         |> assign(:filter_form, to_form(filters, as: :filters))
         |> assign(:shortcuts_modal_open, false)
         |> assign(:page_size, @page_size)
         |> load_metrics(filters, 1)}
    end
  end

  @impl true
  def handle_event("filter", %{"filters" => filters}, socket) do
    filters = default_filters(socket.assigns.project, filters)

    {:noreply,
     socket
     |> assign(:filter_form, to_form(filters, as: :filters))
     |> load_metrics(filters, 1)}
  end

  def handle_event("paginate", %{"page" => page}, socket) do
    filters = socket.assigns.filter_form.params || default_filters(socket.assigns.project, %{})

    {:noreply, load_metrics(socket, filters, page)}
  end

  def handle_event("shortcut", %{"key" => "g i"}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/projects/#{socket.assigns.project.slug}/issues")}
  end

  def handle_event("shortcut", %{"key" => "g l"}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/projects/#{socket.assigns.project.slug}/logs")}
  end

  def handle_event("shortcut", %{"key" => "g m"}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/projects/#{socket.assigns.project.slug}/metrics")}
  end

  def handle_event("shortcut", %{"key" => "help"}, socket) do
    {:noreply, assign(socket, :shortcuts_modal_open, true)}
  end

  def handle_event("shortcut", _params, socket), do: {:noreply, socket}

  def handle_event("close-shortcuts", _params, socket) do
    {:noreply, assign(socket, :shortcuts_modal_open, false)}
  end

  defp load_metrics(socket, filters, page) do
    filters = default_filters(socket.assigns.project, filters)
    pagination = Metrics.paginate_metric_points(socket.assigns.project, filters, page, @page_size)
    chart_data = Metrics.chart_data(socket.assigns.project, filters)

    page_start =
      if pagination.total_count == 0, do: 0, else: (pagination.page - 1) * pagination.per_page + 1

    page_end = min(pagination.page * pagination.per_page, pagination.total_count)

    socket
    |> assign(:page, pagination.page)
    |> assign(:total_pages, pagination.total_pages)
    |> assign(:metric_count, pagination.total_count)
    |> assign(:has_prev_page?, pagination.page > 1)
    |> assign(:has_next_page?, pagination.page < pagination.total_pages)
    |> assign(:page_start, page_start)
    |> assign(:page_end, page_end)
    |> assign(:chart_data, chart_data)
    |> assign(:metric_chart, build_chart(chart_data))
    |> stream(:metric_points, pagination.entries, reset: true)
  end

  defp default_filters(project, params) do
    filters = Metrics.normalize_filters(params)
    latest = Metrics.latest_metric(project, filters["name"])
    name = if filters["name"] == "" && latest, do: latest.name, else: filters["name"]

    latest_for_name = Metrics.latest_metric(project, name)

    type =
      if filters["type"] == "" && latest_for_name do
        Atom.to_string(latest_for_name.type)
      else
        filters["type"]
      end

    %{
      "name" => name || "",
      "type" => type || "",
      "window" => filters["window"]
    }
  end

  defp build_chart(%{type: type, buckets: buckets, unit: unit} = chart_data) do
    LiveCharts.build(%{
      id: "project-metrics-chart",
      type: chart_kind(type),
      series: chart_series(type, buckets),
      options: chart_options(chart_data.name, type, unit)
    })
  end

  defp chart_kind(:counter), do: :bar
  defp chart_kind(:gauge), do: :line
  defp chart_kind(:distribution), do: :area
  defp chart_kind(_), do: :line

  defp chart_series(:counter, buckets) do
    [%{name: "Sum", data: data_points(buckets, :sum)}]
  end

  defp chart_series(:distribution, buckets) do
    [
      %{name: "Average", data: data_points(buckets, :avg)},
      %{name: "Minimum", data: data_points(buckets, :min)},
      %{name: "Maximum", data: data_points(buckets, :max)}
    ]
  end

  defp chart_series(_type, buckets) do
    [%{name: "Average", data: data_points(buckets, :avg)}]
  end

  defp data_points(buckets, key) do
    Enum.map(buckets, fn bucket ->
      %{x: DateTime.to_iso8601(bucket.bucket), y: rounded_number(Map.fetch!(bucket, key))}
    end)
  end

  defp chart_options(name, type, unit) do
    %{
      chart: %{
        height: "100%",
        width: "100%",
        toolbar: %{show: false},
        animations: %{enabled: true},
        parentHeightOffset: 0,
        redrawOnParentResize: true,
        redrawOnWindowResize: true
      },
      stroke: %{curve: "smooth", width: 2},
      fill: %{opacity: if(type == :distribution, do: 0.18, else: 0.85)},
      colors: ["#0284c7", "#10b981", "#f59e0b"],
      dataLabels: %{enabled: false},
      grid: %{
        borderColor: "#e4e4e7",
        strokeDashArray: 4,
        padding: %{bottom: 6, left: 4, right: 4}
      },
      legend: %{position: "bottom", horizontalAlign: "center", fontSize: "12px"},
      xaxis: %{
        type: "datetime",
        axisBorder: %{show: true, color: "#d4d4d8"},
        axisTicks: %{show: true, color: "#d4d4d8"},
        labels: %{
          show: true,
          datetimeUTC: false,
          hideOverlappingLabels: true,
          rotate: 0,
          trim: true
        }
      },
      yaxis: %{title: %{text: yaxis_title(name, unit)}},
      tooltip: %{x: %{format: "yyyy-MM-dd HH:mm"}}
    }
  end

  defp yaxis_title("", nil), do: "value"
  defp yaxis_title("", unit), do: "value (#{unit})"
  defp yaxis_title(name, nil), do: name
  defp yaxis_title(name, unit), do: "#{name} (#{unit})"

  defp metric_name_options(metric_names), do: Enum.map(metric_names, &{&1, &1})

  defp chart_heading(%{name: "", type: type}), do: "#{metric_type_label(type)} metrics"
  defp chart_heading(%{name: name}), do: name

  defp chart_subtitle(%{unit: nil}, count), do: "#{count} raw points in the selected window"
  defp chart_subtitle(%{unit: unit}, count), do: "#{count} raw points, unit #{unit}"

  defp metric_type_label(nil), do: "metric"
  defp metric_type_label(type) when is_atom(type), do: Atom.to_string(type)
  defp metric_type_label(type) when is_binary(type), do: type

  defp attribute_pills(metric_point) do
    metric_point.attributes
    |> normalize_map()
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.take(4)
    |> Enum.map(fn {key, value} -> {key, maybe_truncate(format_attribute_value(value), 36)} end)
  end

  defp normalize_map(map) when is_map(map), do: map
  defp normalize_map(_), do: %{}

  defp rounded_number(value), do: Float.round(value * 1.0, 4)

  defp format_metric_value(value) when is_number(value) do
    value
    |> rounded_number()
    |> :erlang.float_to_binary(decimals: 4)
    |> String.trim_trailing("0")
    |> String.trim_trailing(".")
  end

  defp format_attribute_value(value) when is_binary(value), do: value
  defp format_attribute_value(value), do: inspect(value)

  defp maybe_truncate(value, max) when byte_size(value) > max,
    do: String.slice(value, 0, max) <> "..."

  defp maybe_truncate(value, _max), do: value

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
