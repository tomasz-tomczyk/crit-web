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
#     PHX_SERVER=true bin/crit start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if demo_token = System.get_env("DEMO_REVIEW_TOKEN") do
  config :crit, :demo_review_token, demo_token
end

if System.get_env("SELFHOSTED") in ~w(true 1) do
  config :crit, :selfhosted, true
end

if admin_password = System.get_env("ADMIN_PASSWORD") do
  config :crit, :admin_password, admin_password
end

# OAuth provider — configure exactly one provider per deployment.
#
# Hosted (GitHub):
#   GITHUB_CLIENT_ID=...  GITHUB_CLIENT_SECRET=...
#
# Self-hosted (any OIDC provider — Google, GitLab, Keycloak, etc.):
#   OAUTH_CLIENT_ID=...  OAUTH_CLIENT_SECRET=...  OAUTH_BASE_URL=https://accounts.google.com
#
cond do
  System.get_env("GITHUB_CLIENT_ID") ->
    config :crit, :oauth_provider,
      strategy: Assent.Strategy.Github,
      client_id: System.get_env("GITHUB_CLIENT_ID"),
      client_secret: System.get_env("GITHUB_CLIENT_SECRET")

  System.get_env("OAUTH_CLIENT_ID") ->
    config :crit, :oauth_provider,
      strategy: Assent.Strategy.OIDC,
      client_id: System.get_env("OAUTH_CLIENT_ID"),
      client_secret: System.get_env("OAUTH_CLIENT_SECRET"),
      base_url: System.get_env("OAUTH_BASE_URL"),
      authorization_params: [scope: "openid email profile"]

  true ->
    :ok
end

if System.get_env("PHX_SERVER") do
  config :crit, CritWeb.Endpoint, server: true
end

config :crit, CritWeb.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      case {
        System.get_env("DB_HOST"),
        System.get_env("DB_USER"),
        System.get_env("DB_PASSWORD"),
        System.get_env("DB_NAME")
      } do
        {host, user, password, name}
        when is_binary(host) and is_binary(user) and is_binary(password) and is_binary(name) ->
          port = System.get_env("DB_PORT", "5432")
          "ecto://#{user}:#{password}@#{host}:#{port}/#{name}"

        _ ->
          raise """
          Database connection not configured. Set either:
            DATABASE_URL=ecto://USER:PASS@HOST/DATABASE
          or all of:
            DB_HOST, DB_USER, DB_PASSWORD, DB_NAME (and optionally DB_PORT, default 5432)
          """
      end

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  ssl_opts =
    if System.get_env("DB_SSL") in ~w(true 1) do
      case System.get_env("DB_SSL_CA_CERT") do
        nil -> [verify: :verify_none]
        path -> [verify: :verify_peer, cacertfile: path]
      end
    else
      false
    end

  # Handle Cloud SQL unix socket format used by Taskforce Vibe:
  #   postgresql://role:pw@/dbname?host=/cloudsql/project:region:instance
  # Ecto's URL parser rejects URLs without a hostname (host: nil),
  # so for Cloud SQL we parse the URL ourselves into individual options.
  repo_opts =
    case URI.parse(database_url) do
      %URI{query: query} = uri when is_binary(query) ->
        params = URI.decode_query(query)

        case params["host"] do
          "/cloudsql/" <> _ = socket_path ->
            [user, password] =
              case uri.userinfo do
                nil -> [nil, nil]
                info -> String.split(info, ":", parts: 2)
              end

            database = String.trim_leading(uri.path || "", "/")

            [
              username: user,
              password: password,
              database: database,
              socket_dir: socket_path
            ]

          _ ->
            [url: database_url]
        end

      _ ->
        [url: database_url]
    end

  repo_opts =
    repo_opts ++
      [
        ssl: ssl_opts,
        pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
        socket_options: maybe_ipv6
      ]

  config :crit, Crit.Repo, repo_opts

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by running: openssl rand -base64 64
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :crit, :canonical_host, host
  config :crit, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  scheme = System.get_env("PHX_SCHEME", "https")

  url_port =
    String.to_integer(
      System.get_env("PHX_URL_PORT", if(scheme == "https", do: "443", else: "80"))
    )

  if System.get_env("FORCE_SSL") in ~w(true 1) do
    config :crit, CritWeb.Endpoint,
      force_ssl: [
        rewrite_on: [:x_forwarded_proto],
        exclude: [hosts: ["localhost", "127.0.0.1"]]
      ]
  end

  config :crit, CritWeb.Endpoint,
    url: [host: host, port: url_port, scheme: scheme],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :crit, CritWeb.Endpoint,
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
  #     config :crit, CritWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
