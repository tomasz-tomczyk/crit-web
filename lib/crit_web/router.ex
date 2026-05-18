defmodule CritWeb.Router do
  use CritWeb, :router

  import CritWeb.UserAuth, only: [fetch_current_scope_for_user: 2]

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CritWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug CritWeb.Plugs.SecurityHeaders
    plug CritWeb.Plugs.RateLimit
    plug :fetch_current_scope_for_user
    plug CritWeb.Plugs.TrustedProxyAuth
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug CritWeb.Plugs.SecurityHeaders
    plug CritWeb.Plugs.RateLimit, response: :json
    plug CritWeb.Plugs.ApiAuth
  end

  pipeline :device_api do
    plug :accepts, ["json"]
    plug CritWeb.Plugs.SecurityHeaders
    plug CritWeb.Plugs.RateLimit, response: :json
  end

  pipeline :auth_api do
    plug :accepts, ["json"]
    plug CritWeb.Plugs.SecurityHeaders
    plug CritWeb.Plugs.RateLimit, response: :json
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
    get "/integrations/build-your-own", PageController, :build_integration
    get "/integrations/:tool", PageController, :integration
    get "/terms", PageController, :terms
    get "/privacy", PageController, :privacy
    get "/getting-started", PageController, :getting_started
    get "/self-hosting", PageController, :self_hosting
    get "/changelog", PageController, :changelog
    get "/modes/:mode", PageController, :mode
    get "/sitemap.xml", PageController, :sitemap_xml
    get "/robots.txt", PageController, :robots_txt

    post "/set-name", ReviewController, :set_name
    # GET /auth/login = OAuth provider redirect (initiates the OAuth flow).
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

    get "/r/:token/raw/*file_path", RawController, :show
    get "/share-receiver", ShareReceiverController, :index
  end

  # Review page — visibility-driven noindex/referrer is set in the layout via
  # assigns from ReviewLive.mount/3
  scope "/", CritWeb do
    pipe_through :browser

    live_session :review,
      on_mount: [{CritWeb.UserAuth, :require_review_scope}],
      session: {CritWeb.ReviewLive, :session_opts, []} do
      live "/r/:token", ReviewLive, :show
    end
  end

  # Dashboard / settings / admin — always noindex
  scope "/", CritWeb do
    pipe_through [:browser, :noindex]

    live_session :user,
      on_mount: [{CritWeb.UserAuth, :require_authenticated_user}],
      session: {CritWeb.Live.SessionHelper, :user_session_opts, []} do
      live "/dashboard", DashboardLive, :index
      live "/reviews", ReviewsLive, :index
      live "/settings", SettingsLive, :index
      live "/orgs", Org.SelectLive, :index
      live "/orgs/new", Org.NewLive, :index
      live "/invites/:token", Org.InviteAcceptLive, :index
    end

    live_session :org,
      on_mount: [
        {CritWeb.UserAuth, :require_authenticated_user},
        {CritWeb.UserAuth, :ensure_org}
      ],
      session: {CritWeb.Live.SessionHelper, :user_session_opts, []} do
      live "/orgs/:org_slug", Org.OverviewLive, :index
      live "/orgs/:org_slug/reviews", Org.ReviewsLive, :index
      live "/orgs/:org_slug/members", Org.MembersLive, :index
    end

    live_session :org_admin,
      on_mount: [
        {CritWeb.UserAuth, :require_authenticated_user},
        {CritWeb.UserAuth, :ensure_org},
        {CritWeb.UserAuth, :require_org_admin}
      ],
      session: {CritWeb.Live.SessionHelper, :user_session_opts, []} do
      live "/orgs/:org_slug/settings", Org.SettingsLive, :index
    end

    post "/invites/:token/accept", OrgSessionController, :accept_invite
    post "/invites/:id/accept-direct", OrgSessionController, :accept_invite_direct

    live_session :admin,
      on_mount: [{CritWeb.UserAuth, :require_selfhosted_auth}],
      session: {CritWeb.Live.SessionHelper, :admin_session_opts, []} do
      live "/overview", OverviewLive, :index
    end
  end

  # Admin panel — selfhosted-only. Gated by both the SelfhostedOnly plug and
  # the `:require_admin` on_mount hook (the latter via ADMIN_EMAILS).
  scope "/", CritWeb do
    pipe_through [:browser, :noindex, CritWeb.Plugs.SelfhostedOnly]

    live_session :admin_panel,
      on_mount: [
        {CritWeb.UserAuth, :require_authenticated_user},
        {CritWeb.UserAuth, :require_admin}
      ],
      session: {CritWeb.Live.SessionHelper, :user_session_opts, []} do
      live "/admin/users", AdminUsersLive, :index
      live "/admin/settings", AdminSettingsLive, :index
    end
  end

  # Local-auth routes — only mounted on selfhosted instances.
  scope "/", CritWeb do
    pipe_through [
      :browser,
      :noindex,
      CritWeb.Plugs.SelfhostedOnly,
      CritWeb.Plugs.AuthRateLimit
    ]

    post "/users/log_in", UserSessionController, :create
    delete "/users/log_out", UserSessionController, :delete

    live_session :current_user,
      on_mount: [{CritWeb.UserAuth, :mount_current_scope_for_user}] do
      live "/users/log_in", UserLoginLive, :new
    end
  end

  # Local-auth registration — gated by both selfhosted and local-registration flags.
  scope "/", CritWeb do
    pipe_through [
      :browser,
      :noindex,
      CritWeb.Plugs.SelfhostedOnly,
      CritWeb.Plugs.RegistrationEnabled,
      CritWeb.Plugs.AuthRateLimit
    ]

    post "/users/register", UserSessionController, :register

    live_session :registration,
      on_mount: [{CritWeb.UserAuth, :mount_current_scope_for_user}] do
      live "/users/register", UserRegistrationLive, :new
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
    get "/orgs", AuthApiController, :orgs
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
  end

  # Dev/test-only seed endpoints. Kept in a separate scope without ApiAuth
  # so integration tests can mint users + comments on a selfhosted
  # OAuth-enforced instance (where the regular /api scope returns 401 for
  # anonymous requests). Compiled out of :prod entirely.
  if Mix.env() in [:test, :dev] do
    scope "/api", CritWeb do
      pipe_through [:device_api, :noindex]

      post "/reviews/:token/seed-comment", ApiController, :seed_comment
      post "/reviews/:token/seed-reply/:comment_id", ApiController, :seed_reply
      post "/reviews/:token/seed-resolve/:comment_id", ApiController, :seed_resolve
      post "/test/seed-user", ApiController, :seed_user
      post "/test/seed-org", ApiController, :seed_org
    end
  end

  if Mix.env() == :dev do
    scope "/dev" do
      pipe_through :browser
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  defp put_noindex(conn, _opts) do
    conn
    |> Plug.Conn.put_resp_header("x-robots-tag", "noindex")
    |> Plug.Conn.put_resp_header("referrer-policy", "no-referrer")
  end
end
