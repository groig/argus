defmodule Argus.Repo.Migrations.IndexErrorOccurrencesTimestamp do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:error_occurrences, [:timestamp], concurrently: true)
  end
end
