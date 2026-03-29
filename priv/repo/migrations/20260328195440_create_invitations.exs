defmodule Argus.Repo.Migrations.CreateInvitations do
  use Ecto.Migration

  def change do
    create table(:invitations) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :email, :string, null: false
      add :token, :string, null: false
      add :role, :string, null: false
      add :invited_by_id, references(:users, on_delete: :nilify_all)
      add :accepted_at, :utc_datetime
      add :expires_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:invitations, [:user_id])
    create unique_index(:invitations, [:token])
  end
end
