defmodule Crit.Reviews.InactiveCleanupWorker do
  @moduledoc """
  Deletes reviews that have been inactive for more than 30 days.

  Scheduled daily by `Oban.Plugins.Cron` (see `config/config.exs`). The cron
  plugin only enqueues on the leader node, so one node runs each cleanup.
  Skipped in self-hosted mode.
  """

  use Oban.Worker, queue: :maintenance, max_attempts: 3

  require Logger

  @inactivity_days 30

  @impl Oban.Worker
  def perform(_job) do
    if Application.get_env(:crit, :selfhosted) do
      Logger.debug("[InactiveCleanupWorker] Skipping cleanup in self-hosted mode")
    else
      case Crit.Reviews.delete_inactive(@inactivity_days) do
        {:ok, 0} ->
          Logger.debug("[InactiveCleanupWorker] No inactive reviews to delete")

        {:ok, count} ->
          Logger.info("[InactiveCleanupWorker] Deleted #{count} inactive review(s)")
      end
    end

    :ok
  end
end
