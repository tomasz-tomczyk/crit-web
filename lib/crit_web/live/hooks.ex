defmodule CritWeb.Live.Hooks do
  @moduledoc """
  Shared on_mount hooks for LiveViews.
  """

  import Phoenix.LiveView
  import Phoenix.Component

  alias Crit.Accounts

  @doc """
  Shared on_mount callbacks for LiveViews.

  ## Hooks

  - `:load_current_user` — loads the current user from the session into socket assigns.
    Sets `current_user` to a `%Crit.User{}` or `nil`.

  - `:require_user` — requires a logged-in user (via OAuth). Redirects to
    `/auth/login?return_to=<current_path>` if not logged in. Redirects to `/` if
    no OAuth configured.

  - `:require_selfhosted_auth` — requires an authenticated user on a self-hosted instance.
    Assigns `authenticated`, `current_user`, `oauth_configured`, and `password_required`.
    Redirects to `/` if selfhosted mode is not enabled.
  """
  def on_mount(:load_current_user, _params, session, socket) do
    current_user = load_user(session)

    {:cont, assign(socket, :current_user, current_user)}
  end

  def on_mount(:require_selfhosted_auth, _params, session, socket) do
    selfhosted_auth(session, socket)
  end

  def on_mount(:require_user, _params, session, socket) do
    current_user = load_user(session)

    if current_user do
      {:cont, assign(socket, :current_user, current_user)}
    else
      if Application.get_env(:crit, :oauth_provider) do
        request_path = Map.get(session, "request_path", "/dashboard")
        {:halt, redirect(socket, to: "/auth/login?return_to=#{request_path}")}
      else
        {:halt, redirect(socket, to: "/")}
      end
    end
  end

  defp selfhosted_auth(session, socket) do
    if Application.get_env(:crit, :selfhosted) do
      password_required = Application.get_env(:crit, :admin_password) != nil
      admin_authenticated = Map.get(session, "admin_authenticated", false) == true
      current_user = load_user(session)
      oauth_configured = Application.get_env(:crit, :oauth_provider) != nil

      authenticated =
        cond do
          oauth_configured -> current_user != nil
          password_required -> admin_authenticated
          true -> true
        end

      {:cont,
       socket
       |> assign(:password_required, password_required)
       |> assign(:authenticated, authenticated)
       |> assign(:current_user, current_user)
       |> assign(:oauth_configured, oauth_configured)}
    else
      {:halt, redirect(socket, to: "/")}
    end
  end

  defp load_user(session) do
    case Map.get(session, "user_id") do
      nil ->
        nil

      user_id ->
        case Accounts.get_user(user_id) do
          {:ok, user} -> user
          {:error, :not_found} -> nil
        end
    end
  end
end
