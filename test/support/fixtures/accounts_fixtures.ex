defmodule Argus.AccountsFixtures do
  @moduledoc """
  Test helpers for the Accounts context.
  """

  import Ecto.Query

  alias Argus.Accounts
  alias Argus.Accounts.Scope
  alias Argus.Repo

  def unique_user_email, do: "user#{System.unique_integer([:positive])}@example.com"
  def unique_user_name, do: "User #{System.unique_integer([:positive])}"
  def valid_user_password, do: "changeme123"

  def valid_user_attributes(attrs \\ %{}) do
    attrs = Map.new(attrs)

    Enum.into(attrs, %{
      email: unique_user_email(),
      name: unique_user_name(),
      role: :member,
      password: valid_user_password(),
      password_confirmation: valid_user_password(),
      confirmed: true
    })
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Accounts.create_user()

    user
  end

  def admin_fixture(attrs \\ %{}) do
    user_fixture(Map.put(Map.new(attrs), :role, :admin))
  end

  def invitation_fixture(inviter \\ admin_fixture(), attrs \\ %{}) do
    attrs =
      attrs
      |> Map.new()
      |> Enum.into(%{
        email: unique_user_email(),
        name: unique_user_name(),
        role: "member"
      })

    {:ok, invitation} =
      Accounts.deliver_user_invitation(inviter, attrs, fn token ->
        "https://example.com/invitations/#{token}"
      end)

    Repo.preload(invitation, [:user, :invited_by])
  end

  def pending_user_fixture(attrs \\ %{}) do
    invitation =
      case Map.pop(Map.new(attrs), :inviter) do
        {nil, attrs} -> invitation_fixture(admin_fixture(), attrs)
        {inviter, attrs} -> invitation_fixture(inviter, attrs)
      end

    invitation.user
  end

  def accepted_user_fixture(attrs \\ %{}) do
    invitation =
      case Map.pop(Map.new(attrs), :inviter) do
        {nil, attrs} -> invitation_fixture(admin_fixture(), attrs)
        {inviter, attrs} -> invitation_fixture(inviter, attrs)
      end

    password = Map.get(attrs, :password, valid_user_password())

    {:ok, {user, _expired_tokens}} =
      Accounts.accept_user_invitation(invitation.token, %{
        password: password,
        password_confirmation: password
      })

    Repo.preload(user, [:team_members, :teams])
  end

  def user_scope_fixture do
    user_fixture()
    |> user_scope_fixture()
  end

  def user_scope_fixture(user) do
    Scope.for_user(user)
  end

  def set_password(user, password \\ valid_user_password()) do
    {:ok, {user, _expired_tokens}} =
      Accounts.update_user_password(user, %{
        password: password,
        password_confirmation: password
      })

    user
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    Repo.update_all(
      from(t in Accounts.UserToken, where: t.token == ^token),
      set: [authenticated_at: authenticated_at]
    )
  end

  def offset_user_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    Repo.update_all(
      from(ut in Accounts.UserToken, where: ut.token == ^token),
      set: [inserted_at: dt, authenticated_at: dt]
    )
  end
end
