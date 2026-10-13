defmodule Argus.Repo.Migrations.CreateApiTokens do
  use Ecto.Migration

  def change do
    create table(:api_tokens) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :token_hash, :binary, null: false
      add :last_used_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:api_tokens, [:user_id])
    create unique_index(:api_tokens, [:token_hash])
  end
end
