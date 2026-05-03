# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :crit,
  ecto_repos: [Crit.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# Configure the endpoint
config :crit, CritWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: CritWeb.ErrorHTML, json: CritWeb.ErrorJSON],
    layout: {CritWeb.Layouts, :root}
  ],
  pubsub_server: Crit.PubSub,
  live_view: [signing_salt: "WyzCaSCk"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  crit: [
    args:
      ~w(js/app.js --bundle --splitting --format=esm --target=esnext --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ],
  share_receiver: [
    args:
      ~w(js/share_receiver/index.js --bundle --format=iife --target=es2020 --outdir=../priv/static/assets/js/share_receiver),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  crit: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Sentry — disabled by default; enabled at runtime when SENTRY_DSN is set.
# Self-hosted deployments without a DSN incur no network calls.
config :sentry,
  dsn: nil,
  environment_name: config_env(),
  enable_source_code_context: true,
  root_source_code_paths: [File.cwd!()],
  in_app_otp_apps: [:crit],
  client: Crit.SentryHTTPClient,
  before_send: {Crit.SentryFilter, :before_send}

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
