defmodule CritWeb.Live.SessionHelper do
  @moduledoc """
  Shared session callbacks for live_sessions.
  Extracts session data from the conn so LiveView hooks can read it.
  """

  import Plug.Conn

  @doc """
  Session callback for the :user live_session (dashboard + settings).
  Passes user_id, admin_authenticated, and request_path.
  """
  def user_session_opts(conn) do
    %{
      "user_id" => get_session(conn, "user_id"),
      "admin_authenticated" => get_session(conn, "admin_authenticated"),
      "request_path" => conn.request_path
    }
  end

  @doc """
  Session callback for the :admin live_session.
  Passes user_id and admin_authenticated.
  """
  def admin_session_opts(conn) do
    %{
      "user_id" => get_session(conn, "user_id"),
      "admin_authenticated" => get_session(conn, "admin_authenticated")
    }
  end
end
