defmodule Crit.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        CritWeb.Telemetry,
        Crit.Repo,
        {DNSCluster, query: Application.get_env(:crit, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Crit.PubSub},
        {Crit.RateLimit, clean_period: :timer.minutes(10)}
      ] ++
        review_cleaner() ++
        device_code_cleaner() ++
        changelog() ++
        [
          CritWeb.Endpoint
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Crit.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp review_cleaner do
    if Application.get_env(:crit, :start_review_cleaner, true) do
      [Crit.ReviewCleaner]
    else
      []
    end
  end

  defp device_code_cleaner do
    if Application.get_env(:crit, :start_device_code_cleaner, true) do
      [Crit.DeviceCodeCleaner]
    else
      []
    end
  end

  defp changelog do
    if Application.get_env(:crit, :start_changelog, true) do
      [Crit.Changelog]
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CritWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
