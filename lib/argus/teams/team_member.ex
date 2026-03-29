defmodule Argus.Teams.TeamMember do
  use Ecto.Schema
  import Ecto.Changeset

  schema "team_members" do
    field :role, Ecto.Enum, values: [:admin, :member], default: :member

    belongs_to :user, Argus.Accounts.User
    belongs_to :team, Argus.Teams.Team

    timestamps(type: :utc_datetime)
  end

  def changeset(team_member, attrs) do
    team_member
    |> cast(attrs, [:user_id, :team_id, :role])
    |> validate_required([:user_id, :team_id, :role])
    |> unique_constraint([:user_id, :team_id])
  end
end
