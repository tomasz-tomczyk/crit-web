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
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug CritWeb.Plugs.SecurityHeaders
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
    get "/self-hosting", PageController, :self_hosting
    get "/changelog", PageController, :changelog

    post "/set-name", ReviewController, :set_name
    post "/auth/login", AuthController, :login
    post "/auth/logout", AuthController, :logout
  end

  # Review pages and dashboard — noindex
  scope "/", CritWeb do
    pipe_through [:browser, :noindex]

    live_session :review, on_mount: [] do
      live "/r/:token", ReviewLive, :show
    end

    live_session :dashboard,
      on_mount: [],
      session: {CritWeb.DashboardLive, :session_opts, []} do
      live "/dashboard", DashboardLive, :index
    end
  end

  scope "/api", CritWeb do
    pipe_through [:api, :noindex, CritWeb.Plugs.LocalhostCors]

    options "/reviews", ApiController, :options
    post "/reviews", ApiController, :create
    delete "/reviews", ApiController, :delete_review

    get "/reviews/:token/document", ApiController, :document
    get "/reviews/:token/comments", ApiController, :comments_list

    get "/export/:token/review", ApiController, :export_review
    get "/export/:token/comments", ApiController, :export_comments
  end

  defp put_noindex(conn, _opts) do
    Plug.Conn.put_resp_header(conn, "x-robots-tag", "noindex")
  end
end
