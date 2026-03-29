defmodule Argus.Repo.Migrations.CreateErrorOccurrences do
  use Ecto.Migration

  def change do
    create table(:error_occurrences) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :error_event_id, references(:error_events, on_delete: :delete_all), null: false
      add :event_id, :string, null: false
      add :timestamp, :utc_datetime, null: false
      add :request_url, :string
      add :user_context, :map, null: false, default: %{}
      add :exception_values, {:array, :map}, null: false, default: []
      add :breadcrumbs, {:array, :map}, null: false, default: []
      add :raw_payload, :map, null: false
      add :minidump_attachment, :binary

      timestamps(type: :utc_datetime)
    end

    create index(:error_occurrences, [:error_event_id, :timestamp])
    create index(:error_occurrences, [:project_id])
    create unique_index(:error_occurrences, [:project_id, :event_id])
  end
end
