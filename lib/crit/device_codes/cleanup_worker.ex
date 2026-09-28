defmodule Crit.DeviceCodes.CleanupWorker do
  @moduledoc """
  Deletes expired, redeemed, or stale authorized device codes.

  Scheduled daily by `Oban.Plugins.Cron` (see `config/config.exs`). The cron
  plugin only enqueues on the leader node, so one node runs each cleanup.
  Runs in self-hosted mode too: device codes must expire everywhere.
  """

  use Oban.Worker, queue: :maintenance, max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    case Crit.DeviceCodes.cleanup_expired() do
      {:ok, 0} ->
        Logger.debug("[DeviceCodes.CleanupWorker] No device codes to clean up")

      {:ok, count} ->
        Logger.info("[DeviceCodes.CleanupWorker] Deleted #{count} device code(s)")
    end

    :ok
  end
end
