defmodule ArgusWeb.ProjectLive.Settings do
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
        {@project.name}
        <:subtitle>
          Project identifiers, ingestion credentials, and settings for {@project.team.name}.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/projects/#{@project.slug}/issues"} variant="secondary">
            Issues
          </.button>
          <.button navigate={~p"/projects/#{@project.slug}/logs"} variant="secondary">
            Logs
          </.button>
          <.button navigate={~p"/teams/#{@project.team.id}/settings?tab=projects"} variant="ghost">
            Team settings
          </.button>
        </:actions>
      </.header>

      <section class="grid gap-6 xl:grid-cols-[1.05fr_0.95fr]">
        <div class="space-y-6">
          <section class="border border-zinc-200 bg-white p-6">
            <div class="grid gap-4 sm:grid-cols-2">
              <div class="border border-zinc-200 bg-slate-50 px-4 py-4">
                <p class="text-[11px] font-semibold uppercase tracking-[0.16em] text-zinc-500">
                  Slug
                </p>
                <p class="mt-2 font-mono text-sm font-semibold text-zinc-950">{@project.slug}</p>
              </div>

              <div class="border border-zinc-200 bg-slate-50 px-4 py-4">
                <p class="text-[11px] font-semibold uppercase tracking-[0.16em] text-zinc-500">
                  Created
                </p>
                <div class="mt-2">
                  <.relative_time
                    at={@project.inserted_at}
                    class="text-base font-medium text-zinc-950"
                  />
                </div>
              </div>

              <div class="border border-zinc-200 bg-slate-50 px-4 py-4">
                <p class="text-[11px] font-semibold uppercase tracking-[0.16em] text-zinc-500">
                  Grouped issues
                </p>
                <p class="mt-2 text-3xl font-semibold tracking-tight text-zinc-950">
                  {@stats.issue_count}
                </p>
              </div>

              <div class="border border-zinc-200 bg-slate-50 px-4 py-4">
                <p class="text-[11px] font-semibold uppercase tracking-[0.16em] text-zinc-500">
                  Stored logs
                </p>
                <p class="mt-2 text-3xl font-semibold tracking-tight text-zinc-950">
                  {@stats.log_count}
                </p>
              </div>

              <div class="border border-zinc-200 bg-slate-50 px-4 py-4">
                <p class="text-[11px] font-semibold uppercase tracking-[0.16em] text-zinc-500">
                  Log limit
                </p>
                <p class="mt-2 text-3xl font-semibold tracking-tight text-zinc-950">
                  {@project.log_limit}
                </p>
              </div>
            </div>

            <div class="mt-6 space-y-4 border-t border-zinc-200 pt-6">
              <div>
                <p class="text-[11px] font-semibold uppercase tracking-[0.16em] text-zinc-500">DSN</p>
                <div class="mt-2">
                  <.copy_to_clipboard
                    value={Projects.issue_dsn(@project)}
                    toast_message="DSN copied"
                  />
                </div>
              </div>

              <div>
                <p class="text-[11px] font-semibold uppercase tracking-[0.16em] text-zinc-500">
                  DSN key
                </p>
                <div class="mt-2">
                  <.copy_to_clipboard value={@project.dsn_key} toast_message="DSN key copied" />
                </div>
              </div>
            </div>
          </section>

          <section class="border border-zinc-200 bg-white p-6">
            <div class="flex items-start justify-between gap-4">
              <div>
                <h2 class="text-lg font-semibold tracking-tight text-zinc-950">Danger zone</h2>
                <p class="mt-1 text-sm text-zinc-500">
                  Deleting a project removes its grouped issues, raw events, and stored logs.
                </p>
              </div>
            </div>

            <div class="mt-6 flex items-center justify-between gap-4 border border-red-200 bg-red-50/70 px-4 py-4">
              <div>
                <p class="text-sm font-medium text-zinc-950">Delete this project</p>
                <p class="mt-1 text-sm text-zinc-600">
                  This action is permanent and cannot be undone.
                </p>
              </div>

              <.button
                id="delete-project-button"
                type="button"
                variant="danger"
                phx-click="confirm-delete-project"
              >
                Delete project
              </.button>
            </div>
          </section>
        </div>

        <div class="space-y-6">
          <section class="border border-zinc-200 bg-white p-6">
            <div class="space-y-1">
              <h2 class="text-lg font-semibold tracking-tight text-zinc-950">Project settings</h2>
              <p class="text-sm text-zinc-500">
                Update the public name, the slug used in project URLs, and the maximum stored logs for this project.
              </p>
            </div>

            <.form
              for={@project_form}
              id="project-edit-form"
              phx-change="validate-project"
              phx-submit="update-project"
              class="mt-6 space-y-5"
            >
              <.input
                id="edit-project-name"
                field={@project_form[:name]}
                type="text"
                label="Project name"
                required
              />
              <.input
                id="edit-project-slug"
                field={@project_form[:slug]}
                type="text"
                label="Slug"
                required
              />
              <.input
                id="edit-project-log-limit"
                field={@project_form[:log_limit]}
                type="number"
                label="Stored log limit"
                min="1"
                required
              />

              <div class="flex justify-end">
                <.button>Save changes</.button>
              </div>
            </.form>
          </section>
        </div>
      </section>

      <.modal id="delete-project-modal" open={@delete_project_modal_open} title="Delete project">
        This will permanently remove {@project.name} together with its grouped issues, raw events, and stored logs.
        <:actions>
          <.button type="button" variant="ghost" phx-click="cancel-delete-project">Cancel</.button>
          <.button
            id="confirm-delete-project"
            type="button"
            variant="danger"
            phx-click="delete-project"
          >
            Delete project
          </.button>
        </:actions>
      </.modal>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    user = socket.assigns.current_scope.user

    case Projects.get_project_for_user_by_slug(user, slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/projects")}

      project ->
        if user.role == :admin || Teams.team_admin?(user, project.team) do
          {:ok, assign_page(socket, project)}
        else
          {:ok, push_navigate(socket, to: ArgusWeb.UserAuth.signed_in_path(user))}
        end
    end
  end

  @impl true
  def handle_event("validate-project", %{"project" => params}, socket) do
    form =
      socket.assigns.project
      |> Projects.change_project(params)
      |> Map.put(:action, :validate)
      |> to_form(as: :project)

    {:noreply, assign(socket, :project_form, form)}
  end

  def handle_event("update-project", %{"project" => params}, socket) do
    case Projects.update_project(socket.assigns.project, params) do
      {:ok, project} ->
        {:noreply,
         socket
         |> put_flash(:info, "Project updated.")
         |> push_navigate(to: ~p"/projects/#{project.slug}/settings")}

      {:error, changeset} ->
        {:noreply, assign(socket, :project_form, to_form(changeset, as: :project))}
    end
  end

  def handle_event("confirm-delete-project", _params, socket) do
    {:noreply, assign(socket, :delete_project_modal_open, true)}
  end

  def handle_event("cancel-delete-project", _params, socket) do
    {:noreply, assign(socket, :delete_project_modal_open, false)}
  end

  def handle_event("delete-project", _params, socket) do
    case Projects.delete_project(socket.assigns.project) do
      {:ok, _project} ->
        {:noreply,
         socket
         |> put_flash(:info, "Project deleted.")
         |> push_navigate(to: ~p"/teams/#{socket.assigns.project.team.id}/settings?tab=projects")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> assign(:delete_project_modal_open, false)
         |> put_flash(:error, "Project could not be deleted.")}
    end
  end

  defp assign_page(socket, project) do
    stats =
      [project]
      |> Projects.project_stats()
      |> Map.get(project.id, @empty_stats)

    socket
    |> assign(:project, project)
    |> assign(:stats, stats)
    |> assign(:sidebar, AppShell.build(socket.assigns.current_scope.user, project: project))
    |> assign(:delete_project_modal_open, false)
    |> assign(:project_form, to_form(Projects.change_project(project), as: :project))
  end
end
