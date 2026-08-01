defmodule Crit.Repo.Migrations.AddNotificationSystem do
  use Ecto.Migration

  def up do
    Oban.Migration.up()

    alter table(:users) do
      add :preferences, :map, null: false, default: fragment("'{}'::jsonb")
    end

    execute("""
    UPDATE users
    SET preferences = jsonb_build_object(
      'keep_reviews', keep_reviews,
      'discussion_notifications_enabled', true
    )
    """)

    alter table(:users) do
      remove :keep_reviews
    end

    alter table(:settings) do
      add :notifications_enabled, :boolean, null: false, default: false
      add :notification_batch_minutes, :integer, null: false, default: 10
      add :notification_max_wait_minutes, :integer, null: false, default: 60
      add :notification_retention_days, :integer, null: false, default: 30
    end

    create constraint(:settings, :notification_batch_minutes_positive,
             check: "notification_batch_minutes > 0"
           )

    create constraint(:settings, :notification_max_wait_minutes_valid,
             check:
               "notification_max_wait_minutes > 0 AND notification_max_wait_minutes >= notification_batch_minutes"
           )

    create constraint(:settings, :notification_retention_days_non_negative,
             check: "notification_retention_days >= 0"
           )

    create table(:notification_batches, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :recipient_user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: false

      add :review_id, references(:reviews, type: :binary_id, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "pending"
      add :first_event_at, :utc_datetime_usec, null: false
      add :finished_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:notification_batches, [:recipient_user_id, :review_id],
             where: "status = 'pending'",
             name: :notification_batches_pending_recipient_review_idx
           )

    create index(:notification_batches, [:status, :finished_at])

    create constraint(:notification_batches, :notification_batches_status_check,
             check: "status IN ('pending', 'delivering', 'sent', 'cancelled', 'failed')"
           )

    create constraint(:notification_batches, :notification_batches_finished_check,
             check: "((status IN ('sent', 'cancelled', 'failed')) = (finished_at IS NOT NULL))"
           )

    create table(:notification_items, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :batch_id,
          references(:notification_batches, type: :binary_id, on_delete: :delete_all),
          null: false

      add :comment_id, references(:comments, type: :binary_id, on_delete: :delete_all),
        null: false

      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:notification_items, [:batch_id, :comment_id])
    create index(:notification_items, [:comment_id])
  end

  def down do
    drop table(:notification_items)
    drop table(:notification_batches)

    alter table(:settings) do
      remove :notification_retention_days
      remove :notification_max_wait_minutes
      remove :notification_batch_minutes
      remove :notifications_enabled
    end

    alter table(:users) do
      add :keep_reviews, :boolean, null: false, default: false
    end

    execute(
      "UPDATE users SET keep_reviews = COALESCE((preferences->>'keep_reviews')::boolean, false)"
    )

    alter table(:users) do
      remove :preferences
    end

    Oban.Migration.down()
  end
end
