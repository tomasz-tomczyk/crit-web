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
  Returns true on the public crit.md deployment. Self-hosted instances opt out
  of hosted-only integrations such as Umami analytics.
  """
  @spec hosted?() :: boolean()
  def hosted? do
    Application.get_env(:crit, :selfhosted) != true
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
  Returns true when any auth backend is wired up: OAuth provider, admin
  password, or trusted-proxy user header. With three available backends a
  real selfhost deploy will configure at least one; this predicate exists for
  the rare case where none are set.
  """
  @spec auth_configured?() :: boolean()
  def auth_configured? do
    oauth_configured?() ||
      Application.get_env(:crit, :admin_password) != nil ||
      trusted_proxy_header_configured?()
  end

  defp trusted_proxy_header_configured? do
    case Application.get_env(:crit, :trusted_proxy_user_header) do
      nil -> false
      "" -> false
      _ -> true
    end
  end

  # ---------------------------------------------------------------------------
  # Trusted proxy header authentication
  #
  # When crit-web runs behind an enterprise SSO reverse proxy (oauth2-proxy,
  # Cloudflare Access, IAP, Pomerium, Authelia, ...), the proxy authenticates
  # the user and injects their email into a request header. crit-web trusts
  # that header **only** when:
  #
  #   1. The operator opted in via `CRIT_TRUSTED_PROXY_USER_HEADER`, AND
  #   2. The request comes from a `CRIT_TRUSTED_PROXY_CIDRS` source IP.
  #
  # Setting the header without CIDRs is a footgun (anyone reaching the app
  # directly could spoof the header), so `validate_trusted_proxy!/0` raises
  # at boot if that combination is configured.
  # ---------------------------------------------------------------------------

  @doc """
  Validates the trusted-proxy configuration. Called from `runtime.exs` at boot.

  Raises if `:trusted_proxy_user_header` is set but `:trusted_proxy_cidrs` is
  empty or missing — that combination would let any direct request spoof the
  header. Returns `:ok` otherwise.
  """
  @spec validate_trusted_proxy!() :: :ok
  def validate_trusted_proxy! do
    header = Application.get_env(:crit, :trusted_proxy_user_header)
    cidrs = Application.get_env(:crit, :trusted_proxy_cidrs)

    cond do
      is_nil(header) or header == "" ->
        :ok

      is_list(cidrs) and cidrs != [] ->
        :ok

      true ->
        raise """
        CRIT_TRUSTED_PROXY_USER_HEADER is set but CRIT_TRUSTED_PROXY_CIDRS is empty.

        Trusting a request header without restricting which source IPs can set
        it would let anyone reaching the app directly spoof the authenticated
        user. Set CRIT_TRUSTED_PROXY_CIDRS to a comma-separated list of CIDRs
        covering your reverse proxy, e.g.:

            CRIT_TRUSTED_PROXY_CIDRS=10.0.0.0/8,172.16.0.0/12

        Or unset CRIT_TRUSTED_PROXY_USER_HEADER to disable trusted-proxy auth.
        """
    end
  end

  @doc """
  Parses a comma-separated CIDR list string into a list of
  `{ip_tuple, prefix_len}` pairs suitable for `ip_in_cidrs?/2`.

  Accepts both IPv4 and IPv6. Raises on malformed input.
  """
  @spec parse_cidrs(String.t() | nil) :: [{:inet.ip_address(), non_neg_integer()}]
  def parse_cidrs(nil), do: []
  def parse_cidrs(""), do: []

  def parse_cidrs(str) when is_binary(str) do
    str
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&parse_cidr!/1)
  end

  defp parse_cidr!(cidr) do
    case String.split(cidr, "/", parts: 2) do
      [ip_str, prefix_str] ->
        with {:ok, ip} <- parse_ip(ip_str),
             {prefix, ""} <- Integer.parse(prefix_str),
             true <- valid_prefix?(ip, prefix) do
          {ip, prefix}
        else
          _ -> raise "invalid CIDR: #{inspect(cidr)}"
        end

      _ ->
        raise "invalid CIDR: #{inspect(cidr)}"
    end
  end

  defp parse_ip(str) do
    case :inet.parse_address(String.to_charlist(str)) do
      {:ok, ip} -> {:ok, ip}
      {:error, _} -> :error
    end
  end

  defp valid_prefix?(ip, prefix) when is_integer(prefix) and prefix >= 0 do
    case tuple_size(ip) do
      4 -> prefix <= 32
      8 -> prefix <= 128
    end
  end

  defp valid_prefix?(_, _), do: false

  @doc """
  Returns true if `ip` falls within any of the parsed CIDRs.
  """
  @spec ip_in_cidrs?(:inet.ip_address(), [{:inet.ip_address(), non_neg_integer()}]) :: boolean()
  def ip_in_cidrs?(_ip, []), do: false

  def ip_in_cidrs?(ip, cidrs) when is_tuple(ip) and is_list(cidrs) do
    ip_int = ip_to_int(ip)
    bit_size = bit_size_for(ip)

    Enum.any?(cidrs, fn {net, prefix} ->
      tuple_size(net) == tuple_size(ip) and
        bit_size_for(net) == bit_size and
        prefix_match?(ip_int, ip_to_int(net), prefix, bit_size)
    end)
  end

  defp prefix_match?(_ip_int, _net_int, 0, _bit_size), do: true

  defp prefix_match?(ip_int, net_int, prefix, bit_size) do
    shift = bit_size - prefix
    Bitwise.bsr(ip_int, shift) == Bitwise.bsr(net_int, shift)
  end

  defp bit_size_for(t) when tuple_size(t) == 4, do: 32
  defp bit_size_for(t) when tuple_size(t) == 8, do: 128

  defp ip_to_int({a, b, c, d}) do
    Bitwise.bsl(a, 24) + Bitwise.bsl(b, 16) + Bitwise.bsl(c, 8) + d
  end

  defp ip_to_int({a, b, c, d, e, f, g, h}) do
    Bitwise.bsl(a, 112) + Bitwise.bsl(b, 96) + Bitwise.bsl(c, 80) + Bitwise.bsl(d, 64) +
      Bitwise.bsl(e, 48) + Bitwise.bsl(f, 32) + Bitwise.bsl(g, 16) + h
  end
end
