defmodule Crit.Notifications.NotificationItem do
  use Crit.Schema

  schema "notification_items" do
    belongs_to :batch, Crit.Notifications.NotificationBatch
    belongs_to :comment, Crit.Comment
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:batch_id, :comment_id, :inserted_at])
    |> validate_required([:batch_id, :comment_id])
    |> foreign_key_constraint(:batch_id)
    |> foreign_key_constraint(:comment_id)
    |> unique_constraint([:batch_id, :comment_id])
  end
end
