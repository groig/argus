defmodule Argus.AccountsTest do
  use Argus.DataCase

  import Swoosh.TestAssertions

  alias Argus.Accounts
  alias Argus.Accounts.{Invitation, User, UserToken}
  alias Argus.{Repo, Teams}

  import Argus.AccountsFixtures
  import Argus.WorkspaceFixtures

  describe "get_user_by_email/1" do
    test "returns nil when the user does not exist" do
      assert Accounts.get_user_by_email("missing@example.com") == nil
    end

    test "returns the user when the email exists" do
      user = user_fixture()
      user_id = user.id
      assert %User{id: ^user_id} = Accounts.get_user_by_email(user.email)
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "returns the user for confirmed accounts with valid credentials" do
      user = user_fixture()
      user_id = user.id

      assert %User{id: ^user_id} =
               Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end

    test "rejects pending invited accounts before invitation acceptance" do
      inviter = admin_fixture()

      invitation =
        invitation_fixture(inviter, %{email: unique_user_email(), name: unique_user_name()})

      assert Accounts.get_user_by_email_and_password(invitation.email, valid_user_password()) ==
               nil

      refute invitation.user.confirmed_at
    end
  end

  describe "create_user/1" do
    test "validates required fields" do
      {:error, changeset} = Accounts.create_user(%{})

      assert %{
               email: ["can't be blank"],
               name: ["can't be blank"],
               password: ["can't be blank"]
             } = errors_on(changeset)
    end
  end

  describe "deliver_user_invitation/3" do
    test "creates a pending user, invitation, and email" do
      inviter = admin_fixture(%{name: "Admin Person"})
      email = unique_user_email()

      {:ok, invitation, :sent} =
        Accounts.deliver_user_invitation(
          inviter,
          %{email: email, name: "Invited Member", role: "member"},
          &"https://argus.test/invitations/#{&1}"
        )

      invitation = Repo.preload(invitation, [:user, :invited_by])

      assert invitation.email == email
      assert invitation.invited_by_id == inviter.id
      assert invitation.user.email == email
      assert invitation.user.name == "Invited Member"
      assert invitation.user.confirmed_at == nil
      assert invitation.accepted_at == nil
      assert Repo.get_by(UserToken, user_id: invitation.user_id, context: "invite")

      assert_email_sent(subject: "You're invited to Argus", to: [nil: email])
    end

    test "returns the invitation while it is active and hides it once expired" do
      inviter = admin_fixture()
      invitation = invitation_fixture(inviter)
      invitation_id = invitation.id

      assert %Invitation{id: ^invitation_id} = Accounts.get_invitation_by_token(invitation.token)

      invitation
      |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(:second), -1, :second))
      |> Repo.update!()

      assert Accounts.get_invitation_by_token(invitation.token) == nil
    end
  end

  describe "resend_user_invitation/3" do
    test "rotates the token for a pending user and sends a fresh email" do
      inviter = admin_fixture(%{name: "Admin Person"})

      invitation =
        invitation_fixture(inviter, %{email: unique_user_email(), name: "Pending User"})

      old_token = invitation.token
      assert_email_sent(fn email -> email.text_body =~ old_token end)

      {:ok, resent_invitation, :sent} =
        Accounts.resend_user_invitation(
          inviter,
          invitation.user,
          &"https://argus.test/invitations/#{&1}"
        )

      assert resent_invitation.user_id == invitation.user_id
      assert resent_invitation.token != old_token
      assert Accounts.get_invitation_by_token(old_token) == nil

      assert Repo.aggregate(
               from(token in UserToken, where: token.user_id == ^invitation.user_id),
               :count
             ) ==
               1

      assert_email_sent(fn email ->
        email.subject == "You're invited to Argus" and
          Enum.any?(email.to, fn {_name, address} -> address == invitation.email end) and
          email.text_body =~ resent_invitation.token
      end)
    end

    test "rejects active users" do
      inviter = admin_fixture()
      user = user_fixture()

      assert Accounts.resend_user_invitation(
               inviter,
               user,
               &"https://argus.test/invitations/#{&1}"
             ) ==
               {:error, :already_active}
    end
  end

  describe "accept_user_invitation/2" do
    test "sets the password, confirms the user, and marks the invitation accepted" do
      inviter = admin_fixture()
      invitation = invitation_fixture(inviter)

      {:ok, {user, expired_tokens}} =
        Accounts.accept_user_invitation(invitation.token, %{
          password: valid_user_password(),
          password_confirmation: valid_user_password()
        })

      invitation = Repo.get!(Invitation, invitation.id)

      assert invitation.accepted_at
      assert user.confirmed_at
      assert user.hashed_password
      assert Accounts.get_user_by_email_and_password(user.email, valid_user_password())
      assert expired_tokens != []
      assert Repo.get_by(UserToken, user_id: user.id, context: "invite") == nil
    end

    test "returns an error for an invalid token" do
      assert Accounts.accept_user_invitation("invalid", %{
               password: valid_user_password(),
               password_confirmation: valid_user_password()
             }) == {:error, :invalid_or_expired}
    end
  end

  describe "session tokens" do
    test "generate_user_session_token/1 and get_user_by_session_token/1 round-trip the user" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      user_id = user.id

      assert {%User{id: ^user_id}, inserted_at} = Accounts.get_user_by_session_token(token)
      assert %DateTime{} = inserted_at
    end

    test "delete_user_session_token/1 removes the session token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)

      assert :ok = Accounts.delete_user_session_token(token)
      assert Accounts.get_user_by_session_token(token) == nil
    end
  end

  describe "update_user_password/2" do
    test "updates the password and invalidates existing tokens" do
      user = user_fixture()
      old_token = Accounts.generate_user_session_token(user)

      assert {:ok, {updated_user, expired_tokens}} =
               Accounts.update_user_password(user, %{
                 password: "newpassword123",
                 password_confirmation: "newpassword123"
               })

      assert Enum.any?(expired_tokens, &(&1.token == old_token))
      assert Accounts.get_user_by_session_token(old_token) == nil
      assert Accounts.get_user_by_email_and_password(updated_user.email, "newpassword123")
    end
  end

  describe "delete_user/1" do
    test "removes the user and cascades tokens, invitations, and memberships" do
      inviter = admin_fixture()
      team = team_fixture()
      invitation = invitation_fixture(inviter)
      user = Repo.preload(invitation.user, [:team_members, :teams])
      _membership = membership_fixture(team, user)
      _session_token = Accounts.generate_user_session_token(user)

      assert {:ok, _user} = Accounts.delete_user(user)

      assert Repo.get(User, user.id) == nil

      assert Repo.aggregate(from(token in UserToken, where: token.user_id == ^user.id), :count) ==
               0

      assert Repo.aggregate(from(inv in Invitation, where: inv.user_id == ^user.id), :count) == 0
    end
  end

  describe "API tokens" do
    test "verifies tokens by their raw value and scopes deletion to the owner" do
      user = user_fixture()
      other = user_fixture()

      assert {:ok, {raw, api_token}} = Accounts.create_api_token(user, %{"name" => "agent"})
      assert "argus_" <> _ = raw
      refute api_token.token_hash == raw

      assert Accounts.get_user_by_api_token(raw).id == user.id
      assert Accounts.get_user_by_api_token("argus_wrong") == nil
      assert [%{last_used_at: %DateTime{}}] = Accounts.list_api_tokens(user)

      assert {:error, :not_found} = Accounts.delete_api_token(other, api_token.id)
      assert :ok = Accounts.delete_api_token(user, api_token.id)
      assert Accounts.get_user_by_api_token(raw) == nil
    end

    test "requires a name" do
      assert {:error, changeset} = Accounts.create_api_token(user_fixture(), %{"name" => " "})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "password reset" do
    test "delivers a reset link that resolves back to the user" do
      user = user_fixture()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
        end)

      assert Repo.get_by!(UserToken, user_id: user.id, context: "reset_password").sent_to ==
               user.email

      assert Accounts.get_user_by_reset_password_token(token).id == user.id
    end

    test "only the latest reset link is valid" do
      user = user_fixture()
      deliver = fn url -> Accounts.deliver_user_reset_password_instructions(user, url) end

      old_token = extract_user_token(deliver)
      new_token = extract_user_token(deliver)

      refute Accounts.get_user_by_reset_password_token(old_token)
      assert Accounts.get_user_by_reset_password_token(new_token)
    end

    test "does not send reset links to pending invited users" do
      user = pending_user_fixture()
      assert_email_sent(subject: "You're invited to Argus")

      assert {:error, :not_confirmed} =
               Accounts.deliver_user_reset_password_instructions(user, &"/#{&1}")

      assert_no_email_sent()
    end

    test "rejects invalid and expired tokens" do
      user = user_fixture()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
        end)

      refute Accounts.get_user_by_reset_password_token("oops")

      {1, nil} =
        Repo.update_all(
          from(t in UserToken, where: t.user_id == ^user.id and t.context == "reset_password"),
          set: [inserted_at: DateTime.add(DateTime.utc_now(:second), -2, :hour)]
        )

      refute Accounts.get_user_by_reset_password_token(token)
    end

    test "resetting the password deletes all tokens" do
      user = user_fixture()
      _session = Accounts.generate_user_session_token(user)

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
        end)

      assert {:ok, {_user, _expired}} =
               Accounts.reset_user_password(user, %{
                 password: "brand-new-password",
                 password_confirmation: "brand-new-password"
               })

      refute Repo.get_by(UserToken, user_id: user.id)
      refute Accounts.get_user_by_reset_password_token(token)
      assert Accounts.get_user_by_email_and_password(user.email, "brand-new-password")
    end
  end

  describe "deliver_user_invitation/3 with a team" do
    test "adds the invited user to the team in the same transaction" do
      inviter = admin_fixture()
      team = team_fixture()

      {:ok, invitation, :sent} =
        Accounts.deliver_user_invitation(
          inviter,
          %{
            "email" => unique_user_email(),
            "name" => "Invited Member",
            "role" => "member",
            "team_id" => Integer.to_string(team.id),
            "team_role" => "admin"
          },
          &"https://argus.test/invitations/#{&1}"
        )

      assert Teams.member_role(invitation.user, team) == :admin
    end

    test "rolls back the user when the team does not exist" do
      inviter = admin_fixture()
      email = unique_user_email()

      assert {:error, changeset} =
               Accounts.deliver_user_invitation(
                 inviter,
                 %{"email" => email, "name" => "Ghost", "role" => "member", "team_id" => "-1"},
                 &"https://argus.test/invitations/#{&1}"
               )

      assert %{team_id: ["does not exist"]} = errors_on(changeset)
      refute Accounts.get_user_by_email(email)
    end
  end

  describe "admin_create_user/2" do
    test "creates an active user that can log in, without sending email" do
      email = unique_user_email()

      assert {:ok, user} =
               Accounts.admin_create_user(admin_scope(), %{
                 "email" => email,
                 "name" => "Direct User",
                 "role" => "member",
                 "password" => "direct-password",
                 "password_confirmation" => "direct-password"
               })

      assert user.confirmed_at
      assert Accounts.get_user_by_email_and_password(email, "direct-password")
      assert_no_email_sent()
    end

    test "adds the user to a team with the chosen role" do
      team = team_fixture()

      assert {:ok, user} =
               Accounts.admin_create_user(admin_scope(), %{
                 "email" => unique_user_email(),
                 "name" => "Team User",
                 "role" => "member",
                 "password" => "direct-password",
                 "password_confirmation" => "direct-password",
                 "team_id" => Integer.to_string(team.id),
                 "team_role" => "member"
               })

      assert Teams.member_role(user, team) == :member
    end

    test "validates the password and the team" do
      assert {:error, changeset} =
               Accounts.admin_create_user(admin_scope(), %{
                 "email" => unique_user_email(),
                 "name" => "Weak User",
                 "role" => "member",
                 "password" => "short",
                 "password_confirmation" => "different"
               })

      assert %{password: [_ | _], password_confirmation: ["does not match password"]} =
               errors_on(changeset)

      email = unique_user_email()

      assert {:error, changeset} =
               Accounts.admin_create_user(admin_scope(), %{
                 "email" => email,
                 "name" => "No Team",
                 "role" => "member",
                 "password" => "direct-password",
                 "password_confirmation" => "direct-password",
                 "team_id" => "-1"
               })

      assert %{team_id: ["does not exist"]} = errors_on(changeset)
      refute Accounts.get_user_by_email(email)
    end

    test "rejects duplicate emails" do
      existing = user_fixture()

      assert {:error, changeset} =
               Accounts.admin_create_user(admin_scope(), %{
                 "email" => existing.email,
                 "name" => "Duplicate",
                 "role" => "member",
                 "password" => "direct-password",
                 "password_confirmation" => "direct-password"
               })

      assert %{email: ["has already been taken"]} = errors_on(changeset)
    end

    test "is only allowed for admins" do
      email = unique_user_email()

      assert {:error, :unauthorized} =
               Accounts.admin_create_user(user_scope_fixture(), %{
                 "email" => email,
                 "name" => "Sneaky Admin",
                 "role" => "admin",
                 "password" => "direct-password",
                 "password_confirmation" => "direct-password"
               })

      refute Accounts.get_user_by_email(email)
    end
  end

  describe "admin_update_user/3" do
    test "updates name, email, and role" do
      user = user_fixture()
      email = unique_user_email()

      assert {:ok, updated} =
               Accounts.admin_update_user(admin_scope(), user, %{
                 "name" => "Renamed",
                 "email" => email,
                 "role" => "admin"
               })

      assert updated.name == "Renamed"
      assert updated.email == email
      assert updated.role == :admin
    end

    test "ignores role changes on the acting admin" do
      admin = admin_fixture()

      assert {:ok, updated} =
               Accounts.admin_update_user(user_scope_fixture(admin), admin, %{
                 "name" => "Still Admin",
                 "role" => "member"
               })

      assert updated.name == "Still Admin"
      assert updated.role == :admin
    end

    test "rejects taken emails and invalid names" do
      user = user_fixture()
      other = user_fixture()

      assert {:error, changeset} =
               Accounts.admin_update_user(admin_scope(), user, %{
                 "email" => other.email,
                 "name" => "x"
               })

      assert %{email: ["has already been taken"], name: [_]} = errors_on(changeset)
    end

    test "changing a pending user's email invalidates their invitation link" do
      scope = admin_scope()
      invitation = invitation_fixture(scope.user)

      assert %Invitation{} = Accounts.get_pending_invitation(scope, invitation.user)

      {:ok, user} =
        Accounts.admin_update_user(scope, invitation.user, %{"email" => unique_user_email()})

      assert Accounts.get_pending_invitation(scope, user) == nil
      assert Accounts.get_invitation_by_token(invitation.token) == nil
    end

    test "returns an error instead of raising when the user was deleted" do
      user = user_fixture()
      {:ok, _} = Accounts.delete_user(user)

      assert {:error, changeset} =
               Accounts.admin_update_user(admin_scope(), user, %{"name" => "Ghost"})

      assert %{id: [_]} = errors_on(changeset)
    end

    test "is only allowed for admins" do
      user = user_fixture()

      assert {:error, :unauthorized} =
               Accounts.admin_update_user(user_scope_fixture(), user, %{"role" => "admin"})

      assert Accounts.get_user!(user.id).role == :member
    end
  end

  describe "admin_set_user_password/3" do
    test "activates a pending user and closes their invitation" do
      scope = admin_scope()
      invitation = invitation_fixture()
      user = invitation.user

      assert {:ok, {activated, _expired_tokens}} =
               Accounts.admin_set_user_password(scope, user, %{
                 "password" => "admin-set-password",
                 "password_confirmation" => "admin-set-password"
               })

      assert activated.confirmed_at
      assert Accounts.get_user_by_email_and_password(user.email, "admin-set-password")
      assert Repo.get!(Invitation, invitation.id).accepted_at
      assert Accounts.get_invitation_by_token(invitation.token) == nil
      assert Accounts.get_pending_invitation(scope, activated) == nil
    end

    test "resets an active user's password and ends their sessions" do
      user = user_fixture()
      session_token = Accounts.generate_user_session_token(user)

      assert {:ok, {_user, expired_tokens}} =
               Accounts.admin_set_user_password(admin_scope(), user, %{
                 "password" => "admin-set-password",
                 "password_confirmation" => "admin-set-password"
               })

      assert Enum.any?(expired_tokens, &(&1.token == session_token))
      assert Accounts.get_user_by_session_token(session_token) == nil
      refute Accounts.get_user_by_email_and_password(user.email, valid_user_password())
      assert Accounts.get_user_by_email_and_password(user.email, "admin-set-password")
    end

    test "keeps a pending user pending when the password is invalid" do
      invitation = invitation_fixture()

      assert {:error, changeset} =
               Accounts.admin_set_user_password(admin_scope(), invitation.user, %{
                 "password" => "short",
                 "password_confirmation" => "short"
               })

      assert %{password: [_]} = errors_on(changeset)
      assert Accounts.get_user!(invitation.user_id).confirmed_at == nil
      assert Accounts.get_invitation_by_token(invitation.token)
    end

    test "refuses the acting admin and non-admins" do
      scope = admin_scope()

      attrs = %{
        "password" => "admin-set-password",
        "password_confirmation" => "admin-set-password"
      }

      assert {:error, :self} = Accounts.admin_set_user_password(scope, scope.user, attrs)

      member = user_fixture()

      assert {:error, :unauthorized} =
               Accounts.admin_set_user_password(user_scope_fixture(), member, attrs)

      assert Accounts.get_user_by_email_and_password(member.email, valid_user_password())
    end
  end

  describe "get_pending_invitation/2" do
    test "returns the latest valid invitation for pending users only" do
      scope = admin_scope()
      invitation = invitation_fixture(scope.user)

      assert Accounts.get_pending_invitation(scope, invitation.user).id == invitation.id
      assert Accounts.get_pending_invitation(scope, user_fixture()) == nil

      {:ok, resent, _status} =
        Accounts.resend_user_invitation(scope.user, invitation.user, &"https://argus.test/#{&1}")

      assert Accounts.get_pending_invitation(scope, invitation.user).id == resent.id
    end

    test "returns nil once the invitation expired" do
      invitation = invitation_fixture()

      invitation
      |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(:second), -1, :second))
      |> Repo.update!()

      assert Accounts.get_pending_invitation(admin_scope(), invitation.user) == nil
    end

    test "hides links from non-admins" do
      invitation = invitation_fixture()
      assert Accounts.get_pending_invitation(user_scope_fixture(), invitation.user) == nil
    end
  end

  describe "list_user_session_tokens/1" do
    test "returns only the user's session tokens" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      _other = Accounts.generate_user_session_token(user_fixture())

      assert [%UserToken{token: ^token, context: "session"}] =
               Accounts.list_user_session_tokens(user)
    end
  end

  defp admin_scope, do: user_scope_fixture(admin_fixture())
end
