defmodule Argus.AccountsTest do
  use Argus.DataCase

  import Swoosh.TestAssertions

  alias Argus.Accounts
  alias Argus.Accounts.{Invitation, User, UserToken}
  alias Argus.Repo

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

      {:ok, invitation} =
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

      {:ok, resent_invitation} =
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
end
