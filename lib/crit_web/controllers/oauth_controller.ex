defmodule CritWeb.OAuthController do
  use CritWeb, :controller

  alias Crit.Accounts
  alias CritWeb.UserAuth

  @doc "Initiates OAuth: redirects to the configured provider's authorization URL."
  def request(conn, params) do
    config = build_config()

    case config[:strategy].authorize_url(config) do
      {:ok, %{url: url, session_params: session_params}} ->
        conn
        |> put_session(:oauth_session_params, session_params)
        |> put_session(:oauth_return_to, safe_return_to(params["return_to"]))
        |> redirect(external: url)

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Could not reach OAuth provider.")
        |> redirect(to: ~p"/")
    end
  end

  @doc "Handles the OAuth callback: exchanges code for token, finds/creates user, logs in."
  def callback(conn, params) do
    config = build_config()
    session_params = get_session(conn, :oauth_session_params) || %{}

    if oauth_session_expired?(config, session_params) do
      conn
      |> put_flash(:error, "OAuth session expired. Please try signing in again.")
      |> redirect(to: ~p"/")
    else
      complete_callback(conn, params, config, session_params)
    end
  end

  defp complete_callback(conn, params, config, session_params) do
    case config
         |> Keyword.put(:session_params, session_params)
         |> config[:strategy].callback(params) do
      {:ok, %{user: user_params}} ->
        provider = provider_name(config)

        case Accounts.find_or_create_from_oauth(provider, user_params) do
          {:ok, user} ->
            device_code_id = get_session(conn, :device_code_id)

            return_to = get_session(conn, :oauth_return_to) || ~p"/dashboard"

            conn =
              conn
              |> delete_session(:oauth_session_params)
              |> delete_session(:oauth_return_to)
              |> UserAuth.log_in_user(user, %{})

            if device_code_id do
              # Keep device_code_id in session; redirect to consent screen
              conn
              |> put_session(:device_code_id, device_code_id)
              |> redirect(to: ~p"/auth/cli/authorize")
            else
              redirect(conn, to: return_to)
            end

          {:error, _changeset} ->
            conn
            |> put_flash(:error, "Could not complete sign-in. Please try again.")
            |> redirect(to: ~p"/")
        end

      {:error, _reason} ->
        conn
        |> put_flash(:error, "OAuth callback failed. Please try again.")
        |> redirect(to: ~p"/")
    end
  end

  @doc "Logs out: drops the session and redirects to the homepage."
  def delete(conn, _params) do
    conn
    |> UserAuth.log_out_user()
    |> redirect(to: ~p"/")
  end

  # Only allow local paths to prevent open redirect attacks.
  defp safe_return_to("//" <> _), do: nil
  defp safe_return_to("/" <> _ = path), do: path
  defp safe_return_to(_), do: nil

  defp build_config do
    config = Application.get_env(:crit, :oauth_provider, [])
    redirect_uri = CritWeb.Endpoint.url() <> "/auth/login/callback"
    config ++ [redirect_uri: redirect_uri]
  end

  defp provider_name(config) do
    case config[:strategy] do
      Assent.Strategy.Github -> "github"
      _ -> "custom"
    end
  end

  # Assent's OAuth2 verify_state/3 raises KeyError when session_params lacks :state
  # (expired session, bookmarked callback URL, or cross-browser flow). Fail gracefully.
  defp oauth_session_expired?(config, session_params) do
    state_required? = Keyword.get(config, :state, true) != false
    state_required? and not has_oauth_state?(session_params)
  end

  defp has_oauth_state?(params) when is_map(params) do
    Map.has_key?(params, :state) or Map.has_key?(params, "state")
  end

  defp has_oauth_state?(_), do: false
end
