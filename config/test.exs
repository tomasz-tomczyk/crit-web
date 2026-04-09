import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :crit, Crit.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "crit_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :crit, CritWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "Sg3AbYy0ombvmL33BiB7bfASWI/y6HNgUzvV1JFennme5U8HK2EJBDouMeFYehBc",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Don't start the background cleaner in tests — tests start their own supervised instance
config :crit, start_review_cleaner: false
config :crit, start_device_code_cleaner: false
config :crit, start_changelog: false
config :crit, start_integrations: false

config :crit, :oauth_provider,
  strategy: Assent.Strategy.Github,
  client_id: "test_github_client_id",
  client_secret: "test_github_client_secret"
