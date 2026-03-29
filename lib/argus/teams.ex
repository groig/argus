defmodule Argus.Teams do
  @moduledoc """
  Team ownership and membership rules.

  Teams are the main access boundary in Argus. Projects belong to teams, and project data is
  visible through team membership. Keeping those rules here avoids repeating the same ownership
  checks in every LiveView.
  """

  import Ecto.Query, warn: false

  alias Argus.Accounts.User
  alias Argus.Projects
  alias Argus.Repo
  alias Argus.Teams.{Team, TeamMember}

  def list_teams do
    Repo.all(from team in Team, order_by: [asc: team.name], preload: [team_members: :user])
  end

  def list_teams_for_user(%User{role: :admin}) do
    list_teams()
  end

  def list_teams_for_user(%User{id: user_id}) do
    Repo.all(
      from team in Team,
        join: team_member in assoc(team, :team_members),
        where: team_member.user_id == ^user_id,
        distinct: team.id,
        order_by: [asc: team.name],
        preload: [team_members: :user]
    )
  end

  def get_team!(id), do: Repo.get!(Team, id) |> Repo.preload(team_members: :user)

  def get_team_for_user(nil, _id), do: nil

  def get_team_for_user(%User{role: :admin}, id),
    do: Repo.get(Team, id) |> Repo.preload(team_members: :user)

  def get_team_for_user(%User{id: user_id}, id) do
    Repo.one(
      from team in Team,
        join: team_member in assoc(team, :team_members),
        where: team.id == ^id and team_member.user_id == ^user_id,
        preload: [team_members: :user]
    )
  end

  def create_team(attrs) do
    %Team{}
    |> Team.changeset(attrs)
    |> Repo.insert()
  end

  def add_member(%Team{} = team, %User{} = user, role \\ :member) do
    %TeamMember{}
    |> TeamMember.changeset(%{team_id: team.id, user_id: user.id, role: role})
    |> Repo.insert(
      on_conflict: {:replace, [:role, :updated_at]},
      conflict_target: [:user_id, :team_id]
    )
  end

  def update_member_role(%TeamMember{} = team_member, role) do
    team_member
    |> TeamMember.changeset(%{role: role})
    |> Repo.update()
  end

  def remove_member(%Team{} = team, user_id) do
    {count, _} =
      Repo.delete_all(
        from team_member in TeamMember,
          where: team_member.team_id == ^team.id and team_member.user_id == ^user_id
      )

    Projects.unassign_error_events_for_team_member(team, user_id)

    {count, nil}
  end

  def list_members(%Team{} = team) do
    Repo.all(
      from team_member in TeamMember,
        where: team_member.team_id == ^team.id,
        order_by: [asc: team_member.role, asc: team_member.user_id],
        preload: [:user]
    )
  end

  def member_role(%User{role: :admin}, %Team{}), do: :admin

  def member_role(%User{id: user_id}, %Team{id: team_id}) do
    Repo.one(
      from team_member in TeamMember,
        where: team_member.team_id == ^team_id and team_member.user_id == ^user_id,
        select: team_member.role
    )
  end

  def team_admin?(%User{} = user, %Team{} = team), do: member_role(user, team) == :admin
  def team_admin?(_, _), do: false
end
