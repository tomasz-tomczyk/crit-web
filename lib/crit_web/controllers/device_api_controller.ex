defmodule CritWeb.DeviceApiController do
  use CritWeb, :controller

  alias Crit.DeviceCodes

  plug :rate_limit_create when action in [:create]

  @doc """
  POST /api/device/code — creates a new device code.

  Returns device_code, verification_uri_complete (with embedded session code),
  interval, and expires_in. The CLI opens verification_uri_complete in the
  browser — no manual code entry required.

  Returns 404 if no OAuth provider is configured.
  """
  def create(conn, _params) do
    if oauth_configured?() do
      case DeviceCodes.create_device_code() do
        {:ok, %{device_code: device_code, session_code: session_code}} ->
          verification_uri_complete =
            CritWeb.Endpoint.url() <> "/auth/cli?" <> URI.encode_query(%{code: session_code})

          conn
          |> put_status(201)
          |> json(%{
            device_code: device_code,
            verification_uri_complete: verification_uri_complete,
            interval: DeviceCodes.poll_interval(),
            expires_in: DeviceCodes.expires_in()
          })

        {:error, _reason} ->
          conn
          |> put_status(500)
          |> json(%{error: "Failed to create device code."})
      end
    else
      conn
      |> put_status(404)
      |> json(%{error: "Login is not configured on this server."})
    end
  end

  @doc """
  POST /api/device/token — polls for the token.

  Follows RFC 8628 response conventions:
  - 400 with "authorization_pending" — user hasn't entered code yet
  - 400 with "slow_down" — client polling too fast
  - 400 with "expired_token" — device code expired
  - 200 with access_token — success
  """
  def token(conn, %{"device_code" => device_code}) do
    case DeviceCodes.poll_device_code(device_code) do
      {:ok, access_token, user_info} ->
        response =
          %{access_token: access_token, token_type: "bearer"}
          |> maybe_put(:user_id, user_info && user_info.id)
          |> maybe_put(:user_name, user_info && user_info.name)
          |> maybe_put(:user_email, user_info && user_info.email)

        conn
        |> put_status(200)
        |> json(response)

      {:error, :authorization_pending} ->
        conn |> put_status(400) |> json(%{error: "authorization_pending"})

      {:error, :slow_down} ->
        conn |> put_status(400) |> json(%{error: "slow_down"})

      {:error, :expired_token} ->
        conn |> put_status(400) |> json(%{error: "expired_token"})

      {:error, :not_found} ->
        conn |> put_status(400) |> json(%{error: "expired_token"})
    end
  end

  def token(conn, _params) do
    conn |> put_status(400) |> json(%{error: "device_code is required"})
  end

  defp oauth_configured?, do: Crit.Config.oauth_configured?()

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # Rate-limit device code creation: 10 per minute per IP.
  defp rate_limit_create(conn, _opts) do
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()

    case Crit.RateLimit.hit("device_code_create:#{ip}", :timer.minutes(1), 10) do
      {:allow, _} ->
        conn

      {:deny, retry_after} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(div(retry_after, 1000)))
        |> put_status(429)
        |> json(%{error: "Too many requests"})
        |> halt()
    end
  end
end
