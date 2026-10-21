defmodule Crit.Turnstile do
  @moduledoc """
  Cloudflare Turnstile verification for public forms (the newsletter signup).

  Enabled when both `TURNSTILE_SITE_KEY` and `TURNSTILE_SECRET_KEY` are set.
  Without them (dev, test, self-hosted) `verify/1` always passes.
  """

  require Logger

  @verify_url "https://challenges.cloudflare.com/turnstile/v0/siteverify"

  @doc "The public site key, or nil when Turnstile is off."
  def site_key do
    if enabled?(), do: config()[:site_key]
  end

  def enabled? do
    present?(config()[:site_key]) and present?(config()[:secret_key])
  end

  @doc "Checks a `cf-turnstile-response` token with Cloudflare."
  def verify(token) do
    cond do
      not enabled?() ->
        :ok

      not is_binary(token) or token == "" ->
        {:error, :missing_token}

      true ->
        siteverify(token)
    end
  end

  defp siteverify(token) do
    options =
      [
        url: @verify_url,
        form: [secret: config()[:secret_key], response: token],
        retry: false
      ] ++ Keyword.get(config(), :req_options, [])

    case Req.post(options) do
      {:ok, %Req.Response{status: 200, body: %{"success" => true}}} ->
        :ok

      {:ok, %Req.Response{status: 200, body: %{"error-codes" => codes}}} ->
        {:error, {:rejected, codes}}

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("Turnstile siteverify returned HTTP #{status}")
        {:error, :unavailable}

      {:error, reason} ->
        Logger.warning("Turnstile siteverify failed: #{inspect(reason)}")
        {:error, :unavailable}
    end
  end

  defp config, do: Application.get_env(:crit, __MODULE__, [])

  defp present?(value), do: is_binary(value) and value != ""
end
