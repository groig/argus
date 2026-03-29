defmodule Argus.Mailer do
  use Swoosh.Mailer, otp_app: :argus

  def from do
    config = Application.get_env(:argus, __MODULE__, [])

    {
      Keyword.get(config, :from_name, "Argus"),
      Keyword.get(config, :from_address, "argus@argus.local")
    }
  end
end
