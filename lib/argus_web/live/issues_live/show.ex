defmodule ArgusWeb.IssuesLive.Show do
  use ArgusWeb, :live_view

  alias Argus.Projects
  alias ArgusWeb.AppShell

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} sidebar={@sidebar}>
      <.header>
        {@issue.title}
        <:subtitle>{@issue.culprit || "No culprit captured"}</:subtitle>
        <:actions>
          <.button navigate={~p"/projects/#{@project.slug}/issues"} variant="ghost" size="sm">
            Back to issues
          </.button>
          <.button
            :if={@issue.status != :unresolved}
            phx-click="set-status"
            phx-value-status="unresolved"
            variant="secondary"
            size="sm"
          >
            Unresolve
          </.button>
          <.button
            :if={@issue.status != :resolved}
            phx-click="set-status"
            phx-value-status="resolved"
            variant="secondary"
            size="sm"
          >
            Resolve
          </.button>
          <.button
            :if={@issue.status != :ignored}
            phx-click="set-status"
            phx-value-status="ignored"
            variant="danger"
            size="sm"
          >
            Ignore
          </.button>
        </:actions>
      </.header>

      <section class="grid gap-6 xl:grid-cols-[minmax(0,1.35fr)_22rem]">
        <div class="space-y-6">
          <section class="border border-zinc-200 bg-white p-6">
            <div class="flex flex-wrap items-start justify-between gap-4">
              <div class="flex flex-wrap items-center gap-3">
                <.badge kind={@issue.level}>{@issue.level}</.badge>
                <.badge kind={@issue.status}>{@issue.status}</.badge>
                <span class="text-sm text-zinc-500">
                  Assigned to {assignee_name(@issue.assignee)}
                </span>
                <span class="text-sm text-zinc-500">
                  First seen <.relative_time at={@issue.first_seen_at} />
                </span>
                <span class="text-sm text-zinc-500">
                  Last seen <.relative_time at={@issue.last_seen_at} />
                </span>
                <span class="text-sm text-zinc-500">{@issue.occurrence_count} occurrences</span>
              </div>

              <div
                :if={@selected_occurrence}
                id="issue-occurrence-nav"
                class="flex items-center gap-2"
              >
                <.button
                  :if={@newer_occurrence}
                  id="issue-newer-event"
                  patch={issue_patch(@project, @issue, "event", @newer_occurrence.id, @frame_mode)}
                  variant="ghost"
                  size="sm"
                >
                  Newer
                </.button>
                <div
                  id="issue-event-position"
                  data-position={@selected_occurrence_position}
                  class="border border-zinc-200 bg-slate-50 px-3 py-2 text-sm text-zinc-600"
                >
                  Event {@selected_occurrence_position} of {@occurrence_count}
                </div>
                <.button
                  :if={@older_occurrence}
                  id="issue-older-event"
                  patch={issue_patch(@project, @issue, "event", @older_occurrence.id, @frame_mode)}
                  variant="ghost"
                  size="sm"
                >
                  Older
                </.button>
              </div>
            </div>
          </section>

          <section class="border border-zinc-200 bg-white">
            <div class="flex flex-wrap items-center gap-5 border-b border-zinc-200 px-6 pt-4">
              <.link
                id="issue-event-tab"
                patch={
                  issue_patch(
                    @project,
                    @issue,
                    "event",
                    selected_occurrence_id(@selected_occurrence),
                    @frame_mode
                  )
                }
                class={tab_class(@tab == "event")}
              >
                Event
              </.link>
              <.link
                id="issue-events-tab"
                patch={
                  issue_patch(
                    @project,
                    @issue,
                    "events",
                    selected_occurrence_id(@selected_occurrence),
                    @frame_mode
                  )
                }
                class={tab_class(@tab == "events")}
              >
                Event list
              </.link>
              <.link
                id="issue-tags-tab"
                patch={
                  issue_patch(
                    @project,
                    @issue,
                    "tags",
                    selected_occurrence_id(@selected_occurrence),
                    @frame_mode
                  )
                }
                class={tab_class(@tab == "tags")}
              >
                Tags
              </.link>
              <.link
                id="issue-breadcrumbs-tab"
                patch={
                  issue_patch(
                    @project,
                    @issue,
                    "breadcrumbs",
                    selected_occurrence_id(@selected_occurrence),
                    @frame_mode
                  )
                }
                class={tab_class(@tab == "breadcrumbs")}
              >
                Breadcrumbs
              </.link>
              <.link
                id="issue-context-tab"
                patch={
                  issue_patch(
                    @project,
                    @issue,
                    "context",
                    selected_occurrence_id(@selected_occurrence),
                    @frame_mode
                  )
                }
                class={tab_class(@tab == "context")}
              >
                Context
              </.link>
            </div>

            <div class="p-6">
              <%= if @tab == "event" do %>
                <%= if @selected_occurrence do %>
                  <div id="issue-event-view" class="space-y-6">
                    <section
                      id="issue-selected-event"
                      class="border border-zinc-200 bg-slate-50 px-5 py-5"
                    >
                      <div class="flex flex-wrap items-start justify-between gap-4">
                        <div class="space-y-2">
                          <p class="text-lg font-semibold tracking-tight text-zinc-950">
                            {primary_exception_title(@selected_occurrence) || @issue.title}
                          </p>
                          <div class="flex flex-wrap gap-x-5 gap-y-2 text-sm text-zinc-500">
                            <span>
                              Event ID
                              <span class="font-mono text-xs text-zinc-700">
                                {@selected_occurrence.event_id}
                              </span>
                            </span>
                            <span>
                              Captured <.relative_time at={@selected_occurrence.timestamp} />
                            </span>
                            <span :if={@selected_occurrence.request_url}>
                              Request
                              <span class="font-mono text-xs text-zinc-700">
                                {@selected_occurrence.request_url}
                              </span>
                            </span>
                          </div>
                        </div>

                        <div class="flex flex-wrap gap-2">
                          <.badge
                            :if={handled_exception?(@selected_occurrence)}
                            kind="resolved"
                            class="bg-emerald-50 text-emerald-700"
                          >
                            handled
                          </.badge>
                          <.badge
                            :if={!handled_exception?(@selected_occurrence)}
                            kind="error"
                            class="bg-red-50 text-red-700"
                          >
                            unhandled
                          </.badge>
                        </div>
                      </div>

                      <div
                        :if={event_headline_meta(@selected_occurrence, @issue) != []}
                        class="mt-4 flex flex-wrap gap-2"
                      >
                        <span
                          :for={{label, value} <- event_headline_meta(@selected_occurrence, @issue)}
                          class="inline-flex max-w-full items-center gap-2 border border-zinc-200 bg-white px-3 py-1.5 text-xs text-zinc-600"
                        >
                          <span class="text-zinc-400">{label}</span>
                          <span class="break-all font-mono text-zinc-800">{value}</span>
                        </span>
                      </div>
                    </section>

                    <section
                      :for={exception <- @selected_occurrence.exception_values}
                      class="space-y-4"
                    >
                      <% frames = stack_frames(exception) %>
                      <% visible_frames = visible_stack_frames(frames, @frame_mode) %>
                      <div class="flex flex-wrap items-start justify-between gap-4">
                        <div class="space-y-1">
                          <p class="text-lg font-semibold tracking-tight text-zinc-950">
                            {exception["type"] || "Captured exception"}
                          </p>
                          <p :if={exception["value"]} class="text-sm leading-6 text-zinc-600">
                            {exception["value"]}
                          </p>
                          <p class="text-xs text-zinc-500">
                            {frame_scope_note(frames, @frame_mode)}
                          </p>
                        </div>

                        <div :if={toggleable_frames?(frames)} class="flex items-center gap-2">
                          <.button
                            :if={@frame_mode == "in_app"}
                            id="issue-show-all-frames"
                            patch={
                              issue_patch(
                                @project,
                                @issue,
                                "event",
                                selected_occurrence_id(@selected_occurrence),
                                "all"
                              )
                            }
                            variant="ghost"
                            size="xs"
                          >
                            Show all frames
                          </.button>
                          <.button
                            :if={@frame_mode == "all"}
                            id="issue-show-in-app-frames"
                            patch={
                              issue_patch(
                                @project,
                                @issue,
                                "event",
                                selected_occurrence_id(@selected_occurrence),
                                "in_app"
                              )
                            }
                            variant="ghost"
                            size="xs"
                          >
                            In-app only
                          </.button>
                        </div>
                      </div>

                      <div class="space-y-3">
                        <.frame_card
                          :for={{frame, index} <- Enum.with_index(visible_frames)}
                          index={index}
                          frame={frame}
                          selected={index == selected_frame_index(visible_frames)}
                        />
                      </div>
                    </section>
                  </div>
                <% else %>
                  <.empty_state
                    title="No event data captured"
                    description="Argus has the grouped issue, but there is no stored occurrence for it yet."
                    icon="hero-bug-ant"
                  />
                <% end %>
              <% end %>

              <%= if @tab == "events" do %>
                <div id="issue-events-list" class="space-y-3">
                  <.link
                    :for={occurrence <- @all_occurrences}
                    patch={issue_patch(@project, @issue, "event", occurrence.id, @frame_mode)}
                    class={[
                      "block border px-4 py-4 transition",
                      @selected_occurrence && @selected_occurrence.id == occurrence.id &&
                        "border-sky-200 bg-sky-50",
                      (!@selected_occurrence || @selected_occurrence.id != occurrence.id) &&
                        "border-zinc-200 bg-white hover:border-sky-200 hover:bg-slate-50"
                    ]}
                  >
                    <div class="flex flex-wrap items-start justify-between gap-4">
                      <div class="space-y-1">
                        <p class="text-sm font-medium text-zinc-950">
                          {primary_exception_title(occurrence) || occurrence.request_url ||
                            "Stored event"}
                        </p>
                        <p class="font-mono text-xs text-zinc-500">
                          {occurrence.request_url || "No request URL"}
                        </p>
                      </div>
                      <.relative_time at={occurrence.timestamp} />
                    </div>

                    <div class="mt-3 flex flex-wrap gap-x-5 gap-y-2 text-sm text-zinc-500">
                      <span>
                        User: {occurrence.user_context["email"] || occurrence.user_context["id"] ||
                          "unknown"}
                      </span>
                      <span class="font-mono text-xs text-zinc-500">
                        {occurrence.event_id}
                      </span>
                    </div>
                  </.link>
                </div>
              <% end %>

              <%= if @tab == "tags" do %>
                <div class="space-y-4">
                  <div
                    :for={{key, values} <- @tags}
                    class="border border-zinc-200 bg-slate-50 px-4 py-4"
                  >
                    <p class="text-sm font-semibold text-zinc-900">{key}</p>
                    <div class="mt-3 flex flex-wrap gap-2">
                      <span
                        :for={{value, count} <- values}
                        class="bg-white px-3 py-1 text-xs text-zinc-700 ring-1 ring-zinc-200"
                      >
                        {value} / {count}
                      </span>
                    </div>
                  </div>
                </div>
              <% end %>

              <%= if @tab == "breadcrumbs" do %>
                <%= if @selected_occurrence && query_breadcrumbs(@selected_occurrence) != [] do %>
                  <section id="issue-breadcrumbs" class="space-y-4">
                    <div class="space-y-1">
                      <h2 class="text-lg font-semibold tracking-tight text-zinc-950">Breadcrumbs</h2>
                      <p class="text-sm text-zinc-500">
                        Query breadcrumbs captured before this exception. Expand individual rows when you need more detail.
                      </p>
                    </div>

                    <div class="space-y-3">
                      <details
                        :for={
                          {breadcrumb, index} <-
                            Enum.with_index(query_breadcrumbs(@selected_occurrence))
                        }
                        id={"issue-breadcrumb-#{index}"}
                        class="border border-zinc-200 bg-slate-50"
                      >
                        <summary class="cursor-pointer list-none px-4 py-4">
                          <div class="flex flex-wrap items-start justify-between gap-3">
                            <div class="space-y-1">
                              <div class="flex flex-wrap items-center gap-2">
                                <p class="text-sm font-medium text-zinc-950">
                                  {breadcrumb["message"] || breadcrumb["category"] ||
                                    breadcrumb["type"] ||
                                    "Breadcrumb"}
                                </p>
                                <span
                                  :if={breadcrumb["category"] == "query"}
                                  class="border border-amber-200 bg-amber-50 px-2 py-0.5 text-[11px] font-semibold uppercase tracking-[0.14em] text-amber-700"
                                >
                                  query
                                </span>
                              </div>
                              <p class="font-mono text-xs text-zinc-500">
                                {[breadcrumb["type"], breadcrumb["category"]]
                                |> Enum.reject(&blank?/1)
                                |> Enum.join(" / ")}
                              </p>
                            </div>
                            <p class="text-xs text-zinc-500">
                              {format_breadcrumb_timestamp(breadcrumb["timestamp"])}
                            </p>
                          </div>
                        </summary>

                        <div class="border-t border-zinc-200 bg-white px-4 py-4">
                          <%= if map_size(Map.get(breadcrumb, "data", %{})) > 0 do %>
                            <.structured_entries entries={map_entries(breadcrumb["data"])} />
                          <% else %>
                            <p class="text-sm text-zinc-500">
                              No additional breadcrumb data captured.
                            </p>
                          <% end %>
                        </div>
                      </details>
                    </div>
                  </section>
                <% else %>
                  <.empty_state
                    title="No query breadcrumbs captured"
                    description="This event did not include captured query breadcrumbs."
                    icon="hero-clock"
                  />
                <% end %>
              <% end %>

              <%= if @tab == "context" do %>
                <div class="space-y-6">
                  <div class="grid gap-4 xl:grid-cols-4">
                    <.data_panel
                      title="Runtime"
                      data={@context.runtime}
                      empty_text="No runtime context captured"
                      class="xl:col-span-2"
                    />
                    <.data_panel
                      title="OS"
                      data={@context.os}
                      empty_text="No OS context captured"
                    />
                    <.data_panel
                      title="Browser"
                      data={@context.browser}
                      empty_text="No browser context captured"
                    />
                  </div>

                  <.data_panel
                    title="Trace"
                    data={@context.trace}
                    empty_text="No trace metadata captured"
                  />
                </div>
              <% end %>
            </div>
          </section>
        </div>

        <aside class="space-y-6">
          <section id="issue-assignee-panel" class="border border-zinc-200 bg-white p-5">
            <div class="space-y-1">
              <h2 class="text-[11px] font-semibold uppercase tracking-[0.16em] text-zinc-500">
                Assignee
              </h2>
              <p class="text-sm leading-6 text-zinc-500">
                Route this issue to a single team member, or leave it unassigned to notify the whole project team.
              </p>
            </div>

            <div class="mt-4 space-y-4">
              <div class="border border-zinc-200 bg-slate-50 px-4 py-4">
                <p class="text-sm font-medium text-zinc-950">{assignee_name(@issue.assignee)}</p>
                <p :if={@issue.assignee} class="mt-1 text-sm text-zinc-500">
                  {@issue.assignee.email}
                </p>
                <p :if={is_nil(@issue.assignee)} class="mt-1 text-sm text-zinc-500">
                  New and reappearing issues notify all confirmed team members.
                </p>
              </div>

              <.form
                for={@assignee_form}
                id="issue-assignee-form"
                phx-change="assign-issue"
                class="space-y-4"
              >
                <.input
                  field={@assignee_form[:assignee_id]}
                  type="select"
                  label="Assign to"
                  options={@assignee_options}
                />
              </.form>
            </div>
          </section>

          <%= if @selected_occurrence do %>
            <.data_panel
              id="issue-event-summary-panel"
              title="Event"
              data={event_summary_data(@selected_occurrence, @issue)}
              empty_text="No event metadata captured"
            />
            <.data_panel
              id="issue-user-panel"
              title="User"
              data={occurrence_user(@selected_occurrence)}
              empty_text="No user context captured"
            />
            <.data_panel
              id="issue-request-panel"
              title="Request"
              data={occurrence_request(@selected_occurrence)}
              empty_text="No request captured"
            />
            <.data_panel
              id="issue-sdk-panel"
              title="SDK"
              data={occurrence_sdk(@selected_occurrence)}
              empty_text="No SDK metadata captured"
            />
            <.data_panel
              :if={map_size(occurrence_extra(@selected_occurrence)) > 0}
              id="issue-extra-panel"
              title="Extra"
              data={occurrence_extra(@selected_occurrence)}
              empty_text="No extra metadata captured"
            />
          <% else %>
            <.data_panel
              id="issue-request-panel"
              title="Request"
              data={@issue.request}
              empty_text="No request captured"
            />
            <.data_panel
              id="issue-sdk-panel"
              title="SDK"
              data={@issue.sdk}
              empty_text="No SDK metadata captured"
            />
          <% end %>
        </aside>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"slug" => slug, "id" => id} = params, _session, socket) do
    user = socket.assigns.current_scope.user

    with %{} = project <- Projects.get_project_for_user_by_slug(user, slug),
         %{} = issue <- Projects.get_error_event(project, String.to_integer(id)) do
      if connected?(socket), do: Projects.subscribe_to_issues(project)

      {:ok, assign_page(socket, project, issue, params)}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/projects")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign_page(socket, socket.assigns.project, socket.assigns.issue, params)}
  end

  @impl true
  def handle_event("set-status", %{"status" => status}, socket) do
    {:ok, issue} =
      Projects.update_error_event_status(socket.assigns.issue, String.to_existing_atom(status))

    {:noreply,
     assign_page(socket, socket.assigns.project, issue, %{
       "tab" => socket.assigns.tab,
       "event" => selected_occurrence_id(socket.assigns.selected_occurrence),
       "frames" => socket.assigns.frame_mode
     })}
  end

  def handle_event("assign-issue", %{"assignment" => %{"assignee_id" => assignee_id}}, socket) do
    result =
      case String.trim(assignee_id || "") do
        "" ->
          Projects.unassign_error_event(socket.assigns.current_scope.user, socket.assigns.issue)

        value ->
          Projects.assign_error_event(
            socket.assigns.current_scope.user,
            socket.assigns.issue,
            String.to_integer(value)
          )
      end

    case result do
      {:ok, issue} ->
        {:noreply,
         socket
         |> put_flash(:info, "Issue assignment updated.")
         |> assign_page(socket.assigns.project, issue, %{
           "tab" => socket.assigns.tab,
           "event" => selected_occurrence_id(socket.assigns.selected_occurrence),
           "frames" => socket.assigns.frame_mode
         })}

      {:error, :invalid_assignee} ->
        {:noreply, put_flash(socket, :error, "Selected user cannot be assigned to this issue.")}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "You are not allowed to assign this issue.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not update the issue assignee.")}
    end
  end

  @impl true
  def handle_info({:error_event_updated, error_event}, socket) do
    if error_event.id == socket.assigns.issue.id do
      {:noreply,
       assign_page(
         socket,
         socket.assigns.project,
         Projects.get_error_event(socket.assigns.project, error_event.id),
         %{
           "tab" => socket.assigns.tab,
           "event" => selected_occurrence_id(socket.assigns.selected_occurrence),
           "frames" => socket.assigns.frame_mode
         }
       )}
    else
      {:noreply, socket}
    end
  end

  defp assign_page(socket, project, issue, params) do
    tab = parse_tab(Map.get(params, "tab", "event"))
    frame_mode = parse_frame_mode(Map.get(params, "frames", "in_app"))
    occurrences = Projects.list_all_occurrences(issue)
    selected_occurrence = selected_occurrence(occurrences, Map.get(params, "event"))
    selected_occurrence_position = selected_occurrence_position(occurrences, selected_occurrence)

    {newer_occurrence, older_occurrence} =
      surrounding_occurrences(occurrences, selected_occurrence)

    socket
    |> assign(:project, project)
    |> assign(:issue, issue)
    |> assign(:sidebar, AppShell.build(socket.assigns.current_scope.user, project: project))
    |> assign(:tab, tab)
    |> assign(:frame_mode, frame_mode)
    |> assign(:all_occurrences, occurrences)
    |> assign(:occurrence_count, length(occurrences))
    |> assign(:selected_occurrence, selected_occurrence)
    |> assign(:selected_occurrence_position, selected_occurrence_position)
    |> assign(:newer_occurrence, newer_occurrence)
    |> assign(:older_occurrence, older_occurrence)
    |> assign(:assignee_options, assignee_options(project))
    |> assign(:assignee_form, assignee_form(issue))
    |> assign(:tags, Projects.aggregate_tags(issue))
    |> assign(:context, context_summary(selected_occurrence, issue))
  end

  defp parse_tab(tab) when tab in ~w(event events tags breadcrumbs context), do: tab
  defp parse_tab(_tab), do: "event"

  defp parse_frame_mode(mode) when mode in ~w(in_app all), do: mode
  defp parse_frame_mode(_mode), do: "in_app"

  defp selected_occurrence([], _param), do: nil
  defp selected_occurrence(occurrences, nil), do: List.first(occurrences)

  defp selected_occurrence(occurrences, occurrence_id) when is_integer(occurrence_id),
    do: Enum.find(occurrences, &(&1.id == occurrence_id)) || List.first(occurrences)

  defp selected_occurrence(occurrences, occurrence_id) when is_binary(occurrence_id) do
    Enum.find(occurrences, &(&1.id == String.to_integer(occurrence_id))) ||
      List.first(occurrences)
  end

  defp selected_occurrence_id(nil), do: nil
  defp selected_occurrence_id(occurrence), do: occurrence.id

  defp selected_occurrence_position(_occurrences, nil), do: 0

  defp selected_occurrence_position(occurrences, occurrence) do
    occurrences
    |> Enum.find_index(&(&1.id == occurrence.id))
    |> case do
      nil -> 0
      index -> index + 1
    end
  end

  defp surrounding_occurrences(_occurrences, nil), do: {nil, nil}

  defp surrounding_occurrences(occurrences, occurrence) do
    index = Enum.find_index(occurrences, &(&1.id == occurrence.id)) || 0

    {
      if(index > 0, do: Enum.at(occurrences, index - 1)),
      Enum.at(occurrences, index + 1)
    }
  end

  defp issue_patch(project, issue, tab, nil, frame_mode),
    do: ~p"/projects/#{project.slug}/issues/#{issue.id}?tab=#{tab}&frames=#{frame_mode}"

  defp issue_patch(project, issue, tab, occurrence_id, frame_mode),
    do:
      ~p"/projects/#{project.slug}/issues/#{issue.id}?tab=#{tab}&event=#{occurrence_id}&frames=#{frame_mode}"

  defp tab_class(true),
    do: "border-b-2 border-zinc-950 px-0 pb-3 text-sm font-medium text-zinc-950"

  defp tab_class(false),
    do:
      "border-b-2 border-transparent px-0 pb-3 text-sm text-zinc-500 transition hover:border-zinc-300 hover:text-zinc-900"

  attr :frame, :map, required: true
  attr :index, :integer, required: true
  attr :selected, :boolean, default: false

  defp frame_card(assigns) do
    ~H"""
    <details
      id={"issue-frame-#{@index}"}
      open={@selected}
      class={[
        "border transition",
        @selected && "border-sky-200 bg-sky-50/60",
        !@selected && "border-zinc-200 bg-white"
      ]}
    >
      <summary class="cursor-pointer list-none px-4 py-4">
        <div class="flex flex-wrap items-start justify-between gap-4">
          <div class="space-y-1">
            <div class="flex flex-wrap items-center gap-2">
              <p class="text-sm font-semibold text-zinc-950">
                {@frame["function"] || @frame["module"] || "anonymous"}
              </p>
              <span
                :if={@frame["in_app"]}
                class="border border-sky-200 bg-sky-50 px-2 py-0.5 text-[11px] font-semibold uppercase tracking-[0.14em] text-sky-700"
              >
                in app
              </span>
            </div>
            <p class="font-mono text-xs text-zinc-500">{frame_location(@frame)}</p>
          </div>

          <span :if={@selected} class="text-xs font-medium uppercase tracking-[0.14em] text-sky-700">
            selected frame
          </span>
        </div>
      </summary>

      <div class="border-t border-zinc-200 px-4 py-4">
        <div class="space-y-4">
          <div
            :if={code_context(@frame) != []}
            class="overflow-x-auto border border-zinc-900 bg-zinc-950"
          >
            <div
              :for={line <- code_context(@frame)}
              class={[
                "grid grid-cols-[56px_minmax(0,1fr)] gap-4 px-4 py-1.5 font-mono text-xs text-zinc-200",
                line.current && "bg-sky-500/15"
              ]}
            >
              <span class={[
                "text-right text-zinc-500",
                line.current && "text-sky-300"
              ]}>
                {line.number}
              </span>
              <code class="whitespace-pre-wrap break-words">{line.text}</code>
            </div>
          </div>

          <div :if={map_size(frame_vars(@frame)) > 0} class="border border-zinc-200 bg-white p-4">
            <div class="space-y-1">
              <h3 class="text-sm font-semibold text-zinc-950">Local variables</h3>
              <p class="text-sm text-zinc-500">Captured variables for this frame.</p>
            </div>

            <div class="mt-4 space-y-3">
              <div :for={{key, value} <- map_entries(frame_vars(@frame))} class="space-y-1">
                <p class="text-[11px] font-semibold uppercase tracking-[0.14em] text-zinc-500">
                  {labelize(key)}
                </p>
                <p class="break-words font-mono text-xs leading-6 text-zinc-700">
                  {format_value(value)}
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </details>
    """
  end

  attr :id, :string, default: nil
  attr :title, :string, required: true
  attr :data, :map, default: %{}
  attr :empty_text, :string, required: true
  attr :class, :string, default: nil

  defp data_panel(assigns) do
    ~H"""
    <section id={@id} class={["border border-zinc-200 bg-white p-5", @class]}>
      <h2 class="text-[11px] font-semibold uppercase tracking-[0.16em] text-zinc-500">{@title}</h2>

      <%= if map_size(@data || %{}) == 0 do %>
        <p class="mt-4 text-sm leading-6 text-zinc-500">{@empty_text}</p>
      <% else %>
        <div class="mt-4">
          <.structured_entries entries={map_entries(@data)} />
        </div>
      <% end %>
    </section>
    """
  end

  attr :entries, :list, required: true

  defp structured_entries(assigns) do
    ~H"""
    <div class="space-y-3">
      <div :for={{key, value} <- @entries} class="space-y-2">
        <%= cond do %>
          <% is_map(value) and map_size(value) > 0 -> %>
            <details class="border border-zinc-200 bg-slate-50">
              <summary class="cursor-pointer list-none px-4 py-3 text-sm font-medium text-zinc-800">
                {labelize(key)}
              </summary>
              <div class="border-t border-zinc-200 px-4 py-4">
                <.structured_entries entries={map_entries(value)} />
              </div>
            </details>
          <% is_list(value) and value != [] -> %>
            <details class="border border-zinc-200 bg-slate-50">
              <summary class="cursor-pointer list-none px-4 py-3 text-sm font-medium text-zinc-800">
                {labelize(key)} / {length(value)} items
              </summary>
              <div class="border-t border-zinc-200 px-4 py-4">
                <%= if Enum.all?(value, &is_map/1) do %>
                  <div class="space-y-3">
                    <div :for={item <- value} class="border border-zinc-200 bg-white px-4 py-4">
                      <.structured_entries entries={map_entries(item)} />
                    </div>
                  </div>
                <% else %>
                  <ul class="space-y-2 text-sm text-zinc-700">
                    <li :for={item <- value}>{format_value(item)}</li>
                  </ul>
                <% end %>
              </div>
            </details>
          <% true -> %>
            <div class="grid gap-1 sm:grid-cols-[112px_minmax(0,1fr)] sm:gap-4">
              <p class="text-[11px] font-semibold uppercase tracking-[0.14em] text-zinc-500">
                {labelize(key)}
              </p>
              <p class={value_text_class(value)} title={format_value(value)}>{format_value(value)}</p>
            </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp event_summary_data(occurrence, issue) do
    payload = occurrence.raw_payload || %{}
    exception = List.first(occurrence.exception_values) || %{}

    %{
      "event_id" => occurrence.event_id,
      "environment" => payload["environment"],
      "release" => payload["release"],
      "transaction" => payload["transaction"] || issue.culprit,
      "server_name" => payload["server_name"],
      "platform" => payload["platform"] || issue.platform,
      "mechanism" => get_in(exception, ["mechanism", "type"]),
      "handled" => handled_exception?(occurrence),
      "modules" => payload["modules"] |> modules_count()
    }
    |> Enum.reject(fn {_key, value} -> blank?(value) end)
    |> Map.new()
  end

  defp event_headline_meta(occurrence, issue) do
    payload = occurrence.raw_payload || %{}

    [
      {"environment", payload["environment"]},
      {"release", payload["release"]},
      {"transaction", payload["transaction"] || issue.culprit},
      {"server", payload["server_name"]},
      {"platform", payload["platform"] || issue.platform}
    ]
    |> Enum.reject(fn {_label, value} -> blank?(value) end)
  end

  defp occurrence_user(occurrence) do
    occurrence.raw_payload
    |> Map.get("user", occurrence.user_context || %{})
    |> normalize_map()
  end

  defp occurrence_request(occurrence) do
    occurrence.raw_payload
    |> Map.get("request", %{})
    |> normalize_map()
  end

  defp occurrence_sdk(occurrence) do
    occurrence.raw_payload
    |> Map.get("sdk", %{})
    |> normalize_map()
  end

  defp occurrence_extra(occurrence) do
    occurrence.raw_payload
    |> Map.get("extra", %{})
    |> normalize_map()
  end

  defp context_summary(nil, issue) do
    contexts = issue.contexts || %{}

    %{
      runtime: contexts["runtime"] || %{},
      os: contexts["os"] || %{},
      browser: contexts["browser"] || %{},
      trace: contexts["trace"] || %{}
    }
  end

  defp context_summary(occurrence, _issue) do
    contexts =
      occurrence.raw_payload
      |> Map.get("contexts", %{})
      |> normalize_map()

    %{
      runtime: contexts["runtime"] || %{},
      os: contexts["os"] || %{},
      browser: contexts["browser"] || %{},
      trace: contexts["trace"] || %{}
    }
  end

  defp primary_exception_title(occurrence) do
    with [%{} = exception | _] <- occurrence.exception_values do
      [exception["type"], exception["value"]]
      |> Enum.reject(&blank?/1)
      |> Enum.join(": ")
    else
      _ -> nil
    end
  end

  defp handled_exception?(occurrence) do
    occurrence.exception_values
    |> List.first()
    |> get_in(["mechanism", "handled"])
    |> case do
      nil -> false
      value -> value
    end
  end

  defp stack_frames(exception) do
    exception
    |> get_in(["stacktrace", "frames"])
    |> case do
      frames when is_list(frames) -> Enum.reverse(frames)
      _ -> []
    end
  end

  defp visible_stack_frames(frames, "all"), do: frames

  defp visible_stack_frames(frames, "in_app") do
    in_app_frames = Enum.filter(frames, & &1["in_app"])
    if in_app_frames == [], do: frames, else: in_app_frames
  end

  defp toggleable_frames?(frames) do
    in_app_count = Enum.count(frames, & &1["in_app"])
    in_app_count > 0 and in_app_count < length(frames)
  end

  defp frame_scope_note(frames, frame_mode) do
    in_app_count = Enum.count(frames, & &1["in_app"])
    total_count = length(frames)

    cond do
      total_count == 0 ->
        "No frames captured."

      frame_mode == "all" ->
        "Showing all #{total_count} frames."

      in_app_count == 0 ->
        "No in-app frames captured. Showing all #{total_count} frames."

      true ->
        "Showing #{in_app_count} in-app frames out of #{total_count} total."
    end
  end

  defp selected_frame_index([]), do: 0

  defp selected_frame_index(frames) do
    Enum.find_index(frames, fn frame -> frame["in_app"] end) || 0
  end

  defp frame_location(frame) do
    [
      frame["module"] || frame["filename"],
      frame["function"],
      frame["lineno"] && "line #{frame["lineno"]}"
    ]
    |> Enum.reject(&blank?/1)
    |> Enum.join(" / ")
  end

  defp code_context(frame) do
    pre_context = frame["pre_context"] || []
    post_context = frame["post_context"] || []

    lines =
      case frame["context_line"] do
        nil -> pre_context ++ post_context
        context_line -> pre_context ++ [context_line] ++ post_context
      end

    start_line = max((frame["lineno"] || 1) - length(pre_context), 1)
    current_line = frame["lineno"]

    lines
    |> Enum.with_index(start_line)
    |> Enum.map(fn {text, number} ->
      %{text: text, number: number, current: current_line == number}
    end)
  end

  defp frame_vars(frame) do
    frame
    |> Map.get("vars", %{})
    |> normalize_map()
  end

  defp format_breadcrumb_timestamp(nil), do: "Unknown time"

  defp format_breadcrumb_timestamp(value) do
    case DateTime.from_iso8601(value) do
      {:ok, timestamp, _offset} -> Calendar.strftime(timestamp, "%H:%M:%S")
      _ -> value
    end
  end

  defp query_breadcrumbs(occurrence) do
    occurrence.breadcrumbs
    |> Enum.filter(&query_breadcrumb?/1)
  end

  defp query_breadcrumb?(breadcrumb) do
    category = Map.get(breadcrumb, "category")
    type = Map.get(breadcrumb, "type")

    category == "query" ||
      type == "query" ||
      (is_binary(category) && String.contains?(category, "query"))
  end

  defp modules_count(modules) when is_map(modules), do: map_size(modules)
  defp modules_count(_modules), do: nil

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

  defp blank?(value), do: value in [nil, "", []]

  defp assignee_options(project) do
    [{"Unassigned", ""}] ++
      Enum.map(Projects.list_assignable_users(project), fn user ->
        {"#{user.name} <#{user.email}>", Integer.to_string(user.id)}
      end)
  end

  defp assignee_form(issue) do
    to_form(
      %{"assignee_id" => (issue.assignee_id && Integer.to_string(issue.assignee_id)) || ""},
      as: :assignment
    )
  end

  defp assignee_name(nil), do: "Unassigned"
  defp assignee_name(assignee), do: assignee.name
end
