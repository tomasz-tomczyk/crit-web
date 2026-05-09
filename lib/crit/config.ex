defmodule Crit.Config do
  @moduledoc """
  Centralized accessors for runtime configuration that gates behavior across
  multiple call sites. Keeping these in one place avoids subtle drift between
  the API auth plug and the review LiveView's auth gate.
  """

  @doc """
  Returns true when this instance is running in selfhosted mode AND has an
  OAuth provider configured. This is the predicate that turns on auth
  enforcement for both the JSON API (`CritWeb.Plugs.ApiAuth`) and the
  `/r/:token` review LiveView (`CritWeb.UserAuth.:require_review_scope`).
  """
  @spec selfhosted_oauth?() :: boolean()
  def selfhosted_oauth? do
    Application.get_env(:crit, :selfhosted) == true &&
      Application.get_env(:crit, :oauth_provider) != nil
  end

  @doc """
  Returns true when an OAuth provider is configured, regardless of selfhosted
  mode. Use this for sites that gate purely on OAuth presence (device flow,
  public-mode auth-required redirects). Distinct from `selfhosted_oauth?/0`,
  which also requires `:selfhosted == true`.
  """
  @spec oauth_configured?() :: boolean()
  def oauth_configured? do
    Application.get_env(:crit, :oauth_provider) != nil
  end

  @doc """
  Returns true when any auth backend is wired up: an OAuth provider OR an
  admin password. When neither is set the deployment cannot authenticate
  anyone, so authenticated-only routes (`/dashboard`, `/settings`) render
  anonymously instead of redirecting — see issue #50 for the proxy-loop this
  prevents.
  """
  @spec auth_configured?() :: boolean()
  def auth_configured? do
    oauth_configured?() || Application.get_env(:crit, :admin_password) != nil
  end
end
