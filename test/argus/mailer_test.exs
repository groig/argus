defmodule Argus.MailerTest do
  # Changes global mailer config.
  use Argus.DataCase, async: false

  import Argus.AccountsFixtures
  import Swoosh.TestAssertions

  alias Argus.Accounts
  alias Argus.Mailer

  describe "enabled?/0" do
    setup do
      mailer_config = Application.get_env(:argus, Mailer, [])
      local = Application.get_env(:swoosh, :local)

      on_exit(fn ->
        Application.put_env(:argus, Mailer, mailer_config)

        if is_nil(local),
          do: Application.delete_env(:swoosh, :local),
          else: Application.put_env(:swoosh, :local, local)
      end)

      %{mailer_config: mailer_config}
    end

    test "is true for the test adapter" do
      assert Mailer.enabled?()
    end

    test "is false for the local adapter without its mailbox storage, as in production without SMTP" do
      Application.put_env(:argus, Mailer, adapter: Swoosh.Adapters.Local)
      Application.put_env(:swoosh, :local, false)

      refute Mailer.enabled?()
    end

    test "is true for the local adapter with its mailbox, as in development" do
      Application.put_env(:argus, Mailer, adapter: Swoosh.Adapters.Local)
      Application.put_env(:swoosh, :local, true)

      assert Mailer.enabled?()
    end

    test "honours an explicit enabled flag", %{mailer_config: mailer_config} do
      Application.put_env(:argus, Mailer, Keyword.put(mailer_config, :enabled, false))
      refute Mailer.enabled?()
    end
  end

  describe "with email delivery disabled" do
    setup do
      disable_email_delivery()
    end

    test "invitations are created and report that no email was sent" do
      admin = admin_fixture()
      email = unique_user_email()

      assert {:ok, invitation, :disabled} =
               Accounts.deliver_user_invitation(
                 admin,
                 %{email: email, name: "Offline Invitee", role: "member"},
                 &"https://argus.test/invitations/#{&1}"
               )

      assert Accounts.get_invitation_by_token(invitation.token)
      assert_no_email_sent()
    end

    test "regenerating an invitation works without email" do
      admin = admin_fixture()
      invitation = invitation_fixture(admin)

      assert {:ok, resent, :disabled} =
               Accounts.resend_user_invitation(
                 admin,
                 invitation.user,
                 &"https://argus.test/invitations/#{&1}"
               )

      assert Accounts.get_invitation_by_token(resent.token)
      assert_no_email_sent()
    end

    test "password reset requests don't send anything" do
      user = user_fixture()

      assert {:error, :disabled} =
               Accounts.deliver_user_reset_password_instructions(
                 user,
                 &"https://argus.test/#{&1}"
               )

      assert_no_email_sent()
    end
  end
end
