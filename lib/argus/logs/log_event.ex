defmodule Argus.Logs.LogEvent do
  use Ecto.Schema
  import Ecto.Changeset

  schema "log_events" do
    field :level, Ecto.Enum, values: [:error, :warning, :info], default: :info
    field :message, :string
    field :timestamp, :utc_datetime
    field :metadata, :map, default: %{}
    field :logger_name, :string
    field :message_template, :string
    field :origin, :string
    field :release, :string
    field :environment, :string
    field :sdk_name, :string
    field :sdk_version, :string
    field :sequence, :integer, default: 0
    field :trace_id, :string
    field :span_id, :string

    belongs_to :project, Argus.Projects.Project

    timestamps(type: :utc_datetime)
  end

  def changeset(log_event, attrs) do
    log_event
    |> cast(attrs, [
      :project_id,
      :level,
      :message,
      :timestamp,
      :metadata,
      :logger_name,
      :message_template,
      :origin,
      :release,
      :environment,
      :sdk_name,
      :sdk_version,
      :sequence,
      :trace_id,
      :span_id
    ])
    |> validate_required([:project_id, :level, :message, :timestamp])
  end
end
