defmodule CritWeb.NotificationEmailController do
  @moduledoc """
  Public confirmation page for an extra discussion-notification address.

  GET only shows a button. Mail scanners that fetch the link must not confirm it.
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
    case ExtraAddresses.unsubscribe(token) do
      {:ok, email} -> render_unsubscribe(conn, :done, email)
      :error -> render_unsubscribe(conn, :invalid, nil, 422)
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

  defp render_unsubscribe(conn, state, email, status \\ 200) do
    conn
    |> put_status(status)
    |> render(:unsubscribe,
      state: state,
      email: email,
      page_title: "Unsubscribe · Crit",
      noindex: true,
      meta_description: "Stop discussion notifications to an extra address."
    )
  end
end
