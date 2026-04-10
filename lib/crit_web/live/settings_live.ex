defmodule CritWeb.SettingsLive do
  use CritWeb, :live_view

  on_mount {CritWeb.Live.Hooks, :require_user}

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Settings - Crit")
      |> assign(:noindex, true)

    {:ok, socket, layout: false}
  end

  @doc false
  def session_opts(conn) do
    %{"user_id" => Plug.Conn.get_session(conn, "user_id")}
  end
end
