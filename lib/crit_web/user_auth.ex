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
          {nil, conn}

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
    * `:require_selfhosted_auth` — selfhosted-instance gate.
  """
  def on_mount(:mount_current_scope_for_user, _params, session, socket) do
    {:cont, assign_scope(socket, session)}
  end

  def on_mount(:require_authenticated_user, _params, session, socket) do
    socket = assign_scope(socket, session)

    if socket.assigns.current_scope.user do
      {:cont, socket}
    else
      if Application.get_env(:crit, :oauth_provider) do
        request_path = Map.get(session, "request_path", "/dashboard")
        {:halt, redirect(socket, to: "/auth/login?return_to=#{request_path}")}
      else
        {:halt, redirect(socket, to: "/")}
      end
    end
  end

  def on_mount(:require_selfhosted_auth, _params, session, socket) do
    if Application.get_env(:crit, :selfhosted) do
      socket = assign_scope(socket, session)
      password_required = Application.get_env(:crit, :admin_password) != nil
      admin_authenticated = Map.get(session, "admin_authenticated", false) == true
      oauth_configured = Application.get_env(:crit, :oauth_provider) != nil

      authenticated =
        cond do
          oauth_configured -> socket.assigns.current_scope.user != nil
          password_required -> admin_authenticated
          true -> true
        end

      {:cont,
       socket
       |> Phoenix.Component.assign(:password_required, password_required)
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
