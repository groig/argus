defmodule Argus.Repo.Migrations.AddLogLimitToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :log_limit, :integer, default: 1_000, null: false
    end
  end
end
