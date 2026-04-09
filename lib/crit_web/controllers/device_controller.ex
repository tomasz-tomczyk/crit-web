defmodule CritWeb.DeviceController do
  use CritWeb, :controller

  alias Crit.DeviceCodes

  plug :put_root_layout, false
  plug :put_layout, false
  plug :rate_limit_form when action in [:submit]

  @doc "GET /device — renders the code entry form."
  def index(conn, params) do
    render(conn, :index, error: nil, code: params["code"])
  end

  @doc "POST /device — validates user_code, stores device_code row ID in session, redirects to OAuth."
  def submit(conn, %{"user_code" => user_code}) do
    case DeviceCodes.verify_user_code(user_code) do
      {:ok, device_code} ->
        conn
        |> put_session(:device_code_id, device_code.id)
        |> redirect(to: ~p"/auth/login")

      {:error, :not_found} ->
        render(conn, :index,
          error: "Invalid or expired code. Please try again.",
          code: user_code
        )
    end
  end

  def submit(conn, _params) do
    render(conn, :index, error: "Please enter a code.", code: nil)
  end

  @doc "GET /device/authorize — shows consent screen with user identity."
  def authorize(conn, _params) do
    device_code_id = get_session(conn, :device_code_id)
    current_user = conn.assigns[:current_user]

    if device_code_id && current_user do
      render(conn, :authorize, current_user: current_user, host: conn.host)
    else
      redirect(conn, to: ~p"/device")
    end
  end

  @doc "POST /device/authorize — completes device authorization."
  def confirm_authorize(conn, _params) do
    device_code_id = get_session(conn, :device_code_id)
    current_user = conn.assigns[:current_user]

    if device_code_id && current_user do
      case DeviceCodes.authorize_device_code(device_code_id, current_user) do
        {:ok, _device_code} ->
          conn
          |> delete_session(:device_code_id)
          |> redirect(to: ~p"/device/success")

        {:error, _reason} ->
          conn
          |> delete_session(:device_code_id)
          |> put_flash(:error, "Device authorization failed. The code may have expired.")
          |> redirect(to: ~p"/device")
      end
    else
      redirect(conn, to: ~p"/device")
    end
  end

  @doc "POST /device/cancel — cancels device authorization and clears session."
  def cancel(conn, _params) do
    conn
    |> delete_session(:device_code_id)
    |> redirect(to: ~p"/device")
  end

  @doc "GET /device/success — renders success page after authorization."
  def success(conn, _params) do
    render(conn, :success)
  end

  # Rate-limit form submissions: 5 per 5 minutes per IP.
  defp rate_limit_form(conn, _opts) do
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()

    case Crit.RateLimit.hit("device_form:#{ip}", :timer.minutes(5), 5) do
      {:allow, _} ->
        conn

      {:deny, _} ->
        conn
        |> put_status(429)
        |> render(:index,
          error: "Too many attempts. Please wait a few minutes.",
          code: nil
        )
        |> halt()
    end
  end
end
