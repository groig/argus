defmodule Argus.Mailer do
  use Swoosh.Mailer, otp_app: :argus

  def from do
    config = Application.get_env(:argus, __MODULE__, [])

    {
      Keyword.get(config, :from_name, "Argus"),
      Keyword.get(config, :from_address, "argus@argus.local")
    }
  end

  @doc """
  Whether Argus can actually send email.

  Production without `ARGUS_SMTP_RELAY` keeps the local adapter while Swoosh's in-memory
  storage is disabled, so nothing could receive the message. Admin flows use this to fall back
  to copyable links instead of promising an email. Set `enabled: false` in the mailer config to
  force the fallback.
  """
  def enabled? do
    config = Application.get_env(:argus, __MODULE__, [])

    case Keyword.fetch(config, :enabled) do
      {:ok, enabled} ->
        enabled == true

      :error ->
        not (Keyword.get(config, :adapter) == Swoosh.Adapters.Local and
               Application.get_env(:swoosh, :local, true) == false)
    end
  end
end
