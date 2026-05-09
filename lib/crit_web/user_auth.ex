defmodule CritWeb.UserAuth do
  @moduledoc """
  Conn-side plug and LiveView on_mount callbacks that build the current
  `%Crit.Accounts.Scope{}` and assign it as `:current_scope`.
  """

  use CritWeb, :verified_routes

  import Plug.Conn
  import Phoenix.LiveView, only: [redirect: 2]

  alias Crit.Accounts
  alias Crit.Accounts.Scope

  @remember_me_cookie "_crit_web_user_remember_me"
  @remember_me_options [sign: true, max_age: 60 * 60 * 24 * 60, same_site: "Lax"]

  # ---------------------------------------------------------------------------
  # Session login / logout
  # ---------------------------------------------------------------------------

  @doc """
  Logs the user in via session, optionally setting a remember-me cookie.

  `params` may include `"remember_me" => "true"`.
  """
  def log_in_user(conn, user, params \\ %{}) do
    conn
    |> renew_session()
    |> put_session("user_id", user.id)
    |> put_session(:live_socket_id, "users_sessions:#{Base.url_encode64(user.id)}")
    |> maybe_write_remember_me(user, params)
  end

  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  defp maybe_write_remember_me(conn, user, %{"remember_me" => "true"}) do
    {plaintext, struct} =
      Crit.Accounts.UserToken.build_hashed_token(user, "remember_me", user.email)

    Crit.Repo.insert!(struct)
    put_resp_cookie(conn, @remember_me_cookie, plaintext, @remember_me_options)
  end

  defp maybe_write_remember_me(conn, _user, _), do: conn

  @doc "Clears session + remember-me cookie. Deletes the remember-me token if present."
  def log_out_user(conn) do
    user_id = get_session(conn, "user_id")

    if user_id do
      case Accounts.get_user(user_id) do
        {:ok, user} ->
          Crit.Repo.delete_all(
            Crit.Accounts.UserToken.by_user_and_contexts_query(user, ["remember_me"])
          )

        _ ->
          :ok
      end
    end

    conn
    |> renew_session()
    |> delete_resp_cookie(@remember_me_cookie)
  end

  # ---------------------------------------------------------------------------
  # Plug
  # ---------------------------------------------------------------------------

  @doc """
  Plug that:
    1. Ensures the session has an `identity` UUID (every browser session has one).
    2. Builds a `%Scope{}` from session and assigns it as `:current_scope`.
    3. Clears stale `user_id` from the session if the user no longer exists.
  """
  def fetch_current_scope_for_user(conn, _opts) do
    conn = ensure_session_identity(conn)
    user_id = get_session(conn, "user_id")

    {user, conn} =
      case user_id do
        nil ->
          fetch_user_from_remember_me_cookie(conn)

        id ->
          case Accounts.get_user(id) do
            {:ok, user} -> {user, conn}
            {:error, :not_found} -> {nil, delete_session(conn, "user_id")}
          end
      end

    scope =
      case user do
        nil ->
          %Scope{
            user: nil,
            identity: get_session(conn, "identity"),
            display_name: get_session(conn, "display_name")
          }

        %_{} = u ->
          Scope.for_user(u)
      end

    Plug.Conn.assign(conn, :current_scope, scope)
  end

  # Looks up a user from the signed remember-me cookie when the session has no
  # user_id. On hit, refreshes the session (puts user_id, renews session id).
  # On miss with a cookie present, deletes the cookie so subsequent requests
  # don't keep retrying.
  defp fetch_user_from_remember_me_cookie(conn) do
    conn = fetch_cookies(conn, signed: [@remember_me_cookie])

    case conn.cookies[@remember_me_cookie] do
      plaintext when is_binary(plaintext) ->
        case Accounts.get_user_by_remember_me_token(plaintext) do
          {:ok, user} ->
            conn =
              conn
              |> renew_session()
              |> put_session("user_id", user.id)
              |> put_session(:live_socket_id, "users_sessions:#{Base.url_encode64(user.id)}")

            {user, conn}

          {:error, :not_found} ->
            {nil, delete_resp_cookie(conn, @remember_me_cookie)}
        end

      _ ->
        {nil, conn}
    end
  end

  defp ensure_session_identity(conn) do
    if get_session(conn, "identity") do
      conn
    else
      put_session(conn, "identity", Ecto.UUID.generate())
    end
  end

  # ---------------------------------------------------------------------------
  # on_mount
  # ---------------------------------------------------------------------------

  @doc """
  on_mount hooks:

    * `:mount_current_scope_for_user` — assigns `:current_scope` from session.
    * `:require_authenticated_user` — assigns scope; halts and redirects to
      `/auth/login?return_to=<request_path>` when user missing and OAuth
      configured. Falls back to `/` when OAuth is not configured.
    * `:require_review_scope` — assigns `:current_scope`. When the instance is
      selfhosted AND an `oauth_provider` is configured, redirects unauthenticated
      visitors to the OAuth login flow with `return_to` set to the current
      request path. Otherwise (public/hosted, or selfhosted without OAuth) lets
      the request through with `current_scope.user` possibly nil.
    * `:require_selfhosted_auth` — selfhosted-instance gate.
  """
  def on_mount(:mount_current_scope_for_user, _params, session, socket) do
    {:cont, assign_scope(socket, session)}
  end

  def on_mount(:require_review_scope, _params, session, socket) do
    socket = assign_scope(socket, session)

    cond do
      socket.assigns.current_scope.user ->
        {:cont, socket}

      Crit.Config.selfhosted_oauth?() ->
        return_to = Map.get(session, "request_path", "/")
        {:halt, redirect(socket, to: "/auth/login?return_to=#{URI.encode_www_form(return_to)}")}

      true ->
        {:cont, socket}
    end
  end

  def on_mount(:require_authenticated_user, _params, session, socket) do
    socket = assign_scope(socket, session)

    if socket.assigns.current_scope.user do
      {:cont, socket}
    else
      request_path = Map.get(session, "request_path", "/dashboard")
      encoded = URI.encode_www_form(request_path)

      cond do
        Application.get_env(:crit, :selfhosted) ->
          # Selfhosted always lands on /users/log_in. The login page renders
          # the OAuth button when `oauth_configured?` so the user can pick.
          {:halt, redirect(socket, to: "/users/log_in?return_to=#{encoded}")}

        Crit.Config.oauth_configured?() ->
          {:halt, redirect(socket, to: "/auth/login?return_to=#{encoded}")}

        true ->
          {:halt, redirect(socket, to: "/")}
      end
    end
  end

  def on_mount(:require_admin, _params, _session, socket) do
    if Crit.Accounts.Scope.admin?(socket.assigns.current_scope) do
      {:cont, socket}
    else
      {:halt,
       socket
       |> Phoenix.LiveView.put_flash(:error, "Admins only.")
       |> redirect(to: "/dashboard")}
    end
  end

  def on_mount(:require_selfhosted_auth, _params, session, socket) do
    if Application.get_env(:crit, :selfhosted) do
      socket = assign_scope(socket, session)
      authenticated = socket.assigns.current_scope.user != nil
      oauth_configured = Crit.Config.oauth_configured?()

      {:cont,
       socket
       |> Phoenix.Component.assign(:authenticated, authenticated)
       |> Phoenix.Component.assign(:oauth_configured, oauth_configured)}
    else
      {:halt, redirect(socket, to: "/")}
    end
  end

  defp assign_scope(socket, session) do
    Phoenix.Component.assign(socket, :current_scope, Scope.for_session(session))
  end
end
