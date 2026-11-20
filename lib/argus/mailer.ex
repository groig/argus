defmodule Argus.Mailer do
  use Swoosh.Mailer, otp_app: :argus

  require Logger

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

  @doc """
  Delivers `email` without ever raising into the caller.

  Every sender goes through this: email always goes out after the database write it reports on,
  so a missing or broken mailer must not undo or crash that work. Returns `{:error, :disabled}`
  when `enabled?/0` is false. Failures are logged by subject and a summarised reason only,
  because the email body can carry invitation or password reset tokens.
  """
  def try_deliver(%Swoosh.Email{} = email) do
    if enabled?() do
      case safe_deliver(email) do
        {:ok, metadata} ->
          {:ok, metadata}

        {:error, reason} ->
          Logger.warning(
            "Could not deliver email #{inspect(email.subject)}: " <>
              inspect(reason, limit: 10, printable_limit: 120)
          )

          {:error, reason}
      end
    else
      {:error, :disabled}
    end
  end

  defp safe_deliver(email) do
    deliver(email)
  catch
    kind, reason -> {:error, {kind, summarize(reason)}}
  end

  # Exit reasons from GenServer-backed adapters embed the call arguments, which include the
  # email itself; exceptions such as MatchError embed the offending term. Keep only the shape.
  defp summarize({reason, {module, function, args}})
       when is_atom(module) and is_atom(function) and is_list(args),
       do: {summarize(reason), {module, function, length(args)}}

  defp summarize(%{__exception__: true} = exception), do: exception.__struct__
  defp summarize(reason) when is_atom(reason), do: reason
  defp summarize(_reason), do: :unknown
end
