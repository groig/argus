defmodule Argus.Projects.ErrorOccurrence do
  use Ecto.Schema
  import Ecto.Changeset

  schema "error_occurrences" do
    field :event_id, :string
    field :timestamp, :utc_datetime
    field :request_url, :string
    field :user_context, :map, default: %{}
    field :exception_values, {:array, :map}, default: []
    field :breadcrumbs, {:array, :map}, default: []
    field :raw_payload, :map
    field :minidump_attachment, :binary

    belongs_to :project, Argus.Projects.Project
    belongs_to :error_event, Argus.Projects.ErrorEvent

    timestamps(type: :utc_datetime)
  end

  def changeset(error_occurrence, attrs) do
    error_occurrence
    |> cast(attrs, [
      :project_id,
      :error_event_id,
      :event_id,
      :timestamp,
      :request_url,
      :user_context,
      :exception_values,
      :breadcrumbs,
      :raw_payload,
      :minidump_attachment
    ])
    |> validate_required([:project_id, :error_event_id, :event_id, :timestamp, :raw_payload])
    |> unique_constraint([:project_id, :event_id])
  end
end
