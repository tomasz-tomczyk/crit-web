defmodule Crit.NotificationsTest do
  use Crit.DataCase, async: false
  use Oban.Testing, repo: Crit.Repo

  import Crit.AccountsFixtures
  import Crit.ReviewsFixtures
  import Swoosh.TestAssertions

  alias Crit.Accounts.Scope
  alias Crit.Notifications.{DeliverBatchWorker, NotificationBatch, NotificationItem}
  alias Crit.{Repo, Reviews, Settings}

  setup do
    enable_notifications!()
    :ok
  end

  test "a top-level comment queues one digest for the review owner" do
    owner = user_fixture(%{name: "Owner"})
    actor = user_fixture(%{name: "Actor"})
    review = review_fixture(%{user_id: owner.id})

    assert {:ok, comment} =
             Reviews.create_comment(Scope.for_user(actor), review, valid_comment_attrs())

    assert [%NotificationBatch{} = batch] = Repo.all(NotificationBatch)
    assert batch.recipient_user_id == owner.id
    assert batch.review_id == review.id
    assert [%NotificationItem{comment_id: comment_id}] = Repo.all(NotificationItem)
    assert comment_id == comment.id

    assert_enqueued(
      worker: DeliverBatchWorker,
      args: %{batch_id: batch.id},
      queue: :notifications
    )

    scheduled_at = Repo.one!(from job in Oban.Job, select: job.scheduled_at)
    seconds_until_delivery = DateTime.diff(scheduled_at, DateTime.utc_now())
    assert seconds_until_delivery in 590..600
  end

  test "owner activity does not notify the owner" do
    owner = user_fixture(%{name: "Owner"})
    review = review_fixture(%{user_id: owner.id})

    assert {:ok, _comment} =
             Reviews.create_comment(Scope.for_user(owner), review, valid_comment_attrs())

    assert Repo.aggregate(NotificationBatch, :count) == 0
    refute_enqueued(worker: DeliverBatchWorker)
  end

  test "a reply deduplicates owner and authenticated thread participants and excludes actor" do
    owner = user_fixture(%{name: "Owner"})
    root_author = user_fixture(%{name: "Root"})
    prior_replier = user_fixture(%{name: "Prior"})
    actor = user_fixture(%{name: "Actor"})
    review = review_fixture(%{user_id: owner.id})

    {:ok, root} =
      Reviews.create_comment(Scope.for_user(root_author), review, valid_comment_attrs())

    {:ok, _prior} =
      Reviews.create_reply(
        Scope.for_user(prior_replier),
        root.id,
        %{"body" => "first"},
        review.id
      )

    # Isolate the recipient calculation for the new reply from earlier batches.
    Repo.delete_all(NotificationBatch)
    Repo.delete_all(Oban.Job)

    assert {:ok, reply} =
             Reviews.create_reply(
               Scope.for_user(actor),
               root.id,
               %{"body" => "second"},
               review.id
             )

    recipient_ids =
      Repo.all(from b in NotificationBatch, select: b.recipient_user_id)
      |> MapSet.new()

    assert recipient_ids == MapSet.new([owner.id, root_author.id, prior_replier.id])
    refute actor.id in recipient_ids
    assert Repo.aggregate(NotificationItem, :count) == 3

    assert Repo.all(from i in NotificationItem, select: i.comment_id) ==
             List.duplicate(reply.id, 3)
  end

  test "disabled user preference skips enqueue" do
    owner = user_fixture(%{name: "Owner"})
    actor = user_fixture(%{name: "Actor"})
    review = review_fixture(%{user_id: owner.id})

    {:ok, _owner} =
      Crit.Accounts.update_preferences(owner, %{discussion_notifications_enabled: false})

    assert {:ok, _comment} =
             Reviews.create_comment(Scope.for_user(actor), review, valid_comment_attrs())

    assert Repo.aggregate(NotificationBatch, :count) == 0
  end

  test "anonymous activity can notify an authenticated owner" do
    owner = user_fixture(%{name: "Owner"})
    review = review_fixture(%{user_id: owner.id})

    assert {:ok, _comment} =
             Reviews.create_comment(
               Scope.for_visitor(Ecto.UUID.generate(), "Visitor"),
               review,
               valid_comment_attrs()
             )

    assert Repo.one!(NotificationBatch).recipient_user_id == owner.id
  end

  test "a due batch sends one text and HTML digest and is marked sent" do
    owner = user_fixture(%{name: "Owner"})
    actor = user_fixture(%{name: "<Actor>"})
    review = review_fixture(%{user_id: owner.id})

    {:ok, _comment} =
      Reviews.create_comment(
        Scope.for_user(actor),
        review,
        valid_comment_attrs(%{"body" => "<script>alert('no')</script> useful"})
      )

    batch = Repo.one!(NotificationBatch)

    assert :ok =
             perform_job(DeliverBatchWorker, %{
               batch_id: batch.id
             })

    assert_email_sent(fn email ->
      assert email.subject == "1 new updates on your Crit review"
      assert email.to == [{"", owner.email}]
      assert email.text_body =~ "Actor"
      assert email.html_body =~ "&lt;script&gt;"
      refute email.html_body =~ "<script>"
      true
    end)

    sent = Repo.get!(NotificationBatch, batch.id)
    assert sent.status == :sent
    assert sent.finished_at
  end

  test "delivery-time preference change cancels without sending" do
    owner = user_fixture(%{name: "Owner"})
    actor = user_fixture(%{name: "Actor"})
    review = review_fixture(%{user_id: owner.id})
    {:ok, _comment} = Reviews.create_comment(Scope.for_user(actor), review, valid_comment_attrs())
    batch = Repo.one!(NotificationBatch)

    {:ok, _owner} =
      Crit.Accounts.update_preferences(owner, %{discussion_notifications_enabled: false})

    assert :ok =
             perform_job(DeliverBatchWorker, %{
               batch_id: batch.id
             })

    assert Repo.get!(NotificationBatch, batch.id).status == :cancelled
    refute_email_sent()
  end

  test "comments reconciled during a CLI share do not enqueue notifications" do
    owner = user_fixture(%{name: "Owner"})
    scope = Scope.for_user(owner)

    comments = [
      %{
        "file" => "test.md",
        "start_line" => 1,
        "end_line" => 1,
        "body" => "Imported comment"
      }
    ]

    assert {:ok, _review} =
             Reviews.create_review(
               scope,
               [%{"path" => "test.md", "content" => "hello"}],
               1,
               comments
             )

    assert Repo.aggregate(NotificationBatch, :count) == 0
    refute_enqueued(worker: DeliverBatchWorker)
  end

  defp enable_notifications! do
    setting = Settings.get()

    {:ok, _setting} =
      Settings.update(%{
        max_document_mb: Crit.Setting.bytes_to_mb(setting.max_document_bytes),
        max_comments_per_review: setting.max_comments_per_review,
        max_comment_body_kb: Crit.Setting.bytes_to_kb(setting.max_comment_body_bytes),
        allowed_comment_policies: setting.allowed_comment_policies,
        allowed_review_visibilities: setting.allowed_review_visibilities,
        notifications_enabled: true,
        notification_batch_minutes: 10,
        notification_max_wait_minutes: 60,
        notification_retention_days: 30
      })
  end
end
