defmodule CritWeb.NewsletterController do
  @moduledoc """
  Serves archived newsletter HTML for "view in browser" links on crit.md.

  Hosted-only — self-hosted instances 404 via `CritWeb.Plugs.HostedOnly`.
  """
  use CritWeb, :controller

  alias Crit.Newsletters

  def show(conn, %{"slug" => slug}) do
    case Newsletters.get(slug) do
      nil ->
        conn
        |> put_status(:not_found)
        |> put_view(CritWeb.ErrorHTML)
        |> put_root_layout(false)
        |> put_layout(false)
        |> render(:"404")

      newsletter ->
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(200, Newsletters.browser_html(newsletter))
    end
  end

  def image(conn, %{"slug" => slug, "name" => name}) do
    case Newsletters.image_path(slug, name) do
      nil ->
        send_resp(conn, 404, "Not found")

      path ->
        conn
        |> put_resp_content_type(MIME.from_path(path))
        |> put_resp_header("cache-control", "public, max-age=86400")
        |> send_file(200, path)
    end
  end
end
