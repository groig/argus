defmodule Argus.Repo.Migrations.AddAccentColorToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :accent_color, :string
    end
  end
end
