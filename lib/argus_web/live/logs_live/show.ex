defmodule ArgusWeb.LogsLive.Show do
  use ArgusWeb, :live_view

  alias Argus.Logs
  alias Argus.Projects
  alias ArgusWeb.AppShell

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} sidebar={@sidebar}>
      <.header>
        {@log_event.message}
        <:subtitle>{@log_event.logger_name || @log_event.origin || "Stored log event"}</:subtitle>
        <:actions>
          <.button navigate={~p"/projects/#{@project.slug}/logs"} variant="ghost" size="sm">
            Back to logs
          </.button>
          <.button navigate={~p"/projects/#{@project.slug}/issues"} variant="secondary" size="sm">
            Issues
          </.button>
        </:actions>
      </.header>

      <section class="grid gap-6 xl:grid-cols-[minmax(0,1.35fr)_22rem]">
        <div class="space-y-6">
          <section class="border border-zinc-200 bg-white p-6">
            <div class="flex flex-wrap items-start justify-between gap-4">
              <div class="space-y-3">
                <div class="flex flex-wrap items-center gap-3">
                  <.badge kind={@log_event.level}>{@log_event.level}</.badge>
                  <span class="text-sm text-zinc-500">
                    Captured <.relative_time at={@log_event.timestamp} />
                  </span>
                  <span :if={@log_event.logger_name} class="font-mono text-xs text-zinc-500">
                    {@log_event.logger_name}
                  </span>
                </div>

                <div :if={log_headline_meta(@log_event) != []} class="flex flex-wrap gap-2">
                  <span
                    :for={{label, value} <- log_headline_meta(@log_event)}
                    title={value}
                    class="inline-flex max-w-full items-center gap-2 border border-zinc-200 px-3 py-1.5 text-xs text-zinc-600"
                  >
                    <span class="text-zinc-400">{label}</span>
                    <span class="max-w-44 overflow-hidden text-ellipsis whitespace-nowrap font-mono text-zinc-800">
                      {headline_pill_value(label, value)}
                    </span>
                  </span>
                </div>
              </div>
            </div>
          </section>

          <section>
            <div class="flex flex-wrap items-center gap-5 border-b border-zinc-200 px-0 pt-1">
              <.link
                id="log-formatted-tab"
                patch={log_patch(@project, @log_event, "formatted")}
                class={tab_class(@tab == "formatted")}
              >
                Formatted
              </.link>
              <.link
                id="log-raw-tab"
                patch={log_patch(@project, @log_event, "raw")}
                class={tab_class(@tab == "raw")}
              >
                Raw
              </.link>
            </div>

            <div class="pt-6">
              <%= if @tab == "formatted" do %>
                <div id="log-formatted-view" class="space-y-4">
                  <section
                    :for={{title, data} <- @formatted_sections}
                    class="space-y-3"
                  >
                    <div class="space-y-1">
                      <h2 class="text-lg font-semibold tracking-tight text-zinc-950">{title}</h2>
                    </div>
                    <div class="space-y-px">
                      <.log_entries entries={map_entries(data)} />
                    </div>
                  </section>

                  <.empty_state
                    :if={@formatted_sections == []}
                    title="No formatted metadata captured"
                    description="This log only stored its message, level, and timestamp."
                    icon="hero-document-text"
                  />
                </div>
              <% end %>

              <%= if @tab == "raw" do %>
                <section id="log-raw-view" class="space-y-4">
                  <div class="flex items-center justify-between gap-3">
                    <div class="space-y-1">
                      <h2 class="text-lg font-semibold tracking-tight text-zinc-950">Raw payload</h2>
                      <p class="text-sm text-zinc-500">
                        Full stored log payload as JSON.
                      </p>
                    </div>
                    <.copy_to_clipboard
                      id="copy-log-raw"
                      value={@raw_json}
                      label="Copy raw JSON"
                      compact
                      tooltip="Copy raw JSON"
                      toast_message="Raw log payload copied"
                      class="font-medium text-sky-700"
                    />
                  </div>

                  <pre
                    id="log-raw-json"
                    phx-no-curly-interpolation
                    class="overflow-x-auto border border-zinc-900 bg-zinc-950 p-5 font-mono text-xs leading-6 text-zinc-100"
                  ><%= @raw_json %></pre>
                </section>
              <% end %>
            </div>
          </section>
        </div>

        <aside class="space-y-6">
          <.data_panel
            id="log-summary-panel"
            title="Summary"
            data={summary_data(@log_event)}
            empty_text="No log summary captured"
          />
          <.identifier_panel
            :if={identifier_rows(@log_event) != []}
            id="log-identifiers-panel"
            rows={identifier_rows(@log_event)}
          />
        </aside>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"slug" => slug, "id" => id} = params, _session, socket) do
    user = socket.assigns.current_scope.user

    with %{} = project <- Projects.get_project_for_user_by_slug(user, slug),
         %{} = log_event <- Logs.get_log_event(project, String.to_integer(id)) do
      {:ok, assign_page(socket, project, log_event, params)}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/projects")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign_page(socket, socket.assigns.project, socket.assigns.log_event, params)}
  end

  defp assign_page(socket, project, log_event, params) do
    tab = parse_tab(Map.get(params, "tab", "formatted"))

    socket
    |> assign(:project, project)
    |> assign(:log_event, log_event)
    |> assign(:tab, tab)
    |> assign(:raw_json, Jason.encode!(raw_log_payload(log_event), pretty: true))
    |> assign(:formatted_sections, formatted_sections(log_event))
    |> assign(:sidebar, AppShell.build(socket.assigns.current_scope.user, project: project))
  end

  defp parse_tab(tab) when tab in ~w(formatted raw), do: tab
  defp parse_tab(_tab), do: "formatted"

  defp log_patch(project, log_event, tab),
    do: ~p"/projects/#{project.slug}/logs/#{log_event.id}?tab=#{tab}"

  defp tab_class(true),
    do: "border-b-2 border-zinc-950 px-0 pb-3 text-sm font-medium text-zinc-950"

  defp tab_class(false),
    do:
      "border-b-2 border-transparent px-0 pb-3 text-sm text-zinc-500 transition hover:border-zinc-300 hover:text-zinc-900"

  attr :id, :string, default: nil
  attr :title, :string, required: true
  attr :data, :map, default: %{}
  attr :empty_text, :string, required: true

  defp data_panel(assigns) do
    ~H"""
    <section id={@id} class="border border-zinc-200 bg-white p-5">
      <h2 class="text-[11px] font-semibold uppercase tracking-[0.16em] text-zinc-500">{@title}</h2>

      <%= if map_size(@data || %{}) == 0 do %>
        <p class="mt-4 text-sm leading-6 text-zinc-500">{@empty_text}</p>
      <% else %>
        <div class="mt-4 space-y-px">
          <.sidebar_entries entries={map_entries(@data)} />
        </div>
      <% end %>
    </section>
    """
  end

  attr :entries, :list, required: true

  defp sidebar_entries(assigns) do
    ~H"""
    <div class="space-y-px">
      <div
        :for={{entry, index} <- Enum.with_index(@entries)}
        class={[
          "grid gap-1 px-4 py-2.5 sm:grid-cols-[88px_minmax(0,1fr)] sm:items-baseline sm:gap-4",
          rem(index, 2) == 0 && "bg-zinc-50/80",
          rem(index, 2) == 1 && "bg-white"
        ]}
      >
        <% {key, value} = entry %>
        <p class="text-[11px] font-semibold uppercase tracking-[0.14em] text-zinc-500">
          {labelize(key)}
        </p>
        <p class={sidebar_value_text_class(value)} title={format_value(value)}>
          {format_value(value)}
        </p>
      </div>
    </div>
    """
  end

  defp log_entries(assigns) do
    ~H"""
    <div class="space-y-px">
      <div
        :for={{entry, index} <- Enum.with_index(@entries)}
        class={[
          "grid gap-2 px-4 py-2.5 sm:grid-cols-[220px_minmax(0,1fr)] sm:items-baseline sm:gap-6",
          rem(index, 2) == 0 && "bg-zinc-50/80",
          rem(index, 2) == 1 && "bg-white"
        ]}
      >
        <% {key, value} = entry %>
        <%= cond do %>
          <% is_map(value) and map_size(value) > 0 -> %>
            <div class="space-y-2">
              <p class="font-mono text-xs leading-5 text-zinc-400">{display_key(key)}</p>
              <details class="overflow-hidden rounded-md border border-zinc-200 bg-white">
                <summary class="cursor-pointer list-none px-4 py-3 text-sm font-medium text-zinc-700">
                  Open object
                </summary>
                <div class="border-t border-zinc-100">
                  <.log_entries entries={map_entries(value)} />
                </div>
              </details>
            </div>
          <% is_list(value) and value != [] and Enum.all?(value, &is_map/1) -> %>
            <div class="space-y-2">
              <p class="font-mono text-xs leading-5 text-zinc-400">{display_key(key)}</p>
              <details class="overflow-hidden rounded-md border border-zinc-200 bg-white">
                <summary class="cursor-pointer list-none px-4 py-3 text-sm font-medium text-zinc-700">
                  {length(value)} items
                </summary>
                <div class="space-y-3 border-t border-zinc-100 p-4">
                  <div
                    :for={item <- value}
                    class="overflow-hidden rounded-md border border-zinc-200 bg-white"
                  >
                    <.log_entries entries={map_entries(item)} />
                  </div>
                </div>
              </details>
            </div>
          <% is_list(value) and value != [] -> %>
            <div class="space-y-2">
              <p class="font-mono text-xs leading-5 text-zinc-400">{display_key(key)}</p>
              <ul class="space-y-1.5 text-sm text-zinc-700">
                <li :for={item <- value}>{format_value(item)}</li>
              </ul>
            </div>
          <% true -> %>
            <p class="font-mono text-xs leading-5 text-zinc-400">{display_key(key)}</p>
            <p class={value_text_class(value)} title={format_value(value)}>{format_value(value)}</p>
        <% end %>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :rows, :list, required: true

  defp identifier_panel(assigns) do
    ~H"""
    <section id={@id} class="border border-zinc-200 bg-white p-5">
      <h2 class="text-[11px] font-semibold uppercase tracking-[0.16em] text-zinc-500">Identifiers</h2>

      <div class="mt-4 space-y-3">
        <div
          :for={{label, value} <- @rows}
          class="grid gap-1 sm:grid-cols-[96px_minmax(0,1fr)] sm:items-baseline sm:gap-4"
        >
          <p class="text-[11px] font-semibold uppercase tracking-[0.14em] text-zinc-500">
            {labelize(label)}
          </p>
          <%= if is_binary(value) do %>
            <.copy_to_clipboard
              id={"#{@id}-#{label}"}
              value={value}
              label={truncate_identifier(value)}
              compact
              tooltip={value}
              toast_message={"#{labelize(label)} copied"}
              class="font-mono text-xs text-zinc-700 hover:text-sky-700"
            />
          <% else %>
            <p class="font-mono text-xs leading-6 text-zinc-800">{format_value(value)}</p>
          <% end %>
        </div>
      </div>
    </section>
    """
  end

  defp log_headline_meta(log_event) do
    [
      {"environment", log_event.environment},
      {"release", log_event.release},
      {"origin", log_event.origin},
      {"sdk", sdk_label(log_event)}
    ]
    |> Enum.reject(fn {_label, value} -> blank?(value) end)
  end

  defp formatted_sections(log_event) do
    metadata = normalize_map(log_event.metadata)

    [
      {"Attributes", filtered_attributes(metadata)},
      {"Metadata", filtered_metadata(metadata)}
    ]
    |> Enum.reject(fn {_title, data} -> map_size(data) == 0 end)
  end

  defp summary_data(log_event) do
    %{
      "level" => display_level(log_event.level),
      "timestamp" => Calendar.strftime(log_event.timestamp, "%Y-%m-%d %H:%M:%S UTC"),
      "logger_name" => log_event.logger_name,
      "message_template" => log_event.message_template,
      "environment" => log_event.environment
    }
    |> Enum.reject(fn {_key, value} -> blank?(value) end)
    |> Map.new()
  end

  defp identifier_rows(log_event) do
    [
      {"trace_id", log_event.trace_id},
      {"span_id", log_event.span_id},
      {"sequence", if(log_event.sequence == 0, do: nil, else: log_event.sequence)}
    ]
    |> Enum.reject(fn {_label, value} -> blank?(value) end)
  end

  @duplicate_attribute_keys ~w(
    logger.name
    sentry.message.template
    sentry.origin
    sentry.release
    sentry.environment
    sentry.sdk.name
    sentry.sdk.version
    sentry.timestamp.sequence
    trace_id
    span_id
    trace.id
    span.id
  )

  defp filtered_attributes(metadata) do
    metadata
    |> Map.get("attributes", %{})
    |> normalize_map()
    |> Map.drop(@duplicate_attribute_keys)
  end

  defp filtered_metadata(metadata) do
    metadata
    |> Map.drop(["attributes", "trace_id", "span_id"])
  end

  defp headline_pill_value("release", value) when is_binary(value) do
    if String.match?(value, ~r/^[a-f0-9]{16,}$/i) do
      String.slice(value, 0, 8) <> "..."
    else
      value
    end
  end

  defp headline_pill_value(_label, value), do: value

  defp display_key(key), do: to_string(key)

  defp truncate_identifier(value) when is_binary(value) and byte_size(value) > 16 do
    String.slice(value, 0, 8) <> "..." <> String.slice(value, -4, 4)
  end

  defp truncate_identifier(value), do: value

  defp raw_log_payload(log_event) do
    %{
      "id" => log_event.id,
      "level" => log_event.level,
      "message" => log_event.message,
      "timestamp" => DateTime.to_iso8601(log_event.timestamp),
      "logger_name" => log_event.logger_name,
      "message_template" => log_event.message_template,
      "origin" => log_event.origin,
      "release" => log_event.release,
      "environment" => log_event.environment,
      "sdk_name" => log_event.sdk_name,
      "sdk_version" => log_event.sdk_version,
      "sequence" => log_event.sequence,
      "trace_id" => log_event.trace_id,
      "span_id" => log_event.span_id,
      "metadata" => normalize_map(log_event.metadata)
    }
    |> Enum.reject(fn {_key, value} -> blank?(value) end)
    |> Map.new()
  end

  defp sdk_label(log_event) do
    [log_event.sdk_name, log_event.sdk_version]
    |> Enum.reject(&blank?/1)
    |> Enum.join(" ")
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp map_entries(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
  end

  defp normalize_map(map) when is_map(map), do: map
  defp normalize_map(_map), do: %{}

  defp labelize(key) do
    key
    |> to_string()
    |> String.replace(~r/[_\.]/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.capitalize()
  end

  defp format_value(nil), do: "-"
  defp format_value(value) when is_binary(value), do: value
  defp format_value(value) when is_atom(value), do: Atom.to_string(value)
  defp format_value(value) when is_boolean(value), do: to_string(value)
  defp format_value(value) when is_integer(value) or is_float(value), do: to_string(value)
  defp format_value(value), do: inspect(value)

  defp value_text_class(value) do
    technical? =
      case value do
        binary when is_binary(binary) ->
          String.length(binary) > 24 or
            String.contains?(binary, ["http://", "https://", "_", "/", "@"]) or
            !String.contains?(binary, " ")

        _ ->
          false
      end

    [
      "min-w-0 leading-6 text-zinc-800",
      technical? && "max-w-full overflow-x-auto whitespace-nowrap font-mono text-xs",
      !technical? && "break-words text-sm"
    ]
  end

  defp sidebar_value_text_class(value) do
    technical? =
      case value do
        binary when is_binary(binary) ->
          String.length(binary) > 16 or
            String.contains?(binary, ["http://", "https://", "_", "/", "@", ":"]) or
            !String.contains?(binary, " ")

        _ ->
          false
      end

    [
      "min-w-0 overflow-hidden text-ellipsis whitespace-nowrap leading-6 text-zinc-800",
      technical? && "font-mono text-xs",
      !technical? && "text-sm"
    ]
  end

  defp display_level(:warning), do: "warning"
  defp display_level(:error), do: "error"
  defp display_level(:info), do: "info"
  defp display_level("warn"), do: "warning"
  defp display_level("warning"), do: "warning"
  defp display_level("error"), do: "error"
  defp display_level("info"), do: "info"
  defp display_level(value), do: format_value(value)

  defp blank?(value), do: value in [nil, "", []]
end
