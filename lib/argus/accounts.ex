defmodule Argus.Accounts do
  @moduledoc """
  User lifecycle, invitation onboarding, and account changes tied to authentication.

  Argus has no public signup. Users come from seeds, from invitations, or from an admin who
  creates the account with a password. Invitation acceptance confirms the account and sets the
  password. Email is optional: every invitation link can be copied from the admin panel, and
  admins can set passwords directly. Authentication itself stays on top of `phx.gen.auth`; this
  context adds the invitation, admin, and team rules around it.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Argus.Accounts.{ApiToken, Invitation, Scope, User, UserNotifier, UserToken}
  alias Argus.{Mailer, Repo, Teams}

  @type email_status :: :sent | :disabled | :failed

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

  def get_user(id), do: Repo.get(User, id)

  def create_user(attrs) do
    confirmed? = truthy?(attr(attrs, :confirmed))

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
    Repo.delete(user, stale_error_field: :id)
  end

  ## Admin user management
  #
  # Every function here takes the acting admin's scope first and returns
  # `{:error, :unauthorized}` for anyone who isn't a global admin, so the rules hold whichever
  # caller uses them.

  @doc """
  Creates an active account with a password, without sending any email.

  Accepts optional `team_id` and `team_role` attrs to add the user to a team in the same
  transaction.
  """
  def admin_create_user(%Scope{} = scope, attrs) do
    with :ok <- authorize_admin(scope) do
      changeset =
        %User{}
        |> User.registration_changeset(attrs)
        |> User.confirm_changeset()

      Multi.new()
      |> Multi.insert(:user, changeset)
      |> put_team_membership(attrs)
      |> Repo.transact()
      |> case do
        {:ok, %{user: user}} ->
          {:ok, user}

        {:error, :user, changeset, _changes} ->
          {:error, changeset}

        {:error, :team_member, reason, _changes} ->
          {:error, team_error_changeset(attrs, reason)}
      end
    end
  end

  def change_admin_user(%Scope{} = scope, %User{} = user, attrs \\ %{}) do
    User.admin_changeset(user, attrs, lock_role: self?(scope, user), validate_unique: false)
  end

  @doc """
  Updates name, email, and global role. Admins can't change their own role.

  Changing a pending user's email invalidates their current invitation link, since invitation
  tokens are bound to the address they were issued for. Returns an error on `:id` if the user
  was deleted meanwhile.
  """
  def admin_update_user(%Scope{} = scope, %User{} = user, attrs) do
    with :ok <- authorize_admin(scope) do
      user
      |> User.admin_changeset(attrs, lock_role: self?(scope, user))
      |> Repo.update(stale_error_field: :id)
    end
  end

  @doc """
  Sets another user's password from the admin panel.

  Pending users become active and their open invitations are closed. Every token is deleted,
  so old invitation or reset links stop working and no session survives. Returns
  `{:ok, {user, expired_tokens}}`; pass the tokens to `ArgusWeb.UserAuth.disconnect_sessions/1`
  so already connected LiveViews drop too. Admins change their own password from settings.
  """
  def admin_set_user_password(%Scope{} = scope, %User{} = user, attrs) do
    cond do
      authorize_admin(scope) != :ok ->
        {:error, :unauthorized}

      self?(scope, user) ->
        {:error, :self}

      true ->
        changeset =
          if user.confirmed_at do
            User.password_changeset(user, attrs)
          else
            user |> User.password_changeset(attrs) |> User.confirm_changeset()
          end

        now = DateTime.utc_now(:second)

        update_user_and_delete_tokens(changeset, fn multi ->
          Multi.update_all(
            multi,
            :invitations,
            from(invitation in Invitation,
              where: invitation.user_id == ^user.id and is_nil(invitation.accepted_at)
            ),
            set: [accepted_at: now, updated_at: now]
          )
        end)
    end
  end

  @doc """
  Returns the pending user's current, still valid invitation, or nil.

  Invitations keep their encoded token, so admins can copy the link again when email isn't
  available. Every path that invalidates an invitation token also closes, deletes, or expires
  its invitation row, and links are bound to the user's current email, so the row alone tells
  whether the link still works.
  """
  def get_pending_invitation(%Scope{} = scope, %User{confirmed_at: nil} = user) do
    if authorize_admin(scope) == :ok do
      now = DateTime.utc_now(:second)

      Repo.one(
        from invitation in Invitation,
          where:
            invitation.user_id == ^user.id and is_nil(invitation.accepted_at) and
              invitation.email == ^user.email and invitation.expires_at > ^now,
          order_by: [desc: invitation.inserted_at, desc: invitation.id],
          limit: 1
      )
    end
  end

  def get_pending_invitation(%Scope{}, %User{}), do: nil

  @doc """
  Returns the session tokens of a user, to disconnect their live sessions after their access
  changes.
  """
  def list_user_session_tokens(%User{id: user_id}) do
    Repo.all(
      from token in UserToken, where: token.user_id == ^user_id and token.context == "session"
    )
  end

  defp authorize_admin(%Scope{user: %User{role: :admin}}), do: :ok
  defp authorize_admin(_scope), do: {:error, :unauthorized}

  defp self?(%Scope{user: %User{id: id}}, %User{id: id}), do: true
  defp self?(_scope, _user), do: false

  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_tokens()
  end

  # Applies the user changeset and deletes every token of that user in one transaction, so a
  # credential change always ends existing sessions and outstanding email links. `extra` can add
  # steps to the same transaction. Returns `{:ok, {user, expired_tokens}}` so callers can
  # disconnect live sessions.
  defp update_user_and_delete_tokens(%Ecto.Changeset{} = changeset, extra \\ & &1) do
    user_id = changeset.data.id

    Multi.new()
    |> Multi.all(:tokens, from(token in UserToken, where: token.user_id == ^user_id))
    |> Multi.update(:user, changeset, stale_error_field: :id)
    |> extra.()
    |> Multi.delete_all(
      :delete_tokens,
      from(token in UserToken, where: token.user_id == ^user_id)
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
  invitation instead. Without email nothing could deliver the link, so no token is created
  and any earlier link keeps working.
  """
  def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    cond do
      not Mailer.enabled?() ->
        {:error, :disabled}

      is_nil(user.confirmed_at) ->
        {:error, :not_confirmed}

      true ->
        deliver_reset_password_link(user, reset_password_url_fun)
    end
  end

  defp deliver_reset_password_link(user, reset_password_url_fun) do
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

    UserNotifier.deliver_reset_password_instructions(user, reset_password_url_fun.(encoded_token))
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
    |> put_team_membership(attrs)
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
        send_invitation(invitation, inviter, invitation_url_fun)

      {:error, :user, changeset, _changes} ->
        {:error, changeset}

      {:error, :team_member, reason, _changes} ->
        {:error, team_error_changeset(attrs, reason)}

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
          send_invitation(invitation, inviter, invitation_url_fun)

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

        user
        |> User.invitation_acceptance_changeset(attrs)
        |> update_user_and_delete_tokens(
          &Multi.update(&1, :invitation, Invitation.accept_changeset(invitation))
        )
    end
  end

  # The invitation is committed before the email goes out, so a missing or broken mailer never
  # loses it: the admin panel shows the link either way.
  defp send_invitation(invitation, inviter, invitation_url_fun) do
    invitation = Repo.preload(invitation, [:user, :invited_by])

    email_status =
      invitation
      |> UserNotifier.deliver_invitation_instructions(
        inviter,
        invitation_url_fun.(invitation.token)
      )
      |> email_status()

    {:ok, invitation, email_status}
  end

  defp email_status({:ok, _email}), do: :sent
  defp email_status({:error, :disabled}), do: :disabled
  defp email_status({:error, _reason}), do: :failed

  defp put_team_membership(multi, attrs) do
    case attr(attrs, :team_id) do
      blank when blank in [nil, ""] ->
        multi

      team_id ->
        Multi.run(multi, :team_member, fn _repo, %{user: user} ->
          case Teams.get_team(team_id) do
            nil -> {:error, :team_not_found}
            team -> Teams.add_member(team, user, team_role(attr(attrs, :team_role)))
          end
        end)
    end
  end

  defp team_role(role) when role in [:admin, "admin"], do: :admin
  defp team_role(_role), do: :member

  # Surfaces a failed team membership on the user form: `team_role` errors under the team role
  # field, everything else (including a team deleted mid-request) under the team field.
  defp team_error_changeset(attrs, reason) do
    changeset = User.invited_user_changeset(%User{}, attrs, validate_unique: false)

    changeset =
      case reason do
        :team_not_found ->
          Ecto.Changeset.add_error(changeset, :team_id, "does not exist")

        %Ecto.Changeset{errors: errors} ->
          Enum.reduce(errors, changeset, fn
            {:role, {message, opts}}, acc ->
              Ecto.Changeset.add_error(acc, :team_role, message, opts)

            {_field, {message, opts}}, acc ->
              Ecto.Changeset.add_error(acc, :team_id, message, opts)
          end)
      end

    Map.put(changeset, :action, :insert)
  end

  defp attr(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))

  defp maybe_confirm(changeset, true), do: User.confirm_changeset(changeset)
  defp maybe_confirm(changeset, _), do: changeset

  defp truthy?(value), do: value in [true, "true", 1, "1"]
end
