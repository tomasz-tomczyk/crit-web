defmodule Crit.DeviceCodeCleaner do
  @moduledoc """
  Periodically deletes expired, redeemed, or stale authorized device codes.

  Runs once per day by default. The interval can be overridden via
  `config :crit, :device_code_cleaner_interval_ms, value` — useful in tests.
  """

  use GenServer

  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_next_run()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:run, state) do
    case Crit.DeviceCodes.cleanup_expired() do
      {:ok, 0} ->
        Logger.debug("[DeviceCodeCleaner] No device codes to clean up")

      {:ok, count} ->
        Logger.info("[DeviceCodeCleaner] Deleted #{count} device code(s)")
    end

    schedule_next_run()
    {:noreply, state}
  end

  defp schedule_next_run do
    interval = Application.get_env(:crit, :device_code_cleaner_interval_ms, :timer.hours(24))
    Process.send_after(self(), :run, interval)
  end
end
