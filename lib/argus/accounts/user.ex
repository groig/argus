defmodule Argus.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :name, :string
    field :role, Ecto.Enum, values: [:admin, :member], default: :member
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime
    field :authenticated_at, :utc_datetime, virtual: true

    has_many :team_members, Argus.Teams.TeamMember
    has_many :teams, through: [:team_members, :team]
    has_many :sent_invitations, Argus.Accounts.Invitation, foreign_key: :invited_by_id
    has_many :received_invitations, Argus.Accounts.Invitation, foreign_key: :user_id

    timestamps(type: :utc_datetime)
  end

  def invited_user_changeset(user_or_changeset, attrs, opts \\ []) do
    user_or_changeset
    |> cast(attrs, [:email, :name, :role])
    |> validate_required([:email, :name, :role])
    |> validate_name()
    |> validate_email(opts)
    |> validate_role()
  end

  def profile_changeset(user_or_changeset, attrs, opts \\ []) do
    user_or_changeset
    |> cast(attrs, [:email, :name])
    |> validate_required([:email, :name])
    |> validate_name()
    |> validate_email(opts)
  end

  def role_changeset(user_or_changeset, attrs) do
    user_or_changeset
    |> cast(attrs, [:role])
    |> validate_role()
  end

  def registration_changeset(user_or_changeset, attrs) do
    user_or_changeset
    |> invited_user_changeset(attrs)
    |> password_changeset(attrs)
  end

  def invitation_acceptance_changeset(user_or_changeset, attrs) do
    user_or_changeset
    |> password_changeset(attrs)
    |> put_change(:confirmed_at, DateTime.utc_now(:second))
  end

  def password_changeset(user_or_changeset, attrs, opts \\ []) do
    user_or_changeset
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 8, max: 72)
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      # If using Bcrypt, then further validate it is at most 72 bytes long
      |> validate_length(:password, max: 72, count: :bytes)
      # Hashing could be done with `Ecto.Changeset.prepare_changes/2`, but that
      # would keep the database transaction open longer and hurt performance.
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  def confirm_changeset(user_or_changeset) do
    change(user_or_changeset, confirmed_at: DateTime.utc_now(:second))
  end

  def valid_password?(%Argus.Accounts.User{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end

  defp validate_name(changeset) do
    changeset
    |> validate_length(:name, min: 2, max: 80)
  end

  defp validate_role(changeset) do
    validate_required(changeset, [:role])
  end

  defp validate_email(changeset, opts) do
    changeset =
      changeset
      |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
        message: "must have the @ sign and no spaces"
      )
      |> validate_length(:email, max: 160)

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:email, Argus.Repo)
      |> unique_constraint(:email)
    else
      changeset
    end
  end
end
