import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/argus start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :argus, ArgusWeb.Endpoint, server: true
end

config :argus, ArgusWeb.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "4000"))]

config :argus, Argus.Projects.IssueNotifier,
  webhook_url: System.get_env("ARGUS_ISSUE_WEBHOOK_URL"),
  req_options: []

config :argus, :ui,
  screenshot_mode: System.get_env("ARGUS_SCREENSHOT_MODE") in ~w(1 true TRUE yes)

maybe_put_env = fn config, key, env_var ->
  case System.get_env(env_var) do
    nil -> config
    "" -> config
    value -> Keyword.put(config, key, value)
  end
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :argus, Argus.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :argus, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :argus, ArgusWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  if smtp_relay = System.get_env("ARGUS_SMTP_RELAY") do
    smtp_hostname = System.get_env("ARGUS_SMTP_HOSTNAME") || host

    smtp_from_address =
      System.get_env("ARGUS_SMTP_FROM_ADDRESS") || System.get_env("ARGUS_SMTP_USERNAME") ||
        "argus@argus.local"

    smtp_config =
      [
        adapter: Swoosh.Adapters.SMTP,
        relay: smtp_relay,
        port: System.get_env("ARGUS_SMTP_PORT", "587"),
        ssl: System.get_env("ARGUS_SMTP_SSL", "false"),
        tls: System.get_env("ARGUS_SMTP_TLS", "if_available"),
        auth: System.get_env("ARGUS_SMTP_AUTH", "always"),
        hostname: smtp_hostname,
        from_name: System.get_env("ARGUS_SMTP_FROM_NAME", "Argus"),
        from_address: smtp_from_address,
        tls_options: [
          verify: :verify_peer,
          depth: 3,
          cacerts: :public_key.cacerts_get(),
          server_name_indication: String.to_charlist(smtp_relay),
          customize_hostname_check: [
            match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
          ],
          versions: [:"tlsv1.3", :"tlsv1.2"]
        ]
      ]
      |> maybe_put_env.(:username, "ARGUS_SMTP_USERNAME")
      |> maybe_put_env.(:password, "ARGUS_SMTP_PASSWORD")

    config :argus, Argus.Mailer, smtp_config
    config :swoosh, :api_client, false
  end

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :argus, ArgusWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :argus, ArgusWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # Set ARGUS_SMTP_RELAY to switch the mailer to Swoosh's SMTP adapter.
  # Common settings are:
  #
  #     ARGUS_SMTP_RELAY=smtp.example.com
  #     ARGUS_SMTP_PORT=587
  #     ARGUS_SMTP_USERNAME=mailer@example.com
  #     ARGUS_SMTP_PASSWORD=replace-me
  #     ARGUS_SMTP_TLS=always
  #     ARGUS_SMTP_SSL=false
  #     ARGUS_SMTP_AUTH=always
  #     ARGUS_SMTP_HOSTNAME=argus.example.com
  #     ARGUS_SMTP_FROM_NAME=Argus
  #     ARGUS_SMTP_FROM_ADDRESS=alerts@example.com
  #
  # Leave ARGUS_SMTP_RELAY unset if you want to keep email delivery disabled.
end
