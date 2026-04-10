defmodule CritWeb.DeviceController do
  use CritWeb, :controller

  alias Crit.DeviceCodes

  plug :put_root_layout, false
  plug :put_layout, false

  @doc """
  GET /auth/cli?code=SESSION_CODE — validates session_code, stores device_code_id
  in session, and redirects to OAuth. No form, no manual code entry.
  """
  def index(conn, %{"code" => code}) when is_binary(code) and code != "" do
    case DeviceCodes.verify_session_code(code) do
      {:ok, device_code} ->
        conn
        |> put_session(:device_code_id, device_code.id)
        |> redirect(to: ~p"/auth/login")

      {:error, :not_found} ->
        conn
        |> put_status(400)
        |> render(:error, message: "This link is invalid or expired. Please run crit auth login again.")
    end
  end

  def index(conn, _params) do
    conn
    |> put_status(400)
    |> render(:error, message: "This link is invalid or expired. Please run crit auth login again.")
  end

  @doc "GET /auth/cli/authorize — shows consent screen with user identity."
  def authorize(conn, _params) do
    device_code_id = get_session(conn, :device_code_id)
    current_user = conn.assigns[:current_user]

    if device_code_id && current_user do
      render(conn, :authorize, current_user: current_user, host: conn.host)
    else
      redirect(conn, to: ~p"/auth/cli")
    end
  end

  @doc "POST /auth/cli/authorize — completes device authorization."
  def confirm_authorize(conn, _params) do
    device_code_id = get_session(conn, :device_code_id)
    current_user = conn.assigns[:current_user]

    if device_code_id && current_user do
      case DeviceCodes.authorize_device_code(device_code_id, current_user) do
        {:ok, _device_code} ->
          conn
          |> delete_session(:device_code_id)
          |> redirect(to: ~p"/auth/cli/success")

        {:error, _reason} ->
          conn
          |> delete_session(:device_code_id)
          |> put_flash(:error, "Device authorization failed. The code may have expired.")
          |> redirect(to: ~p"/auth/cli")
      end
    else
      redirect(conn, to: ~p"/auth/cli")
    end
  end

  @doc "POST /auth/cli/cancel — cancels device authorization and clears session."
  def cancel(conn, _params) do
    conn
    |> delete_session(:device_code_id)
    |> redirect(to: ~p"/auth/cli")
  end

  @doc "GET /auth/cli/success — renders success page after authorization."
  def success(conn, _params) do
    render(conn, :success)
  end
end
