defmodule CritWeb.NewsletterController do
  @moduledoc """
  Serves archived newsletter HTML for "view in browser" links on crit.md.

  Hosted-only — self-hosted instances 404 via `CritWeb.Plugs.HostedOnly`.
  """
  use CritWeb, :controller

  alias Crit.Newsletters

  plug :private_subscription_response when action not in [:index, :show, :image]

  defp private_subscription_response(conn, _) do
    conn
    |> put_resp_header("referrer-policy", "no-referrer")
    |> put_resp_header("cache-control", "no-store")
  end

  def index(conn, _params) do
    render_index(conn, Newsletters.change_subscription())
  end

  def subscribe(conn, params) do
    case Newsletters.request_subscription(Map.get(params, "newsletter", %{})) do
      {:ok, :check_inbox} ->
        render_index(
          conn,
          Newsletters.change_subscription(),
          "Check your inbox to confirm your subscription. If you're already subscribed, you're all set."
        )

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> render_index(changeset)

      {:error, :delivery_failed} ->
        conn
        |> put_status(:service_unavailable)
        |> render_index(
          Newsletters.change_subscription(),
          "We couldn't send the confirmation email. Please try again in a moment."
        )
    end
  end

  def confirm(conn, %{"token" => token}) do
    render_token_page(conn, token, :confirm, Newsletters.confirmation(token))
  end

  def confirm_subscription(conn, %{"token" => token}) do
    case Newsletters.confirm_subscription(token) do
      {:ok, _} ->
        render_index(
          conn,
          Newsletters.change_subscription(),
          "You're subscribed. The next Crit update will arrive in your inbox."
        )

      {:error, _} ->
        invalid_token(conn)
    end
  end

  def unsubscribe(conn, %{"token" => token}) do
    render_token_page(conn, token, :unsubscribe, Newsletters.subscription_for_unsubscribe(token))
  end

  def unsubscribe_subscription(conn, %{"token" => token}) do
    case Newsletters.unsubscribe(token) do
      {:ok, _} ->
        render_index(
          conn,
          Newsletters.change_subscription(),
          "You're unsubscribed from Crit updates."
        )

      {:error, _} ->
        invalid_token(conn)
    end
  end

  defp render_index(conn, changeset, message \\ nil) do
    render(conn, :index,
      newsletters: Newsletters.list(),
      newsletter_form: Phoenix.Component.to_form(changeset, as: :newsletter),
      message: message,
      page_title: "Newsletter · Crit",
      canonical_url: CritWeb.Endpoint.url() <> "/newsletter",
      meta_description:
        "Occasional updates from Crit. Read previous newsletters or subscribe by email."
    )
  end

  defp render_token_page(conn, token, action, {:ok, _}) do
    render(conn, :subscription, token: token, action: action, page_title: "Newsletter · Crit")
  end

  defp render_token_page(conn, _, _, {:error, _}), do: invalid_token(conn)

  defp invalid_token(conn) do
    conn
    |> put_status(:unprocessable_entity)
    |> render_index(
      Newsletters.change_subscription(),
      "This link has expired or has already been used. You can subscribe again below."
    )
  end

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
