defmodule Argus.Accounts.UserNotifier do
  import Swoosh.Email

  alias Argus.Mailer
  alias Argus.Accounts.{Invitation, User}

  defp deliver(recipient, subject, text_body, html_body) do
    email =
      new()
      |> to(recipient)
      |> from(Mailer.from())
      |> subject(subject)
      |> text_body(text_body)
      |> html_body(html_body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  def deliver_invitation_instructions(%Invitation{} = invitation, %User{} = inviter, url) do
    text_body = """
    #{invitation.email},

    #{inviter.name} invited you to Argus.

    Finish setting up your account:
    #{url}

    This link expires in 72 hours.
    """

    html_body = """
    <div style="font-family: ui-sans-serif, system-ui, sans-serif; color: #111827; line-height: 1.6; max-width: 560px; margin: 0 auto; padding: 24px;">
      <p style="margin: 0 0 12px 0;">#{invitation.email},</p>
      <p style="margin: 0 0 18px 0;"><strong>#{inviter.name}</strong> invited you to Argus.</p>
      <p style="margin: 0 0 24px 0;">
        <a href="#{url}" style="display: inline-block; background: #111827; color: #ffffff; text-decoration: none; border-radius: 9999px; padding: 12px 18px; font-weight: 600;">Accept invitation</a>
      </p>
      <p style="margin: 0; color: #6b7280;">This link expires in 72 hours.</p>
    </div>
    """

    deliver(invitation.email, "You're invited to Argus", text_body, html_body)
  end
end
