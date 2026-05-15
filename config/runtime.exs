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

# Comma-separated list of comment IDs that constitute the seeded demo review's
# canonical comments + replies. The export filter uses this to hide
# visitor-authored comments from the public API export. If a deployment
# configures :demo_review_token without this, the export silently returns
# zero comments — set DEMO_COMMENT_IDS to match the seed.
if demo_ids = System.get_env("DEMO_COMMENT_IDS") do
  ids = demo_ids |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
  config :crit, :demo_comment_ids, ids
end

if System.get_env("SELFHOSTED") in ~w(true 1) do
  config :crit, :selfhosted, true
end

# ADMIN_EMAILS: comma-separated list of email addresses that should have the
# instance admin role. Parsed into a list of trimmed, lowercased strings.
# This is the single source of truth for admin status — see
# `Crit.Authorization` and `Crit.Accounts.apply_role_for_email/1`.
admin_emails =
  case System.get_env("ADMIN_EMAILS") do
    nil ->
      []

    raw ->
      raw
      |> String.split(",", trim: true)
      |> Enum.map(&(&1 |> String.trim() |> String.downcase()))
      |> Enum.reject(&(&1 == ""))
  end

config :crit, :admin_emails, admin_emails

# Sentry — only active when SENTRY_DSN is set. With no DSN the SDK is a no-op,
# so self-hosted deployments make zero network calls to Sentry.
if sentry_dsn = System.get_env("SENTRY_DSN") do
  release =
    System.get_env("SENTRY_RELEASE") ||
      (Application.spec(:crit, :vsn) || ~c"") |> to_string()

  config :sentry,
    dsn: sentry_dsn,
    environment_name: System.get_env("SENTRY_ENV") || to_string(config_env()),
    release: release
end

# Optional separate DSN for the browser SDK. Injected into the page only when set.
if frontend_dsn = System.get_env("SENTRY_FRONTEND_DSN") do
  ingest_origin =
    case URI.parse(frontend_dsn) do
      %URI{scheme: scheme, host: host} when is_binary(scheme) and is_binary(host) ->
        "#{scheme}://#{host}"

      _ ->
        nil
    end

  config :crit, :sentry_frontend, %{
    dsn: frontend_dsn,
    environment: System.get_env("SENTRY_ENV") || "prod",
    release: System.get_env("SENTRY_RELEASE"),
    ingest_origin: ingest_origin
  }
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

# Local registration (email + password). Off by default — operators who want
# basic accounts opt in explicitly. Combine with OAuth or use standalone.
config :crit,
       :local_registration_enabled,
       System.get_env("LOCAL_REGISTRATION_ENABLED") in ~w(true 1)

if System.get_env("PHX_SERVER") do
  config :crit, CritWeb.Endpoint, server: true
end

# Trusted reverse-proxy header authentication.
#
# When set, crit-web reads the configured request header to discover the
# authenticated user's email (e.g. "X-Auth-Request-Email" from oauth2-proxy,
# "Cf-Access-Authenticated-User-Email" from Cloudflare Access). The header is
# trusted ONLY for requests from the configured CIDR ranges — without that
# guard, anyone reaching the app directly could spoof identity, so the boot
# validator below raises if the header is set without CIDRs.
case System.get_env("CRIT_TRUSTED_PROXY_USER_HEADER") do
  nil ->
    :ok

  "" ->
    :ok

  header ->
    config :crit, :trusted_proxy_user_header, header
end

case System.get_env("CRIT_TRUSTED_PROXY_CIDRS") do
  nil ->
    :ok

  "" ->
    :ok

  cidrs ->
    config :crit, :trusted_proxy_cidrs, Crit.Config.parse_cidrs(cidrs)
end

Crit.Config.validate_trusted_proxy!()

# LiveView transport selection. Default is "websocket"; set "longpoll" to skip
# the WebSocket attempt entirely when deploying behind a proxy known to break
# WS upgrades (e.g. some SSO/Envoy setups). See issue #50.
case System.get_env("CRIT_LIVEVIEW_TRANSPORT") do
  nil ->
    :ok

  "" ->
    :ok

  "websocket" ->
    config :crit, CritWeb.Endpoint, liveview_transport: "websocket"

  "longpoll" ->
    config :crit, CritWeb.Endpoint, liveview_transport: "longpoll"

  other ->
    raise "CRIT_LIVEVIEW_TRANSPORT must be \"websocket\" or \"longpoll\", got: #{inspect(other)}"
end

config :crit, CritWeb.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :prod do
  smtp_host = System.get_env("SMTP_HOST", "localhost")

  config :crit, Crit.Mailer,
    adapter: Swoosh.Adapters.SMTP,
    relay: smtp_host,
    port: String.to_integer(System.get_env("SMTP_PORT", "587")),
    username: System.get_env("SMTP_USERNAME"),
    password: System.get_env("SMTP_PASSWORD"),
    tls: :if_available,
    auth: :if_available,
    tls_options: [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      server_name_indication: String.to_charlist(smtp_host),
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ],
      depth: 3
    ]

  if from = System.get_env("SMTP_FROM") do
    config :crit, :smtp_from, from
  end

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

  # Handle unix socket DATABASE_URLs (e.g. Cloud SQL on Google Cloud Run):
  #   postgresql://role:pw@/dbname?host=/cloudsql/project:region:instance
  # Ecto's URL parser rejects URLs without a hostname (host: nil),
  # so we parse the URL ourselves and pass options directly to Postgrex.
  pool_size = String.to_integer(System.get_env("POOL_SIZE") || "10")

  repo_opts =
    case URI.parse(database_url) do
      %URI{query: query} = uri when is_binary(query) ->
        params = URI.decode_query(query)

        case params["host"] do
          "/" <> _ = socket_path ->
            {user, password} =
              case uri.userinfo do
                nil ->
                  {nil, nil}

                info ->
                  case String.split(info, ":", parts: 2) do
                    [u, p] -> {URI.decode(u), URI.decode(p)}
                    [u] -> {URI.decode(u), nil}
                  end
              end

            database = String.trim_leading(uri.path || "", "/")

            [
              username: user,
              password: password,
              database: database,
              socket_dir: socket_path,
              ssl: false,
              pool_size: pool_size
            ]

          _ ->
            [url: database_url, ssl: ssl_opts, pool_size: pool_size, socket_options: maybe_ipv6]
        end

      _ ->
        [url: database_url, ssl: ssl_opts, pool_size: pool_size, socket_options: maybe_ipv6]
    end

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
