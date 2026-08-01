defmodule Crit.NotificationsTest.FailingMailer do
  use Swoosh.Adapter

  def deliver(_email, _config), do: {:error, :smtp_down}
end

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

    Repo.update_all(from(b in NotificationBatch, where: b.id == ^batch.id),
      set: [deliver_after: DateTime.add(DateTime.utc_now(), -1, :second)]
    )

    assert :ok =
             perform_job(DeliverBatchWorker, %{
               batch_id: batch.id
             })

    assert_email_sent(fn email ->
      assert email.subject == "<Actor> commented on test.md"
      assert email.from == {"<Actor> via Crit", "test@localhost"}
      assert email.to == [{"", owner.email}]
      assert email.text_body =~ "Actor"
      assert email.html_body =~ "&lt;Actor&gt; left a comment on test.md"
      assert email.html_body =~ "&lt;script&gt;"
      refute email.html_body =~ "<script>alert"
      assert email.html_body =~ "display:none"
      assert email.html_body =~ "Notification settings"
      refute email.text_body =~ "quiet period"
      refute email.html_body =~ "quiet period"
      true
    end)

    sent = Repo.get!(NotificationBatch, batch.id)
    assert sent.status == :sent
    assert sent.finished_at
  end

  test "digest names multiple actors and includes avatars for logged-in users" do
    owner = user_fixture(%{name: "Owner"})
    alex = oauth_user_fixture(%{name: "Alex Example", picture: "https://example.com/alex.png"})
    sam = oauth_user_fixture(%{name: "Sam Other", picture: "https://example.com/sam.png"})
    review = review_fixture(%{user_id: owner.id})

    {:ok, _} =
      Reviews.create_comment(
        Scope.for_user(alex),
        review,
        valid_comment_attrs(%{"body" => "from alex"})
      )

    {:ok, _} =
      Reviews.create_comment(
        Scope.for_user(sam),
        review,
        valid_comment_attrs(%{"start_line" => 2, "end_line" => 2, "body" => "from sam"})
      )

    batch = Repo.one!(NotificationBatch)

    Repo.update_all(from(b in NotificationBatch, where: b.id == ^batch.id),
      set: [deliver_after: DateTime.add(DateTime.utc_now(), -1, :second)]
    )

    assert :ok = perform_job(DeliverBatchWorker, %{batch_id: batch.id})

    assert_email_sent(fn email ->
      assert email.subject == "Alex and Sam on test.md"
      assert email.from == {"Alex Example via Crit", "test@localhost"}
      assert email.html_body =~ "Alex and Sam commented on test.md"
      assert email.html_body =~ "https://example.com/alex.png"
      assert email.html_body =~ "https://example.com/sam.png"
      assert email.html_body =~ "from alex"
      assert email.html_body =~ "from sam"
      assert email.html_body =~ "Open review"
      refute email.html_body =~ "<ul"
      refute email.html_body =~ "On Crit since"
      true
    end)
  end

  test "anonymous-only digest keeps brand from and uses visitor name in subject" do
    owner = user_fixture(%{name: "Owner"})
    review = review_fixture(%{user_id: owner.id})

    {:ok, _} =
      Reviews.create_comment(
        Scope.for_visitor(Ecto.UUID.generate(), "Visitor"),
        review,
        valid_comment_attrs(%{"body" => "hello from visitor"})
      )

    batch = Repo.one!(NotificationBatch)

    Repo.update_all(from(b in NotificationBatch, where: b.id == ^batch.id),
      set: [deliver_after: DateTime.add(DateTime.utc_now(), -1, :second)]
    )

    assert :ok = perform_job(DeliverBatchWorker, %{batch_id: batch.id})

    assert_email_sent(fn email ->
      assert email.subject == "Visitor commented on test.md"
      assert email.from == {"", "test@localhost"} or email.from == "test@localhost"
      assert email.html_body =~ "Visitor left a comment on test.md"
      assert email.html_body =~ "email-avatar-fallback"
      assert email.html_body =~ "hello from visitor"
      refute email.html_body =~ "On Crit since"
      true
    end)
  end

  test "delivery-time preference change cancels without sending" do
    owner = user_fixture(%{name: "Owner"})
    actor = user_fixture(%{name: "Actor"})
    review = review_fixture(%{user_id: owner.id})
    {:ok, _comment} = Reviews.create_comment(Scope.for_user(actor), review, valid_comment_attrs())
    batch = Repo.one!(NotificationBatch)

    Repo.update_all(from(b in NotificationBatch, where: b.id == ^batch.id),
      set: [deliver_after: DateTime.add(DateTime.utc_now(), -1, :second)]
    )

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

  test "later activity extends deliver_after without exceeding the max wait" do
    owner = user_fixture(%{name: "Owner"})
    actor = user_fixture(%{name: "Actor"})
    review = review_fixture(%{user_id: owner.id})

    {:ok, _} = Reviews.create_comment(Scope.for_user(actor), review, valid_comment_attrs())
    batch = Repo.one!(NotificationBatch)
    first_deadline = batch.deliver_after

    # Simulate time advancing a few minutes inside the quiet window.
    past = DateTime.add(DateTime.utc_now(), -3 * 60, :second)

    Repo.update_all(from(b in NotificationBatch, where: b.id == ^batch.id),
      set: [first_event_at: past, deliver_after: DateTime.add(past, 10 * 60, :second)]
    )

    {:ok, _} =
      Reviews.create_comment(
        Scope.for_user(actor),
        review,
        valid_comment_attrs(%{"start_line" => 2, "end_line" => 2, "body" => "second"})
      )

    updated = Repo.get!(NotificationBatch, batch.id)

    assert DateTime.after?(updated.deliver_after, first_deadline) or
             DateTime.compare(updated.deliver_after, first_deadline) != :lt

    max_deadline = DateTime.add(updated.first_event_at, 60 * 60, :second)
    refute DateTime.after?(updated.deliver_after, max_deadline)
    assert Repo.aggregate(NotificationItem, :count) == 2
    assert Repo.aggregate(NotificationBatch, :count) == 1
  end

  test "worker snoozes when deliver_after is still in the future" do
    owner = user_fixture(%{name: "Owner"})
    actor = user_fixture(%{name: "Actor"})
    review = review_fixture(%{user_id: owner.id})
    {:ok, _} = Reviews.create_comment(Scope.for_user(actor), review, valid_comment_attrs())
    batch = Repo.one!(NotificationBatch)

    assert {:snooze, seconds} =
             perform_job(DeliverBatchWorker, %{batch_id: batch.id})

    assert seconds >= 1
    assert Repo.get!(NotificationBatch, batch.id).status == :pending
    refute_email_sent()
  end

  test "deleted comments empty a batch and cancel without sending" do
    owner = user_fixture(%{name: "Owner"})
    actor = user_fixture(%{name: "Actor"})
    review = review_fixture(%{user_id: owner.id})

    {:ok, comment} =
      Reviews.create_comment(Scope.for_user(actor), review, valid_comment_attrs())

    batch = Repo.one!(NotificationBatch)

    Repo.update_all(from(b in NotificationBatch, where: b.id == ^batch.id),
      set: [deliver_after: DateTime.add(DateTime.utc_now(), -1, :second)]
    )

    assert {:ok, _} = Reviews.delete_comment(Scope.for_user(actor), comment.id)
    assert Repo.aggregate(NotificationItem, :count) == 0

    assert :ok = perform_job(DeliverBatchWorker, %{batch_id: batch.id})
    assert Repo.get!(NotificationBatch, batch.id).status == :cancelled
    refute_email_sent()
  end

  test "activity while delivering opens a new pending batch" do
    owner = user_fixture(%{name: "Owner"})
    actor = user_fixture(%{name: "Actor"})
    review = review_fixture(%{user_id: owner.id})

    {:ok, _} = Reviews.create_comment(Scope.for_user(actor), review, valid_comment_attrs())
    batch = Repo.one!(NotificationBatch)

    Repo.update_all(from(b in NotificationBatch, where: b.id == ^batch.id),
      set: [
        status: :delivering,
        deliver_after: DateTime.add(DateTime.utc_now(), -1, :second)
      ]
    )

    {:ok, _} =
      Reviews.create_comment(
        Scope.for_user(actor),
        review,
        valid_comment_attrs(%{"start_line" => 3, "end_line" => 3, "body" => "while sending"})
      )

    batches = Repo.all(from b in NotificationBatch, order_by: [asc: b.inserted_at])
    assert length(batches) == 2
    assert Enum.map(batches, & &1.status) == [:delivering, :pending]
  end

  test "instance notifications disabled skips enqueue" do
    setting = Settings.get()

    {:ok, _} =
      Settings.update(%{
        max_document_mb: Crit.Setting.bytes_to_mb(setting.max_document_bytes),
        max_comments_per_review: setting.max_comments_per_review,
        max_comment_body_kb: Crit.Setting.bytes_to_kb(setting.max_comment_body_bytes),
        allowed_comment_policies: setting.allowed_comment_policies,
        allowed_review_visibilities: setting.allowed_review_visibilities,
        notifications_enabled: false
      })

    owner = user_fixture(%{name: "Owner"})
    actor = user_fixture(%{name: "Actor"})
    review = review_fixture(%{user_id: owner.id})

    assert {:ok, _} =
             Reviews.create_comment(Scope.for_user(actor), review, valid_comment_attrs())

    assert Repo.aggregate(NotificationBatch, :count) == 0
  end

  test "missing or terminal batches are no-ops" do
    assert :ok =
             perform_job(DeliverBatchWorker, %{batch_id: Ecto.UUID.generate()})

    owner = user_fixture(%{name: "Owner"})
    actor = user_fixture(%{name: "Actor"})
    review = review_fixture(%{user_id: owner.id})
    {:ok, _} = Reviews.create_comment(Scope.for_user(actor), review, valid_comment_attrs())
    batch = Repo.one!(NotificationBatch)

    Repo.update_all(from(b in NotificationBatch, where: b.id == ^batch.id),
      set: [
        status: :sent,
        finished_at: DateTime.utc_now(),
        deliver_after: DateTime.add(DateTime.utc_now(), -1, :second)
      ]
    )

    assert :ok = perform_job(DeliverBatchWorker, %{batch_id: batch.id})
    refute_email_sent()
  end

  test "already-claimed delivering batch is skipped on first attempt" do
    owner = user_fixture(%{name: "Owner"})
    actor = user_fixture(%{name: "Actor"})
    review = review_fixture(%{user_id: owner.id})
    {:ok, _} = Reviews.create_comment(Scope.for_user(actor), review, valid_comment_attrs())
    batch = Repo.one!(NotificationBatch)

    Repo.update_all(from(b in NotificationBatch, where: b.id == ^batch.id),
      set: [
        status: :delivering,
        deliver_after: DateTime.add(DateTime.utc_now(), -1, :second)
      ]
    )

    assert :ok = perform_job(DeliverBatchWorker, %{batch_id: batch.id}, attempt: 1)
    refute_email_sent()
    assert Repo.get!(NotificationBatch, batch.id).status == :delivering
  end

  test "retry attempt reclaims a delivering batch" do
    owner = user_fixture(%{name: "Owner"})
    actor = user_fixture(%{name: "Actor"})
    review = review_fixture(%{user_id: owner.id})
    {:ok, _} = Reviews.create_comment(Scope.for_user(actor), review, valid_comment_attrs())
    batch = Repo.one!(NotificationBatch)

    Repo.update_all(from(b in NotificationBatch, where: b.id == ^batch.id),
      set: [
        status: :delivering,
        deliver_after: DateTime.add(DateTime.utc_now(), -1, :second)
      ]
    )

    assert :ok = perform_job(DeliverBatchWorker, %{batch_id: batch.id}, attempt: 2)
    assert Repo.get!(NotificationBatch, batch.id).status == :sent
  end

  test "delivery failure marks retryable then failed on final attempt" do
    original = Application.get_env(:crit, Crit.Mailer)
    Application.put_env(:crit, Crit.Mailer, adapter: Crit.NotificationsTest.FailingMailer)

    on_exit(fn -> Application.put_env(:crit, Crit.Mailer, original) end)

    owner = user_fixture(%{name: "Owner"})
    actor = user_fixture(%{name: "Actor"})
    review = review_fixture(%{user_id: owner.id})
    {:ok, _} = Reviews.create_comment(Scope.for_user(actor), review, valid_comment_attrs())
    batch = make_due!(Repo.one!(NotificationBatch))

    assert {:error, :smtp_down} =
             perform_job(DeliverBatchWorker, %{batch_id: batch.id}, attempt: 1)

    assert Repo.get!(NotificationBatch, batch.id).status == :retryable

    assert {:error, :smtp_down} =
             perform_job(DeliverBatchWorker, %{batch_id: batch.id}, attempt: 3)

    assert Repo.get!(NotificationBatch, batch.id).status == :failed
  end

  test "instance disabled at delivery cancels without sending" do
    owner = user_fixture(%{name: "Owner"})
    actor = user_fixture(%{name: "Actor"})
    review = review_fixture(%{user_id: owner.id})
    {:ok, _} = Reviews.create_comment(Scope.for_user(actor), review, valid_comment_attrs())
    batch = make_due!(Repo.one!(NotificationBatch))

    setting = Settings.get()

    {:ok, _} =
      Settings.update(%{
        max_document_mb: Crit.Setting.bytes_to_mb(setting.max_document_bytes),
        max_comments_per_review: setting.max_comments_per_review,
        max_comment_body_kb: Crit.Setting.bytes_to_kb(setting.max_comment_body_bytes),
        allowed_comment_policies: setting.allowed_comment_policies,
        allowed_review_visibilities: setting.allowed_review_visibilities,
        notifications_enabled: false
      })

    assert :ok = perform_job(DeliverBatchWorker, %{batch_id: batch.id})
    assert Repo.get!(NotificationBatch, batch.id).status == :cancelled
    refute_email_sent()
  end

  test "digest names three-plus actors, truncates long names, and caps items" do
    owner = user_fixture(%{name: "Owner"})
    a = user_fixture(%{name: "Alex Example"})
    b = user_fixture(%{name: "Blair Example"})
    c = user_fixture(%{name: "Casey Example"})

    review =
      review_fixture(%{
        user_id: owner.id,
        files: [
          %{
            "path" => "very-long-document-name-for-truncation.md",
            "content" => Enum.map_join(1..30, "\n", &"line #{&1}")
          }
        ]
      })

    long_body = String.duplicate("word ", 80)

    for {actor, line} <- [{a, 1}, {b, 2}, {c, 3}] do
      assert {:ok, _} =
               Reviews.create_comment(
                 Scope.for_user(actor),
                 review,
                 valid_comment_attrs(%{
                   "start_line" => line,
                   "end_line" => line,
                   "body" => long_body
                 })
               )
    end

    # Extra activity past the digest cap (20 shown).
    for line <- 4..22 do
      assert {:ok, _} =
               Reviews.create_comment(
                 Scope.for_user(a),
                 review,
                 valid_comment_attrs(%{
                   "start_line" => line,
                   "end_line" => line,
                   "body" => "extra #{line}"
                 })
               )
    end

    batch = make_due!(Repo.one!(NotificationBatch))
    assert :ok = perform_job(DeliverBatchWorker, %{batch_id: batch.id})

    assert_email_sent(fn email ->
      assert email.subject =~ "Alex and 2 others on"
      assert email.subject =~ "…"
      assert email.html_body =~ "Alex and 2 others commented on"
      assert email.html_body =~ "Open review — and"
      assert email.text_body =~ "…and"
      assert email.html_body =~ "…"
      true
    end)
  end

  test "cleanup worker deletes old terminal batches and no-ops when retention is forever" do
    owner = user_fixture(%{name: "Owner"})
    actor = user_fixture(%{name: "Actor"})
    review = review_fixture(%{user_id: owner.id})
    {:ok, _} = Reviews.create_comment(Scope.for_user(actor), review, valid_comment_attrs())
    batch = Repo.one!(NotificationBatch)

    old = DateTime.add(DateTime.utc_now(), -40, :day)

    Repo.update_all(from(b in NotificationBatch, where: b.id == ^batch.id),
      set: [status: :sent, finished_at: old, deliver_after: old]
    )

    assert :ok = perform_job(Crit.Notifications.CleanupWorker, %{})
    assert Repo.get(NotificationBatch, batch.id) == nil

    setting = Settings.get()

    {:ok, _} =
      Settings.update(%{
        max_document_mb: Crit.Setting.bytes_to_mb(setting.max_document_bytes),
        max_comments_per_review: setting.max_comments_per_review,
        max_comment_body_kb: Crit.Setting.bytes_to_kb(setting.max_comment_body_bytes),
        allowed_comment_policies: setting.allowed_comment_policies,
        allowed_review_visibilities: setting.allowed_review_visibilities,
        notifications_enabled: true,
        notification_retention_days: 0
      })

    assert :ok = perform_job(Crit.Notifications.CleanupWorker, %{})
  end

  test "notification batch changeset validates required fields" do
    changeset = Crit.Notifications.NotificationBatch.changeset(%Crit.Notifications.NotificationBatch{}, %{})
    refute changeset.valid?
  end

  defp make_due!(batch) do
    Repo.update_all(from(b in NotificationBatch, where: b.id == ^batch.id),
      set: [deliver_after: DateTime.add(DateTime.utc_now(), -1, :second)]
    )

    Repo.get!(NotificationBatch, batch.id)
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
