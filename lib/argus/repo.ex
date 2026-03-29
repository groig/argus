defmodule Argus.Repo do
  use Ecto.Repo,
    otp_app: :argus,
    adapter: Ecto.Adapters.Postgres
end
