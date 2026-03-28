defmodule Crit.ReviewCleaner do
  @moduledoc """
  Periodically deletes reviews that have been inactive for more than 30 days.

  Runs once per day by default. The interval can be overridden via
  `config :crit, :review_cleaner_interval_ms, value` — useful in tests.
  """

  use GenServer

  require Logger

  @inactivity_days 30

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
    if Application.get_env(:crit, :selfhosted) do
      Logger.debug("[ReviewCleaner] Skipping cleanup in self-hosted mode")
    else
      case Crit.Reviews.delete_inactive(@inactivity_days) do
        {:ok, 0} ->
          Logger.debug("[ReviewCleaner] No inactive reviews to delete")

        {:ok, count} ->
          Logger.info("[ReviewCleaner] Deleted #{count} inactive review(s)")
      end
    end

    schedule_next_run()
    {:noreply, state}
  end

  defp schedule_next_run do
    interval = Application.get_env(:crit, :review_cleaner_interval_ms, :timer.hours(24))
    Process.send_after(self(), :run, interval)
  end
end
