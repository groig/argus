defmodule Argus.Repo.Migrations.AddUserProfileFields do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :name, :string, null: false, default: ""
      add :role, :string, null: false, default: "member"
    end

    create index(:users, [:role])
  end
end
