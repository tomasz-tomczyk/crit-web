defmodule CritWeb.ShareReceiverController do
  @moduledoc """
  Renders the same-origin popup relay page used by crit's local CLI to perform
  share / fetch / upsert / unpublish against crit-web from behind an SSO
  reverse proxy. The page runs a tiny bundled JS handler and exchanges a
  MessagePort with the localhost opener; no server-side state lives here.
  """
  use CritWeb, :controller

  def index(conn, _params) do
    conn
    |> put_root_layout(false)
    |> put_layout(false)
    |> render(:index)
  end
end
