defmodule Argus.Repo.Migrations.CreateErrorEvents do
  use Ecto.Migration

  def change do
    create table(:error_events) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :fingerprint, :string, null: false
      add :title, :string, null: false
      add :culprit, :string
      add :level, :string, null: false, default: "error"
      add :platform, :string
      add :sdk, :map, null: false, default: %{}
      add :request, :map, null: false, default: %{}
      add :contexts, :map, null: false, default: %{}
      add :tags, :map, null: false, default: %{}
      add :extra, :map, null: false, default: %{}
      add :first_seen_at, :utc_datetime, null: false
      add :last_seen_at, :utc_datetime, null: false
      add :occurrence_count, :integer, null: false, default: 1
      add :status, :string, null: false, default: "unresolved"

      timestamps(type: :utc_datetime)
    end

    create index(:error_events, [:project_id, :last_seen_at])
    create index(:error_events, [:project_id, :status])
    create index(:error_events, [:project_id, :level])
    create unique_index(:error_events, [:project_id, :fingerprint])
  end
end
