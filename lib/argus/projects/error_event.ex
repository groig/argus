defmodule Argus.Projects.ErrorEvent do
  use Ecto.Schema
  import Ecto.Changeset

  schema "error_events" do
    field :fingerprint, :string
    field :title, :string
    field :culprit, :string
    field :level, Ecto.Enum, values: [:error, :warning, :info], default: :error
    field :platform, :string
    field :sdk, :map, default: %{}
    field :request, :map, default: %{}
    field :contexts, :map, default: %{}
    field :tags, :map, default: %{}
    field :extra, :map, default: %{}
    field :first_seen_at, :utc_datetime
    field :last_seen_at, :utc_datetime
    field :occurrence_count, :integer, default: 1
    field :status, Ecto.Enum, values: [:unresolved, :resolved, :ignored], default: :unresolved

    belongs_to :project, Argus.Projects.Project
    belongs_to :assignee, Argus.Accounts.User
    has_many :occurrences, Argus.Projects.ErrorOccurrence

    timestamps(type: :utc_datetime)
  end

  def changeset(error_event, attrs) do
    error_event
    |> cast(attrs, [
      :project_id,
      :fingerprint,
      :title,
      :culprit,
      :level,
      :platform,
      :sdk,
      :request,
      :contexts,
      :tags,
      :extra,
      :first_seen_at,
      :last_seen_at,
      :occurrence_count,
      :status,
      :assignee_id
    ])
    |> validate_required([
      :project_id,
      :fingerprint,
      :title,
      :level,
      :first_seen_at,
      :last_seen_at,
      :occurrence_count,
      :status
    ])
    |> unique_constraint([:project_id, :fingerprint])
  end
end
