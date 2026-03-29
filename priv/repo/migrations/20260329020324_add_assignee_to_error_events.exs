defmodule Argus.Repo.Migrations.AddAssigneeToErrorEvents do
  use Ecto.Migration

  def change do
    alter table(:error_events) do
      add :assignee_id, references(:users, on_delete: :nilify_all)
    end

    create index(:error_events, [:assignee_id])
    create index(:error_events, [:project_id, :assignee_id])
  end
end
