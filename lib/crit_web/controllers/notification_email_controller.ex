defmodule CritWeb.NotificationEmailController do
  @moduledoc """
  Public pages for an extra discussion-notification address.

  GET only shows a button. Mail scanners that fetch the link must not confirm
  or remove the address.
  """

  use CritWeb, :controller

  alias Crit.Notifications.ExtraAddresses

  plug :private_response

  defp private_response(conn, _opts) do
    conn
    |> put_resp_header("referrer-policy", "no-referrer")
    |> put_resp_header("cache-control", "no-store")
  end

  def confirm(conn, %{"token" => token}) do
    case ExtraAddresses.preview(token) do
      {:ok, state, email} -> render_page(conn, state, token, email)
      :error -> render_page(conn, :invalid, nil, nil, 422)
    end
  end

  def confirm_address(conn, %{"token" => token}) do
    case ExtraAddresses.confirm(token) do
      {:ok, email} -> render_page(conn, :done, token, email)
      :error -> render_page(conn, :invalid, nil, nil, 422)
    end
  end

  def unsubscribe(conn, %{"token" => token}) do
    case ExtraAddresses.unsubscribe_preview(token) do
      {:ok, state, email} -> render_unsubscribe(conn, state, token, email)
      :error -> render_unsubscribe(conn, :invalid, nil, nil, 422)
    end
  end

  def unsubscribe_address(conn, %{"token" => token}) do
    case ExtraAddresses.unsubscribe(token) do
      {:ok, email} -> render_unsubscribe(conn, :done, token, email)
      :error -> render_unsubscribe(conn, :invalid, nil, nil, 422)
    end
  end

  defp render_page(conn, state, token, email, status \\ 200) do
    conn
    |> put_status(status)
    |> render(:confirm,
      state: state,
      token: token,
      email: email,
      page_title: "Confirm notification address · Crit",
      noindex: true,
      meta_description: "Confirm an extra address for Crit discussion notifications."
    )
  end

  defp render_unsubscribe(conn, state, token, email, status \\ 200) do
    conn
    |> put_status(status)
    |> render(:unsubscribe,
      state: state,
      token: token,
      email: email,
      page_title: "Unsubscribe · Crit",
      noindex: true,
      meta_description: "Stop discussion notifications to an extra address."
    )
  end
end
