defmodule Argus.Projects.Project do
  use Ecto.Schema
  import Ecto.Changeset

  alias Argus.Projects.WebhookTemplate

  @default_log_limit 1_000

  schema "projects" do
    field :name, :string
    field :slug, :string
    field :dsn_key, :string
    field :log_limit, :integer, default: @default_log_limit
    field :webhook_url, :string
    field :webhook_body_template, :string

    belongs_to :team, Argus.Teams.Team
    has_many :error_events, Argus.Projects.ErrorEvent
    has_many :log_events, Argus.Logs.LogEvent

    timestamps(type: :utc_datetime)
  end

  def default_log_limit, do: @default_log_limit

  def changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :slug, :dsn_key, :team_id, :log_limit])
    |> validate_required([:name, :slug, :dsn_key, :team_id, :log_limit])
    |> validate_length(:name, min: 2, max: 80)
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/)
    |> validate_length(:slug, min: 2, max: 80)
    |> validate_number(:log_limit, greater_than_or_equal_to: 1)
    |> unique_constraint(:slug)
    |> unique_constraint(:dsn_key)
  end

  def webhook_changeset(project, attrs) do
    project
    |> cast(attrs, [:webhook_url, :webhook_body_template])
    |> update_change(:webhook_url, &blank_to_nil/1)
    |> update_change(:webhook_body_template, &blank_to_nil/1)
    |> validate_webhook_url()
    |> validate_webhook_template()
  end

  defp validate_webhook_url(changeset) do
    validate_change(changeset, :webhook_url, fn :webhook_url, webhook_url ->
      case URI.parse(webhook_url) do
        %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
          []

        _ ->
          [webhook_url: "must be an http or https URL"]
      end
    end)
  end

  defp validate_webhook_template(changeset) do
    webhook_url = get_field(changeset, :webhook_url)
    template = get_field(changeset, :webhook_body_template)

    cond do
      is_nil(webhook_url) ->
        changeset

      is_nil(template) ->
        add_error(changeset, :webhook_body_template, "can't be blank")

      true ->
        validate_change(changeset, :webhook_body_template, fn :webhook_body_template, body ->
          case WebhookTemplate.decode(body) do
            {:ok, %{} = _template} -> []
            {:ok, _other} -> [webhook_body_template: "must be a JSON object"]
            {:error, _reason} -> [webhook_body_template: "must be valid JSON"]
          end
        end)
    end
  end

  defp blank_to_nil(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value
end
