defmodule ArgusWeb.Layouts do
  @moduledoc false
  use ArgusWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :sidebar, :map, default: nil
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <%= if @current_scope && @current_scope.user && @sidebar do %>
      <div class="min-h-screen bg-slate-100 text-zinc-900">
        <div class="flex min-h-screen">
          <aside class="hidden w-72 shrink-0 border-r border-zinc-900 bg-zinc-950 px-5 py-5 text-zinc-100 lg:flex lg:flex-col">
            <div class="border-b border-zinc-900/80 pb-5">
              <.link
                navigate={ArgusWeb.UserAuth.signed_in_path(@current_scope.user)}
                class="flex items-center gap-3"
              >
                <div class="flex h-9 w-9 items-center justify-center border border-sky-500/30 bg-sky-500/12 text-sm font-semibold text-sky-300">
                  A
                </div>
                <div class="space-y-0.5">
                  <p class="text-[11px] font-semibold uppercase tracking-[0.24em] text-zinc-500">
                    Argus
                  </p>
                  <p class="text-sm font-medium text-zinc-100">
                    {active_team_name(@sidebar) || "Overview"}
                  </p>
                </div>
              </.link>
            </div>

            <div :if={length(@sidebar.teams) > 1} class="mt-8 space-y-2">
              <p class="text-[10px] font-medium uppercase tracking-[0.18em] text-zinc-600">Teams</p>
              <div class="space-y-1">
                <.link
                  :for={team <- @sidebar.teams}
                  navigate={Map.get(@sidebar.team_targets, team.id)}
                  class={[
                    "flex items-center justify-between border-l-2 px-3 py-2 text-sm transition",
                    @sidebar.active_team && @sidebar.active_team.id == team.id &&
                      "border-sky-400 bg-zinc-900 text-white",
                    @sidebar.active_team && @sidebar.active_team.id != team.id &&
                      "border-transparent text-zinc-400 hover:border-zinc-700 hover:bg-zinc-900 hover:text-zinc-100"
                  ]}
                >
                  <span class={[
                    @sidebar.active_team && @sidebar.active_team.id == team.id && "font-medium"
                  ]}>
                    {team.name}
                  </span>
                  <.icon
                    :if={@sidebar.active_team && @sidebar.active_team.id == team.id}
                    name="hero-check-mini"
                    class="size-4 text-sky-300"
                  />
                </.link>
              </div>
            </div>

            <div class="mt-8 flex-1 space-y-2">
              <div :if={@sidebar.active_team} class="space-y-1">
                <.link
                  navigate={~p"/projects?team_id=#{@sidebar.active_team.id}"}
                  class={[
                    "flex items-center gap-3 border-l-2 px-3 py-2 text-sm transition",
                    is_nil(@sidebar.active_project) &&
                      "border-sky-400 bg-zinc-900 font-medium text-white",
                    !is_nil(@sidebar.active_project) &&
                      "border-transparent text-zinc-400 hover:border-zinc-700 hover:bg-zinc-900 hover:text-zinc-100"
                  ]}
                >
                  <.icon name="hero-squares-2x2-mini" class="size-4 shrink-0" />
                  <span>Overview</span>
                </.link>
              </div>

              <p class="text-[10px] font-medium uppercase tracking-[0.18em] text-zinc-600">
                Projects
              </p>
              <div
                :if={@sidebar.projects == []}
                class="border border-zinc-800 bg-zinc-900/60 px-3 py-4 text-sm text-zinc-500"
              >
                No projects yet.
              </div>
              <div :if={@sidebar.projects != []} class="space-y-1">
                <.link
                  :for={project <- @sidebar.projects}
                  navigate={~p"/projects/#{project.slug}/issues"}
                  class={[
                    "flex items-center gap-3 border-l-2 pl-5 pr-3 py-2 text-sm transition",
                    @sidebar.active_project && @sidebar.active_project.id == project.id &&
                      "border-sky-400 bg-zinc-50 font-medium text-zinc-950",
                    (!@sidebar.active_project || @sidebar.active_project.id != project.id) &&
                      "border-transparent text-zinc-400 hover:border-zinc-700 hover:bg-zinc-900 hover:text-zinc-100"
                  ]}
                >
                  <div class={[
                    "flex h-5 w-5 shrink-0 items-center justify-center rounded-[4px] border text-[10px] font-semibold uppercase",
                    project_icon_tone(project)
                  ]}>
                    {project_initial(project)}
                  </div>
                  <span class="truncate">{project.name}</span>
                </.link>
              </div>
            </div>

            <div class="border-t border-zinc-800 pt-4">
              <details class="group relative">
                <summary class="flex w-full list-none cursor-pointer items-center gap-3 border border-transparent px-2 py-2 text-left transition hover:border-zinc-800 hover:bg-zinc-900 [&::-webkit-details-marker]:hidden">
                  <div class="flex h-10 w-10 items-center justify-center bg-zinc-800 text-sm font-semibold uppercase text-zinc-100">
                    {String.first(@current_scope.user.name || @current_scope.user.email)}
                  </div>
                  <div class="min-w-0 flex-1">
                    <p class="truncate text-sm font-medium text-zinc-50">
                      {@current_scope.user.name}
                    </p>
                    <p class="truncate text-xs text-zinc-500">{@current_scope.user.email}</p>
                  </div>
                  <.icon
                    name="hero-chevron-up-down-mini"
                    class="size-4 shrink-0 text-zinc-500 transition group-open:text-zinc-300"
                  />
                </summary>

                <div class="absolute bottom-full left-0 z-30 mb-3 w-60 border border-zinc-800 bg-zinc-950 p-1.5 shadow-[0_18px_48px_rgba(15,23,42,0.35)]">
                  <.link
                    navigate={~p"/settings"}
                    class="flex items-center gap-3 px-3 py-2 text-sm text-zinc-300 transition hover:bg-zinc-900 hover:text-white"
                  >
                    <.icon name="hero-cog-6-tooth-mini" class="size-4 shrink-0 text-zinc-500" />
                    <span>Settings</span>
                  </.link>
                  <.link
                    :if={@current_scope.user.role == :admin}
                    navigate={~p"/admin"}
                    class="flex items-center gap-3 px-3 py-2 text-sm text-zinc-300 transition hover:bg-zinc-900 hover:text-white"
                  >
                    <.icon name="hero-shield-check-mini" class="size-4 shrink-0 text-zinc-500" />
                    <span>Admin</span>
                  </.link>
                  <.link
                    href={~p"/logout"}
                    method="delete"
                    class="flex items-center gap-3 px-3 py-2 text-sm text-zinc-300 transition hover:bg-zinc-900 hover:text-white"
                  >
                    <.icon
                      name="hero-arrow-left-start-on-rectangle-mini"
                      class="size-4 shrink-0 text-zinc-500"
                    />
                    <span>Log out</span>
                  </.link>
                </div>
              </details>
            </div>
          </aside>

          <main class="min-w-0 flex-1 bg-slate-100 px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
            <div class="w-full space-y-8">
              {render_slot(@inner_block)}
            </div>
          </main>
        </div>
      </div>
    <% else %>
      <main class="flex min-h-screen items-center justify-center bg-slate-100 px-6 py-12">
        <div class="w-full max-w-lg">{render_slot(@inner_block)}</div>
      </main>
    <% end %>

    <.flash_group flash={@flash} />
    """
  end

  defp active_team_name(%{active_team: %{name: name}}), do: name
  defp active_team_name(_sidebar), do: nil

  defp project_initial(%{name: name}) when is_binary(name) do
    name
    |> String.trim()
    |> String.first()
    |> case do
      nil -> "?"
      initial -> String.upcase(initial)
    end
  end

  defp project_initial(_project), do: "?"

  defp project_icon_tone(project) do
    case rem(:erlang.phash2({project.slug, project.name}), 6) do
      0 -> "border-sky-500/30 bg-sky-500/12 text-sky-300"
      1 -> "border-emerald-500/30 bg-emerald-500/12 text-emerald-300"
      2 -> "border-amber-500/30 bg-amber-500/12 text-amber-300"
      3 -> "border-rose-500/30 bg-rose-500/12 text-rose-300"
      4 -> "border-violet-500/30 bg-violet-500/12 text-violet-300"
      _ -> "border-cyan-500/30 bg-cyan-500/12 text-cyan-300"
    end
  end

  attr :flash, :map, required: true
  attr :id, :string, default: "flash-group"

  def flash_group(assigns) do
    ~H"""
    <div
      id={@id}
      aria-live="polite"
      class="pointer-events-none fixed right-4 top-4 z-50 flex w-full max-w-sm flex-col gap-3"
    >
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("Connection lost")}
        phx-disconnected={show("#client-error")}
        phx-connected={hide("#client-error")}
        hidden
      >
        {gettext("Attempting to reconnect")}
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong")}
        phx-disconnected={show("#server-error")}
        phx-connected={hide("#server-error")}
        hidden
      >
        {gettext("Attempting to reconnect")}
      </.flash>

      <div id="client-toasts" phx-hook="ToastViewport" phx-update="ignore"></div>
    </div>
    """
  end
end
