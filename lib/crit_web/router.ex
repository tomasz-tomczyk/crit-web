defmodule CritWeb.Router do
  use CritWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CritWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug CritWeb.Plugs.Identity
    plug CritWeb.Plugs.SecurityHeaders
    plug CritWeb.Plugs.Auth
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug CritWeb.Plugs.SecurityHeaders
    plug CritWeb.Plugs.ApiAuth
  end

  pipeline :device_api do
    plug :accepts, ["json"]
    plug CritWeb.Plugs.SecurityHeaders
  end

  pipeline :auth_api do
    plug :accepts, ["json"]
    plug CritWeb.Plugs.SecurityHeaders
    plug CritWeb.Plugs.RequireBearerAuth
  end

  pipeline :noindex do
    plug :put_noindex
  end

  scope "/", CritWeb do
    get "/health", HealthController, :index
  end

  # Marketing pages — indexable by search engines
  scope "/", CritWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/features", PageController, :features
    get "/features/:slug", PageController, :feature
    get "/integrations", PageController, :integrations
    get "/terms", PageController, :terms
    get "/privacy", PageController, :privacy
    get "/getting-started", PageController, :getting_started
    get "/self-hosting", PageController, :self_hosting
    get "/changelog", PageController, :changelog

    post "/set-name", ReviewController, :set_name
    post "/auth/login", AuthController, :login
    post "/auth/logout", AuthController, :logout

    get "/auth/login", OAuthController, :request
    get "/auth/login/callback", OAuthController, :callback
    delete "/auth/logout", OAuthController, :delete
  end

  # CLI auth browser pages — noindexed
  scope "/", CritWeb do
    pipe_through [:browser, :noindex]

    get "/auth/cli", DeviceController, :index
    get "/auth/cli/authorize", DeviceController, :authorize
    post "/auth/cli/authorize", DeviceController, :confirm_authorize
    post "/auth/cli/cancel", DeviceController, :cancel
    get "/auth/cli/success", DeviceController, :success
  end

  # Review pages and dashboard — noindex
  scope "/", CritWeb do
    pipe_through [:browser, :noindex]

    live_session :review,
      on_mount: [],
      session: {CritWeb.ReviewLive, :session_opts, []} do
      live "/r/:token", ReviewLive, :show
    end

    live_session :user,
      on_mount: [{CritWeb.Live.Hooks, :require_user}],
      session: {CritWeb.Live.SessionHelper, :user_session_opts, []} do
      live "/dashboard", DashboardLive, :index
      live "/settings", SettingsLive, :index
    end

    live_session :admin,
      on_mount: [{CritWeb.Live.Hooks, :require_selfhosted_auth}],
      session: {CritWeb.Live.SessionHelper, :admin_session_opts, []} do
      live "/overview", OverviewLive, :index
    end
  end

  # Device flow API — unauthenticated (exempt from ApiAuth)
  scope "/api/device", CritWeb do
    pipe_through [:device_api, :noindex]

    post "/code", DeviceApiController, :create
    post "/token", DeviceApiController, :token
  end

  # Auth API — always requires Bearer token
  scope "/api/auth", CritWeb do
    pipe_through [:auth_api, :noindex]

    get "/whoami", AuthApiController, :whoami
    delete "/token", AuthApiController, :revoke
  end

  scope "/api", CritWeb do
    pipe_through [:api, :noindex, CritWeb.Plugs.LocalhostCors]

    options "/reviews", ApiController, :options
    post "/reviews", ApiController, :create
    delete "/reviews", ApiController, :delete_review
    put "/reviews/:token", ApiController, :update

    get "/reviews/:token/document", ApiController, :document
    get "/reviews/:token/comments", ApiController, :comments_list

    get "/export/:token/review", ApiController, :export_review
    get "/export/:token/comments", ApiController, :export_comments

    if Mix.env() in [:test, :dev] do
      post "/reviews/:token/seed-comment", ApiController, :seed_comment
      post "/reviews/:token/seed-reply/:comment_id", ApiController, :seed_reply
      post "/test/seed-user", ApiController, :seed_user
    end
  end

  defp put_noindex(conn, _opts) do
    Plug.Conn.put_resp_header(conn, "x-robots-tag", "noindex")
  end
end
