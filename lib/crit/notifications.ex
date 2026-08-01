defmodule Crit.Notifications do
  @moduledoc "Records discussion activity and owns notification batch lifecycle."

  import Ecto.Query

  alias Crit.Accounts.Scope
  alias Crit.Notifications.{DeliverBatchWorker, NotificationBatch, NotificationItem}
  alias Crit.{Comment, Repo, Review, Settings, User}

  @pending_conflict {:unsafe_fragment, "(recipient_user_id, review_id) WHERE status = 'pending'"}

  @doc "Records eligible notification items inside the caller's transaction."
  def record_activity(%Scope{} = scope, %Review{} = review, %Comment{} = comment) do
    setting = Settings.get()

    if setting.notifications_enabled do
      recipients(scope, review, comment)
      |> Enum.reduce_while({:ok, []}, fn recipient, {:ok, batches} ->
        case queue_item(recipient, review, comment, setting) do
          {:ok, batch} -> {:cont, {:ok, [batch | batches]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    else
      {:ok, []}
    end
  end

  @doc "Returns eligible users for one newly-created comment or reply."
  def recipients(%Scope{} = scope, %Review{} = review, %Comment{} = comment) do
    actor_id = Scope.user_id(scope)

    user_ids =
      if comment.parent_id do
        participant_ids =
          Repo.all(
            from c in Comment,
              where: c.id == ^comment.parent_id or c.parent_id == ^comment.parent_id,
              where: not is_nil(c.user_id),
              select: c.user_id
          )

        [review.user_id | participant_ids]
      else
        [review.user_id]
      end

    query =
      from u in User,
        where: u.id in ^user_ids and not is_nil(u.email) and u.email != "",
        where:
          fragment(
            "COALESCE((?->>'discussion_notifications_enabled')::boolean, true)",
            u.preferences
          )

    query =
      if actor_id do
        from u in query, where: u.id != ^actor_id
      else
        query
      end

    Repo.all(from u in query, distinct: u.id)
  end

  defp queue_item(recipient, review, comment, setting, retries \\ 1) do
    now = DateTime.utc_now()
    quiet_after = DateTime.add(now, setting.notification_batch_minutes * 60, :second)

    attrs = %{
      recipient_user_id: recipient.id,
      review_id: review.id,
      status: :pending,
      first_event_at: now,
      deliver_after: quiet_after
    }

    {:ok, batch} = get_or_insert_pending(attrs)

    max_after =
      DateTime.add(batch.first_event_at, setting.notification_max_wait_minutes * 60, :second)

    deliver_after =
      if DateTime.after?(quiet_after, max_after), do: max_after, else: quiet_after

    {count, _} =
      Repo.update_all(
        from(b in NotificationBatch, where: b.id == ^batch.id and b.status == :pending),
        set: [deliver_after: deliver_after, updated_at: now]
      )

    cond do
      count == 1 ->
        %NotificationItem{}
        |> NotificationItem.changeset(%{batch_id: batch.id, comment_id: comment.id})
        |> Repo.insert(on_conflict: :nothing, conflict_target: [:batch_id, :comment_id])
        |> case do
          {:ok, _item} -> enqueue_delivery(%{batch | deliver_after: deliver_after}, deliver_after)
          {:error, changeset} -> {:error, changeset}
        end

      retries > 0 ->
        # Batch was claimed for delivery; the pending unique index now allows a
        # fresh digest for this activity.
        queue_item(recipient, review, comment, setting, retries - 1)

      true ->
        {:error, :batch_race}
    end
  end

  defp get_or_insert_pending(attrs) do
    now = DateTime.utc_now()
    attrs = Map.merge(attrs, %{id: Ecto.UUID.generate(), inserted_at: now, updated_at: now})

    case Repo.insert_all(NotificationBatch, [attrs],
           on_conflict: :nothing,
           conflict_target: @pending_conflict,
           returning: true
         ) do
      {1, [batch]} ->
        {:ok, batch}

      {0, []} ->
        {:ok,
         Repo.one!(
           from b in NotificationBatch,
             where:
               b.recipient_user_id == ^attrs.recipient_user_id and
                 b.review_id == ^attrs.review_id and b.status == :pending,
             lock: "FOR UPDATE"
         )}
    end
  end

  def enqueue_delivery(batch, scheduled_at) do
    %{batch_id: batch.id}
    |> DeliverBatchWorker.new(
      scheduled_at: scheduled_at,
      # Only bump scheduled jobs. Available/executing jobs are handled by the
      # worker's deliver_after snooze check.
      replace: [scheduled: [:scheduled_at]]
    )
    |> Oban.insert()
    |> case do
      {:ok, _job} ->
        {:ok, batch}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def get_batch(id), do: Repo.get(NotificationBatch, id)

  def load_batch(id) do
    items_query = from i in NotificationItem, order_by: [asc: i.inserted_at]

    NotificationBatch
    |> Repo.get(id)
    |> Repo.preload([
      :recipient,
      :review,
      items: {items_query, [comment: [:user, parent: :user]]}
    ])
  end

  @doc """
  Atomically claims a batch for delivery.

  Returns `{:ok, batch}` when this caller won the claim, or `:already_claimed`
  when another worker owns it.

  First attempts claim only from `pending`/`retryable`. On Oban retries
  (`attempt > 1`), also reclaim `:delivering` so a crash after claim can
  resume without a separate recovery worker.
  """
  def claim_for_delivery(id, attempt \\ 1) do
    now = DateTime.utc_now()

    statuses =
      if attempt > 1 do
        [:pending, :retryable, :delivering]
      else
        [:pending, :retryable]
      end

    case Repo.update_all(
           from(b in NotificationBatch, where: b.id == ^id and b.status in ^statuses),
           set: [status: :delivering, finished_at: nil, updated_at: now]
         ) do
      {1, _} -> {:ok, get_batch(id)}
      {0, _} -> :already_claimed
    end
  end

  def finish(id, status) when status in [:sent, :cancelled, :failed] do
    case Repo.get(NotificationBatch, id) do
      %NotificationBatch{status: :delivering} = batch ->
        batch
        |> NotificationBatch.changeset(%{status: status, finished_at: DateTime.utc_now()})
        |> Repo.update()

      _missing_or_finished ->
        {:ok, nil}
    end
  end

  @doc "Returns a soft-failed batch to `:retryable` so Oban can retry it."
  def mark_retryable(id) do
    now = DateTime.utc_now()

    Repo.update_all(
      from(b in NotificationBatch, where: b.id == ^id and b.status == :delivering),
      set: [status: :retryable, finished_at: nil, updated_at: now]
    )
  end

  def cleanup_terminal(retention_days) do
    cutoff = DateTime.add(DateTime.utc_now(), -retention_days, :day)

    ids =
      Repo.all(
        from b in NotificationBatch,
          where: b.status in [:sent, :cancelled, :failed] and b.finished_at < ^cutoff,
          order_by: [asc: b.finished_at],
          limit: 1000,
          select: b.id
      )

    {count, _} = Repo.delete_all(from b in NotificationBatch, where: b.id in ^ids)
    if count == 1000, do: cleanup_terminal(retention_days), else: count
  end
end
