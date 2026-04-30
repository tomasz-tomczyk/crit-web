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
  `/r/:token` review LiveView (`CritWeb.Live.Hooks.:require_review_auth`).
  """
  @spec selfhosted_oauth?() :: boolean()
  def selfhosted_oauth? do
    Application.get_env(:crit, :selfhosted) == true &&
      Application.get_env(:crit, :oauth_provider) != nil
  end
end
