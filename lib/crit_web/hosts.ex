defmodule CritWeb.Hosts do
  @moduledoc """
  Host/origin helpers for app-vs-preview isolation.
  """

  @doc """
  Canonical app host (`PHX_HOST`), if configured.
  """
  @spec canonical_host() :: String.t() | nil
  def canonical_host do
    Application.get_env(:crit, :canonical_host)
  end

  @doc """
  Optional dedicated preview host (`PREVIEW_HOST`).
  """
  @spec preview_host() :: String.t() | nil
  def preview_host do
    case Application.get_env(:crit, :preview_host) do
      host when is_binary(host) and host != "" -> host
      _ -> nil
    end
  end

  @doc """
  True when a separate preview host is configured.
  """
  @spec preview_host_enabled?() :: boolean()
  def preview_host_enabled? do
    is_binary(preview_host())
  end

  @doc """
  Canonical app origin.
  """
  @spec canonical_origin() :: String.t()
  def canonical_origin do
    endpoint_origin_for(canonical_host())
  end

  @doc """
  Preview origin. Falls back to endpoint origin when PREVIEW_HOST is unset.
  """
  @spec preview_origin() :: String.t()
  def preview_origin do
    endpoint_origin_for(preview_host())
  end

  defp endpoint_origin_for(nil), do: CritWeb.Endpoint.url()

  defp endpoint_origin_for(host) do
    endpoint = URI.parse(CritWeb.Endpoint.url())
    endpoint |> Map.put(:host, host) |> URI.to_string()
  end
end
