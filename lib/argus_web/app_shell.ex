defmodule ArgusWeb.AppShell do
  @moduledoc """
  Builds the shared navigation state for authenticated LiveViews.

  Sidebar options depend on the current user, team membership, and active project. Building that
  state on the server keeps the menu in sync with permissions and the latest database state.
  """
  use ArgusWeb, :verified_routes

  alias Argus.Projects
  alias Argus.Teams

  def build(user, opts \\ []) do
    teams = Teams.list_teams_for_user(user)
    active_project = Keyword.get(opts, :project)

    active_team =
      Keyword.get(opts, :team) ||
        (active_project && active_project.team) ||
        List.first(teams)

    projects =
      if active_team do
        Projects.list_projects_for_team(user, active_team)
      else
        []
      end

    team_targets =
      Map.new(teams, fn team ->
        {team.id, ~p"/projects?team_id=#{team.id}"}
      end)

    %{
      teams: teams,
      active_team: active_team,
      projects: projects,
      active_project: active_project,
      team_targets: team_targets
    }
  end
end
