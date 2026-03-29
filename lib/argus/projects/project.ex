defmodule Argus.Projects.Project do
  use Ecto.Schema
  import Ecto.Changeset

  @default_log_limit 1_000

  schema "projects" do
    field :name, :string
    field :slug, :string
    field :dsn_key, :string
    field :log_limit, :integer, default: @default_log_limit

    belongs_to :team, Argus.Teams.Team
    has_many :error_events, Argus.Projects.ErrorEvent
    has_many :log_events, Argus.Logs.LogEvent

    timestamps(type: :utc_datetime)
  end

  def default_log_limit, do: @default_log_limit

  def changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :slug, :dsn_key, :team_id, :log_limit])
    |> validate_required([:name, :slug, :dsn_key, :team_id, :log_limit])
    |> validate_length(:name, min: 2, max: 80)
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/)
    |> validate_length(:slug, min: 2, max: 80)
    |> validate_number(:log_limit, greater_than_or_equal_to: 1)
    |> unique_constraint(:slug)
    |> unique_constraint(:dsn_key)
  end
end
