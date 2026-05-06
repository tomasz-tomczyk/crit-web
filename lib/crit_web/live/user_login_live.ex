defmodule CritWeb.UserLoginLive do
  use CritWeb, :live_view

  def mount(_params, _session, socket) do
    form = to_form(%{}, as: "user")
    {:ok, assign(socket, form: form, oauth_provider_label: oauth_label())}
  end

  defp oauth_label do
    case Application.get_env(:crit, :oauth_provider) do
      nil ->
        nil

      opts when is_list(opts) ->
        case Keyword.get(opts, :strategy) do
          Assent.Strategy.Github -> "Continue with GitHub"
          nil -> nil
          _other -> "Continue with SSO"
        end
    end
  end
end
