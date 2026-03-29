defmodule Argus.Repo.Migrations.CreateProjects do
  use Ecto.Migration

  def change do
    create table(:projects) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :dsn_key, :string, null: false
      add :team_id, references(:teams, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:projects, [:team_id])
    create unique_index(:projects, [:slug])
    create unique_index(:projects, [:dsn_key])
  end
end
