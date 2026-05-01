defmodule Argus.Repo.Migrations.AddWebhookSettingsToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :webhook_url, :string
      add :webhook_body_template, :text
    end
  end
end
