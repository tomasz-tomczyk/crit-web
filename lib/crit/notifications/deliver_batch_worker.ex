defmodule Crit.Notifications.DeliverBatchWorker do
  use Oban.Worker,
    queue: :notifications,
    max_attempts: 3,
    unique: [
      period: :infinity,
      fields: [:worker, :queue, :args],
      keys: [:batch_id],
      states: :incomplete
    ]

  require Logger

  alias Crit.Accounts.Scope
  alias Crit.Notifications

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"batch_id" => id}} = job) do
    case Notifications.get_batch(id) do
      nil ->
        :ok

      %{status: status} when status in [:pending, :delivering] ->
        deliver(job, id)

      _terminal ->
        :ok
    end
  end

  defp deliver(job, id) do
    Notifications.mark_delivering(id)
    do_deliver(job, id)
  end

  defp do_deliver(job, id) do
    batch = Notifications.load_batch(id)

    cond do
      is_nil(batch) ->
        :ok

      not delivery_enabled?(batch) ->
        Notifications.finish(id, :cancelled)
        :ok

      batch.items == [] ->
        Notifications.finish(id, :cancelled)
        :ok

      true ->
        email = Crit.Notifications.Notifier.email(batch, batch.items)

        case Crit.Mailer.deliver(email) do
          {:ok, _metadata} ->
            Notifications.finish(id, :sent)
            :ok

          {:error, reason} ->
            fail(job, batch, reason)
        end
    end
  rescue
    error -> fail(job, Notifications.get_batch(id), error)
  end

  defp delivery_enabled?(batch) do
    setting = Crit.Settings.get()
    preference = batch.recipient.preferences.discussion_notifications_enabled
    access = Crit.Reviews.check_org_access(batch.review, Scope.for_user(batch.recipient))

    setting.notifications_enabled and preference and access == :ok and
      is_binary(batch.recipient.email) and batch.recipient.email != ""
  end

  defp fail(_job, nil, reason), do: {:error, reason}

  defp fail(job, batch, reason) do
    final? = job.attempt >= job.max_attempts

    if final? do
      Notifications.finish(batch.id, :failed)
    end

    Logger.warning("notification delivery failed",
      batch_id: batch.id,
      review_id: batch.review_id,
      recipient_user_id: batch.recipient_user_id,
      attempt: job.attempt,
      failure_class: failure_class(reason)
    )

    {:error, reason}
  end

  defp failure_class(%{__struct__: module}), do: inspect(module)
  defp failure_class(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp failure_class(_reason), do: "delivery_error"
end
