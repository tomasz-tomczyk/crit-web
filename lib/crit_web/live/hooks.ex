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

  - `:require_authenticated_user` — requires an authenticated user on a self-hosted instance.
    Assigns `authenticated`, `current_user`, `oauth_configured`, and `password_required`.
    Redirects to `/` if selfhosted mode is not enabled.
  """
  def on_mount(:load_current_user, _params, session, socket) do
    current_user =
      case Map.get(session, "user_id") do
        nil ->
          nil

        user_id ->
          case Accounts.get_user(user_id) do
            {:ok, user} -> user
            {:error, :not_found} -> nil
          end
      end

    {:cont, assign(socket, :current_user, current_user)}
  end

  def on_mount(:require_authenticated_user, _params, session, socket) do
    if Application.get_env(:crit, :selfhosted) do
      password_required = Application.get_env(:crit, :admin_password) != nil
      admin_authenticated = Map.get(session, "admin_authenticated", false) == true

      current_user =
        case Map.get(session, "user_id") do
          nil ->
            nil

          user_id ->
            case Accounts.get_user(user_id) do
              {:ok, user} -> user
              {:error, :not_found} -> nil
            end
        end

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

  def on_mount(:require_user, _params, session, socket) do
    current_user =
      case Map.get(session, "user_id") do
        nil ->
          nil

        user_id ->
          case Accounts.get_user(user_id) do
            {:ok, user} -> user
            {:error, :not_found} -> nil
          end
      end

    if current_user do
      {:cont, assign(socket, :current_user, current_user)}
    else
      {:halt, redirect(socket, to: "/auth/login?return_to=/settings")}
    end
  end
end
