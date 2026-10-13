defmodule Argus.Accounts.ApiToken do
  @moduledoc """
  Personal token for the agent API.

  Only the SHA-256 hash is stored. The raw token is shown once, at creation time, and grants the
  same project access as its owner.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Argus.Accounts.ApiToken

  @hash_algorithm :sha256
  @rand_size 32
  @prefix "argus_"

  schema "api_tokens" do
    field :name, :string
    field :token_hash, :binary
    field :last_used_at, :utc_datetime
    belongs_to :user, Argus.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(api_token, attrs) do
    api_token
    |> cast(attrs, [:name])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, max: 80)
  end

  @doc """
  Builds a token for the user, returning the raw token and the struct to insert.
  """
  def build(user, attrs) do
    raw = @prefix <> Base.url_encode64(:crypto.strong_rand_bytes(@rand_size), padding: false)

    changeset =
      %ApiToken{user_id: user.id, token_hash: hash(raw)}
      |> changeset(attrs)

    {raw, changeset}
  end

  def verify_query(raw) when is_binary(raw) do
    from api_token in ApiToken,
      join: user in assoc(api_token, :user),
      where: api_token.token_hash == ^hash(raw),
      select: {api_token, user}
  end

  defp hash(raw), do: :crypto.hash(@hash_algorithm, raw)
end
