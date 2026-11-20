defmodule Argus.MailerTest.ExitingStorage do
  @moduledoc false
  # Stands in for Swoosh's local mailbox when its process is down: the exit reason carries the
  # call arguments, email included, like a real `GenServer.call` to a missing process.
  def push(email), do: exit({:noproc, {GenServer, :call, [__MODULE__, {:push, email}, 5000]}})
end

defmodule Argus.MailerTest do
  # Changes global mailer config.
  use Argus.DataCase, async: false

  import Argus.AccountsFixtures
  import ExUnit.CaptureLog
  import Swoosh.TestAssertions

  alias Argus.Accounts
  alias Argus.Accounts.UserToken
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

  describe "try_deliver/1" do
    setup do
      mailer_config = Application.get_env(:argus, Mailer, [])
      on_exit(fn -> Application.put_env(:argus, Mailer, mailer_config) end)
      :ok
    end

    test "turns adapter crashes into errors without logging the email" do
      Application.put_env(:argus, Mailer,
        adapter: Swoosh.Adapters.Local,
        storage_driver: Argus.MailerTest.ExitingStorage,
        enabled: true
      )

      email =
        Swoosh.Email.new(
          to: "someone@example.com",
          from: "argus@example.com",
          subject: "Reset your Argus password",
          text_body: "https://argus.test/reset-password/SECRET-TOKEN"
        )

      log =
        capture_log(fn ->
          assert {:error, {:exit, {:noproc, {GenServer, :call, 3}}}} = Mailer.try_deliver(email)
        end)

      assert log =~ "Reset your Argus password"
      refute log =~ "SECRET-TOKEN"
      refute log =~ "someone@example.com"
    end

    test "returns :disabled without touching the adapter" do
      disable_email_delivery()
      assert {:error, :disabled} = Mailer.try_deliver(Swoosh.Email.new(subject: "Hi"))
      assert_no_email_sent()
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

    test "password reset requests don't send anything or create undeliverable tokens" do
      user = user_fixture()

      assert {:error, :disabled} =
               Accounts.deliver_user_reset_password_instructions(
                 user,
                 &"https://argus.test/#{&1}"
               )

      refute Repo.get_by(UserToken, user_id: user.id, context: "reset_password")

      assert_no_email_sent()
    end
  end
end
