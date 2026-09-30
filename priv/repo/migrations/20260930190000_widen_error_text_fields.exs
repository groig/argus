defmodule Argus.Repo.Migrations.WidenErrorTextFields do
  use Ecto.Migration

  # varchar -> text is metadata-only in PostgreSQL (no table rewrite).
  def change do
    alter table(:error_events) do
      modify :title, :text, null: false, from: {:string, null: false}
      modify :culprit, :text, from: :string
    end

    alter table(:error_occurrences) do
      modify :request_url, :text, from: :string
    end
  end
end
