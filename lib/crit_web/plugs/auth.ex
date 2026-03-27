defmodule CritWeb.Plugs.Auth do
  @moduledoc """
  Loads the current user from the session into conn assigns.
  Sets conn.assigns[:current_user] to a %Crit.User{} or nil.
  """

  import Plug.Conn
  alias Crit.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, "user_id") do
      nil ->
        assign(conn, :current_user, nil)

      user_id ->
        case Accounts.get_user(user_id) do
          {:ok, user} ->
            assign(conn, :current_user, user)

          {:error, :not_found} ->
            conn
            |> delete_session("user_id")
            |> assign(:current_user, nil)
        end
    end
  end
end
