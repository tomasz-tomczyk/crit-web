defmodule Crit.Notifications.NotificationBatch do
  use Crit.Schema

  @statuses [:pending, :delivering, :retryable, :sent, :cancelled, :failed]

  schema "notification_batches" do
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :first_event_at, :utc_datetime_usec
    field :deliver_after, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec

    belongs_to :recipient, Crit.User, foreign_key: :recipient_user_id
    belongs_to :review, Crit.Review
    has_many :items, Crit.Notifications.NotificationItem, foreign_key: :batch_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(batch, attrs) do
    batch
    |> cast(attrs, [
      :recipient_user_id,
      :review_id,
      :status,
      :first_event_at,
      :deliver_after,
      :finished_at
    ])
    |> validate_required([
      :recipient_user_id,
      :review_id,
      :status,
      :first_event_at,
      :deliver_after
    ])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:recipient_user_id)
    |> foreign_key_constraint(:review_id)
  end
end
