defmodule Argus.Accounts do
  @moduledoc """
  User lifecycle, invitation onboarding, and account changes tied to authentication.

  Argus has no public signup. Users come from seeds or invitations. Invitation acceptance
  confirms the account and sets the password. Authentication itself stays on top of
  `phx.gen.auth`; this context adds the invitation and team rules around it.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Argus.Accounts.{ApiToken, Invitation, User, UserNotifier, UserToken}
  alias Argus.Repo

  def list_users do
    Repo.all(
      from user in User,
        order_by: [asc: user.name, asc: user.email],
        preload: [team_members: :team, received_invitations: :invited_by]
    )
  end

  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)

    if user && user.confirmed_at && User.valid_password?(user, password) do
      user
    end
  end

  def get_user!(id), do: Repo.get!(User, id)

  def create_user(attrs) do
    confirmed? = truthy?(Map.get(attrs, :confirmed) || Map.get(attrs, "confirmed"))

    %User{}
    |> User.registration_changeset(attrs)
    |> maybe_confirm(confirmed?)
    |> Repo.insert()
  end

  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  def change_user_profile(user, attrs \\ %{}, opts \\ []) do
    User.profile_changeset(user, attrs, opts)
  end

  def update_user_profile(user, attrs) do
    user
    |> User.profile_changeset(attrs)
    |> Repo.update()
  end

  def update_user_role(user, role) when is_atom(role) do
    user
    |> User.role_changeset(%{role: role})
    |> Repo.update()
  end

  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  def update_user_password(user, attrs) do
    changeset = User.password_changeset(user, attrs)

    Multi.new()
    |> Multi.all(:tokens, from(token in UserToken, where: token.user_id == ^user.id))
    |> Multi.update(:user, changeset)
    |> Multi.delete_all(
      :delete_tokens,
      from(token in UserToken, where: token.user_id == ^user.id)
    )
    |> Repo.transact()
    |> case do
      {:ok, %{user: user, tokens: tokens}} -> {:ok, {user, tokens}}
      {:error, :user, changeset, _changes} -> {:error, changeset}
    end
  end

  ## Password reset

  @doc """
  Emails a password reset link to an active user, replacing any earlier reset link.

  Pending invited users have no password yet, so they are skipped; they should use their
  invitation instead.
  """
  def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    if user.confirmed_at do
      {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")

      {:ok, _} =
        Multi.new()
        |> Multi.delete_all(
          :delete_tokens,
          from(token in UserToken,
            where: token.user_id == ^user.id and token.context == "reset_password"
          )
        )
        |> Multi.insert(:user_token, user_token)
        |> Repo.transact()

      UserNotifier.deliver_reset_password_instructions(
        user,
        reset_password_url_fun.(encoded_token)
      )
    else
      {:error, :not_confirmed}
    end
  end

  def get_user_by_reset_password_token(token) when is_binary(token) do
    with {:ok, query} <- UserToken.verify_reset_password_token_query(token),
         {%User{confirmed_at: %DateTime{}} = user, _user_token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Sets a new password. Like `update_user_password/2`, this deletes every token for the user,
  including the reset token and all sessions.
  """
  def reset_user_password(%User{} = user, attrs) do
    update_user_password(user, attrs)
  end

  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  def delete_user_session_token(token) do
    Repo.delete_all(
      from(user_token in UserToken,
        where: user_token.token == ^token and user_token.context == "session"
      )
    )

    :ok
  end

  ## API tokens

  def list_api_tokens(%User{id: user_id}) do
    Repo.all(
      from api_token in ApiToken,
        where: api_token.user_id == ^user_id,
        order_by: [desc: api_token.inserted_at, desc: api_token.id]
    )
  end

  def change_api_token(attrs \\ %{}) do
    ApiToken.changeset(%ApiToken{}, attrs)
  end

  @doc """
  Creates a token for the user. Returns `{:ok, {raw_token, api_token}}`; the raw token can't be
  recovered later.
  """
  def create_api_token(%User{} = user, attrs) do
    {raw, changeset} = ApiToken.build(user, attrs)

    with {:ok, api_token} <- Repo.insert(changeset) do
      {:ok, {raw, api_token}}
    end
  end

  def delete_api_token(%User{id: user_id}, id) do
    {count, _} =
      Repo.delete_all(
        from api_token in ApiToken, where: api_token.id == ^id and api_token.user_id == ^user_id
      )

    if count == 1, do: :ok, else: {:error, :not_found}
  end

  @doc """
  Returns the user owning the raw token, or nil. Touches `last_used_at` at most once a minute.
  """
  def get_user_by_api_token(raw) when is_binary(raw) do
    case Repo.one(ApiToken.verify_query(raw)) do
      {api_token, user} ->
        touch_api_token(api_token)
        user

      nil ->
        nil
    end
  end

  def get_user_by_api_token(_raw), do: nil

  defp touch_api_token(%ApiToken{last_used_at: last_used_at} = api_token) do
    now = DateTime.utc_now(:second)

    if is_nil(last_used_at) or DateTime.diff(now, last_used_at) >= 60 do
      Repo.update_all(from(t in ApiToken, where: t.id == ^api_token.id), set: [last_used_at: now])
    end

    :ok
  end

  def deliver_user_invitation(%User{} = inviter, attrs, invitation_url_fun)
      when is_function(invitation_url_fun, 1) do
    expires_at = DateTime.add(DateTime.utc_now(:second), 72, :hour)

    Multi.new()
    |> Multi.insert(:user, User.invited_user_changeset(%User{}, attrs))
    |> Multi.run(:token_pair, fn _repo, %{user: user} ->
      {:ok, UserToken.build_email_token(user, "invite")}
    end)
    |> Multi.insert(:user_token, fn %{token_pair: {_encoded_token, user_token}} -> user_token end)
    |> Multi.insert(:invitation, fn %{token_pair: {encoded_token, _user_token}, user: user} ->
      Invitation.create_changeset(%Invitation{}, %{
        user_id: user.id,
        email: user.email,
        token: encoded_token,
        role: user.role,
        invited_by_id: inviter.id,
        expires_at: expires_at
      })
    end)
    |> Repo.transact()
    |> case do
      {:ok, %{invitation: invitation}} ->
        invitation = Repo.preload(invitation, [:user, :invited_by])

        UserNotifier.deliver_invitation_instructions(
          invitation,
          inviter,
          invitation_url_fun.(invitation.token)
        )

        {:ok, invitation}

      {:error, :user, changeset, _changes} ->
        {:error, changeset}

      {:error, :invitation, changeset, _changes} ->
        {:error, changeset}
    end
  end

  def resend_user_invitation(%User{} = inviter, %User{} = invitee, invitation_url_fun)
      when is_function(invitation_url_fun, 1) do
    if invitee.confirmed_at do
      {:error, :already_active}
    else
      expires_at = DateTime.add(DateTime.utc_now(:second), 72, :hour)

      Multi.new()
      |> Multi.delete_all(
        :delete_tokens,
        from(token in UserToken,
          where: token.user_id == ^invitee.id and token.context == "invite"
        )
      )
      |> Multi.delete_all(
        :delete_invitations,
        from(invitation in Invitation,
          where: invitation.user_id == ^invitee.id and is_nil(invitation.accepted_at)
        )
      )
      |> Multi.run(:token_pair, fn _repo, _changes ->
        {:ok, UserToken.build_email_token(invitee, "invite")}
      end)
      |> Multi.insert(:user_token, fn %{token_pair: {_encoded_token, user_token}} ->
        user_token
      end)
      |> Multi.insert(:invitation, fn %{token_pair: {encoded_token, _user_token}} ->
        Invitation.create_changeset(%Invitation{}, %{
          user_id: invitee.id,
          email: invitee.email,
          token: encoded_token,
          role: invitee.role,
          invited_by_id: inviter.id,
          expires_at: expires_at
        })
      end)
      |> Repo.transact()
      |> case do
        {:ok, %{invitation: invitation}} ->
          invitation = Repo.preload(invitation, [:user, :invited_by])

          UserNotifier.deliver_invitation_instructions(
            invitation,
            inviter,
            invitation_url_fun.(invitation.token)
          )

          {:ok, invitation}

        {:error, :invitation, changeset, _changes} ->
          {:error, changeset}
      end
    end
  end

  def get_invitation_by_token(token) when is_binary(token) do
    with {:ok, query} <- UserToken.verify_invitation_token_query(token),
         {user, _user_token} <- Repo.one(query),
         %Invitation{} = invitation <-
           Repo.one(
             from invitation in Invitation,
               where:
                 invitation.user_id == ^user.id and invitation.token == ^token and
                   is_nil(invitation.accepted_at)
           ),
         :gt <- DateTime.compare(invitation.expires_at, DateTime.utc_now()) do
      Repo.preload(invitation, [:user, :invited_by])
    else
      _ -> nil
    end
  end

  def accept_user_invitation(token, attrs) do
    case get_invitation_by_token(token) do
      nil ->
        {:error, :invalid_or_expired}

      %Invitation{} = invitation ->
        user = Repo.preload(invitation, :user).user
        changeset = User.invitation_acceptance_changeset(user, attrs)

        Multi.new()
        |> Multi.all(
          :tokens,
          from(user_token in UserToken, where: user_token.user_id == ^user.id)
        )
        |> Multi.update(:user, changeset)
        |> Multi.update(:invitation, Invitation.accept_changeset(invitation))
        |> Multi.delete_all(
          :delete_tokens,
          from(user_token in UserToken, where: user_token.user_id == ^user.id)
        )
        |> Repo.transact()
        |> case do
          {:ok, %{user: accepted_user, tokens: tokens}} ->
            {:ok, {accepted_user, tokens}}

          {:error, :user, changeset, _changes} ->
            {:error, changeset}
        end
    end
  end

  defp maybe_confirm(changeset, true), do: User.confirm_changeset(changeset)
  defp maybe_confirm(changeset, _), do: changeset

  defp truthy?(value), do: value in [true, "true", 1, "1"]
end
