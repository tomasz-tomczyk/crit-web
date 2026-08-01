defmodule Crit.Notifications.CleanupWorker do
  use Oban.Worker, queue: :notifications, max_attempts: 3

  @impl Oban.Worker
  def perform(_job) do
    case Crit.Settings.get().notification_retention_days do
      0 -> :ok
      days -> Crit.Notifications.cleanup_terminal(days)
    end

    :ok
  end
end
