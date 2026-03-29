defmodule Argus.Accounts.Invitation do
  use Ecto.Schema
  import Ecto.Changeset

  schema "invitations" do
    field :email, :string
    field :token, :string
    field :role, Ecto.Enum, values: [:admin, :member]
    field :accepted_at, :utc_datetime
    field :expires_at, :utc_datetime

    belongs_to :user, Argus.Accounts.User
    belongs_to :invited_by, Argus.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def create_changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [:user_id, :email, :token, :role, :invited_by_id, :expires_at])
    |> validate_required([:user_id, :email, :token, :role, :expires_at])
    |> unique_constraint(:token)
  end

  def accept_changeset(invitation) do
    change(invitation, accepted_at: DateTime.utc_now(:second))
  end
end
