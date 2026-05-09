defmodule CritWeb.UserLoginLive do
  use CritWeb, :live_view

  def mount(params, _session, socket) do
    form = to_form(%{}, as: "user")

    {:ok,
     socket
     |> assign(:form, form)
     |> assign(:oauth_provider_label, oauth_label())
     |> assign(:return_to, sanitize_return_to(params["return_to"]))
     |> assign(:selfhosted, Application.get_env(:crit, :selfhosted) == true)}
  end

  # Only allow same-origin path redirects to prevent open-redirect via return_to.
  defp sanitize_return_to(nil), do: nil
  defp sanitize_return_to("/" <> _ = path), do: path
  defp sanitize_return_to(_), do: nil

  def oauth_login_path(nil), do: "/auth/login"
  def oauth_login_path(return_to), do: "/auth/login?return_to=#{URI.encode_www_form(return_to)}"

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
