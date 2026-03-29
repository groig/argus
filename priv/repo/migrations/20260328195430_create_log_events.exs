defmodule Argus.Repo.Migrations.CreateLogEvents do
  use Ecto.Migration

  def change do
    create table(:log_events) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :level, :string, null: false, default: "info"
      add :message, :string, null: false
      add :timestamp, :utc_datetime, null: false
      add :metadata, :map, null: false, default: %{}
      add :logger_name, :string
      add :message_template, :string
      add :origin, :string
      add :release, :string
      add :environment, :string
      add :sdk_name, :string
      add :sdk_version, :string
      add :sequence, :integer, null: false, default: 0
      add :trace_id, :string
      add :span_id, :string

      timestamps(type: :utc_datetime)
    end

    create index(:log_events, [:project_id, :timestamp])
    create index(:log_events, [:project_id, :level])
  end
end
