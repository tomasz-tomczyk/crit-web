defmodule Crit.ReviewsSubThreadsTest do
  use Crit.DataCase, async: true

  import Ecto.Query

  alias Crit.Accounts.Scope
  alias Crit.{Comment, Repo, Reviews}

  defp anon_scope(name \\ "Visitor"),
    do: Scope.for_visitor("anon-#{System.unique_integer([:positive])}", name)

  defp insert_user!(name) do
    %Crit.User{}
    |> Crit.User.oauth_changeset(%{
      provider: "test",
      provider_uid: "uid-#{System.unique_integer([:positive])}",
      email: "u-#{System.unique_integer([:positive])}@example.com",
      name: name
    })
    |> Repo.insert!()
  end

  @plan "# Plan\n\nStep 1\n\nStep 2\n"

  defp review_with_thread do
    scope = anon_scope()

    {:ok, review} =
      Reviews.create_review(scope, [%{"path" => "plan.md", "content" => @plan}], 1, [], [])

    {:ok, root} =
      Reviews.create_comment(
        scope,
        review,
        %{"start_line" => 3, "end_line" => 3, "body" => "Expand this", "scope" => "line"},
        file_path: "plan.md"
      )

    {:ok, reply} =
      Reviews.create_reply(scope, root.id, %{"body" => "Done, see step 1"}, review.id)

    %{scope: scope, review: Repo.reload!(review), root: root, reply: reply}
  end

  defp sub_thread!(scope, anchor, review, body \\ "Why?", quote \\ "step 1") do
    {:ok, sub_thread} =
      Reviews.create_sub_thread(
        scope,
        anchor.id,
        %{"body" => body, "quote" => quote, "quote_offset" => 6},
        review.id
      )

    sub_thread
  end

  defp ids(review_id) do
    Repo.all(from c in Comment, where: c.review_id == ^review_id, select: c.id) |> MapSet.new()
  end

  defp sub_threads_of(review_id) do
    Repo.all(
      from c in Comment,
        where: c.review_id == ^review_id and not is_nil(c.anchor_comment_id),
        order_by: [asc: c.inserted_at]
    )
  end

  describe "create_sub_thread/4" do
    test "anchors a root without lines on a comment, in its thread's scope and file" do
      %{scope: scope, review: review, root: root} = review_with_thread()

      assert {:ok, sub_thread} =
               Reviews.create_sub_thread(
                 scope,
                 root.id,
                 %{"body" => "Why?", "quote" => "Expand", "quote_offset" => 0},
                 review.id
               )

      assert sub_thread.anchor_comment_id == root.id
      assert is_nil(sub_thread.parent_id)
      assert is_nil(sub_thread.start_line) and is_nil(sub_thread.end_line)
      assert sub_thread.scope == "line"
      assert sub_thread.file_path == "plan.md"
      assert sub_thread.quote == "Expand"
      assert sub_thread.quote_offset == 0
      assert sub_thread.review_round == review.review_round
      assert sub_thread.author_display_name == "Visitor"
      assert sub_thread.author_identity == scope.identity
    end

    test "anchors on a reply, taking the scope and file of the reply's thread" do
      %{scope: scope, review: review, reply: reply} = review_with_thread()

      sub_thread = sub_thread!(scope, reply, review)

      assert sub_thread.anchor_comment_id == reply.id
      assert sub_thread.scope == "line"
      assert sub_thread.file_path == "plan.md"
    end

    test "rejects an anchor from another review, an unknown id and a malformed id" do
      %{scope: scope, review: review} = review_with_thread()
      %{root: other_root} = review_with_thread()

      for anchor_id <- [other_root.id, Ecto.UUID.generate(), "not-a-uuid"] do
        assert {:error, :not_found} =
                 Reviews.create_sub_thread(scope, anchor_id, %{"body" => "x"}, review.id)
      end
    end

    test "follows the review's comment policy" do
      %{scope: scope, review: review, root: root} = review_with_thread()
      review |> Ecto.Changeset.change(comment_policy: :disallowed) |> Repo.update!()

      assert {:error, :comments_disallowed} =
               Reviews.create_sub_thread(scope, root.id, %{"body" => "x"}, review.id)
    end

    test "requires a body and ignores fields the caller may not set" do
      %{scope: scope, review: review, root: root} = review_with_thread()

      assert {:error, %Ecto.Changeset{} = changeset} =
               Reviews.create_sub_thread(scope, root.id, %{"body" => ""}, review.id)

      assert %{body: [_]} = errors_on(changeset)

      {:ok, sub_thread} =
        Reviews.create_sub_thread(
          scope,
          root.id,
          %{"body" => "x", "resolved" => true, "external_id" => "c_x", "start_line" => 4},
          review.id
        )

      refute sub_thread.resolved
      assert is_nil(sub_thread.external_id)
      assert is_nil(sub_thread.start_line)
    end
  end

  describe "replies, resolution and deletion" do
    test "a sub-thread takes replies and resolves apart from its anchor's thread" do
      %{scope: scope, review: review, root: root, reply: reply} = review_with_thread()
      sub_thread = sub_thread!(scope, reply, review)

      assert {:ok, answer} =
               Reviews.create_reply(scope, sub_thread.id, %{"body" => "Because"}, review.id)

      assert answer.parent_id == sub_thread.id

      assert {:ok, resolved} = Reviews.resolve_comment(scope, sub_thread.id, true, review.id)
      assert resolved.resolved
      refute Repo.reload!(root).resolved

      assert {:ok, _} = Reviews.resolve_comment(scope, root.id, true, review.id)
      assert {:ok, _} = Reviews.resolve_comment(scope, sub_thread.id, false, review.id)
      assert Repo.reload!(root).resolved
      refute Repo.reload!(sub_thread).resolved
    end

    test "deleting a comment deletes the sub-threads under it at any depth" do
      %{scope: scope, review: review, root: root, reply: reply} = review_with_thread()
      on_root = sub_thread!(scope, root, review)
      on_reply = sub_thread!(scope, reply, review)
      {:ok, answer} = Reviews.create_reply(scope, on_reply.id, %{"body" => "a"}, review.id)
      _deep = sub_thread!(scope, answer, review)
      _deeper = sub_thread!(scope, on_root, review)

      assert MapSet.size(ids(review.id)) == 7
      assert {:ok, _} = Reviews.delete_comment(scope, root.id)
      assert ids(review.id) == MapSet.new()
    end

    test "deleting a reply deletes its sub-threads and leaves the rest of the thread" do
      %{scope: scope, review: review, root: root, reply: reply} = review_with_thread()
      on_root = sub_thread!(scope, root, review)
      on_reply = sub_thread!(scope, reply, review)
      {:ok, answer} = Reviews.create_reply(scope, on_reply.id, %{"body" => "a"}, review.id)
      deep = sub_thread!(scope, on_reply, review)

      assert {:ok, _} = Reviews.delete_reply(scope, reply.id)

      assert ids(review.id) == MapSet.new([root.id, on_root.id])
      refute Repo.get(Comment, answer.id)
      refute Repo.get(Comment, deep.id)
    end
  end

  describe "reads" do
    test "serialize_threads nests sub-threads under the message they comment on" do
      %{scope: scope, review: review, root: root, reply: reply} = review_with_thread()
      on_root = sub_thread!(scope, root, review, "On the comment", "Expand")
      on_reply = sub_thread!(scope, reply, review, "On the reply", "step 1")
      {:ok, answer} = Reviews.create_reply(scope, on_reply.id, %{"body" => "a"}, review.id)
      deep = sub_thread!(scope, answer, review, "Deeper", "a")

      assert [thread] = review |> Reviews.list_comments() |> Reviews.serialize_threads()
      assert thread.id == root.id
      assert [%{id: on_root_id, sub_threads: [], replies: []}] = thread.sub_threads
      assert on_root_id == on_root.id

      assert [serialized_reply] = thread.replies
      assert serialized_reply.id == reply.id
      assert Map.has_key?(serialized_reply, :external_id)
      assert [%{id: on_reply_id, replies: [serialized_answer]}] = serialized_reply.sub_threads
      assert on_reply_id == on_reply.id
      assert serialized_answer.id == answer.id
      assert [%{id: deep_id, anchor_comment_id: deep_anchor}] = serialized_answer.sub_threads
      assert deep_id == deep.id and deep_anchor == answer.id
    end
  end

  describe "upsert_review/4 without a comments list" do
    test "leaves sub-threads out of the line carry" do
      %{scope: scope, review: review, reply: reply} = review_with_thread()
      sub_thread = sub_thread!(scope, reply, review)

      assert {:ok, :updated, _} =
               Reviews.upsert_review(scope, review.token, review.delete_token, %{
                 "files" => [%{"path" => "plan.md", "content" => "# Plan\n\nNew\n\n" <> @plan}]
               })

      stored = Repo.reload!(sub_thread)
      assert is_nil(stored.start_line) and is_nil(stored.end_line)
      refute stored.drifted
      assert stored.anchor_comment_id == reply.id
    end
  end

  # The share payload crit sends: roots in `comments`, sub-threads anchored on
  # them by `parent_external_id`.
  defp share_comments do
    [
      %{
        "file" => "plan.md",
        "start_line" => 3,
        "end_line" => 3,
        "scope" => "line",
        "body" => "Expand this",
        "external_id" => "c_root",
        "replies" => [%{"body" => "Done", "external_id" => "rp_done"}]
      },
      %{"body" => "Overall", "scope" => "review", "external_id" => "r_general"}
    ]
  end

  # Listed deepest first: the anchors resolve whatever the order.
  defp share_sub_threads do
    [
      %{
        "external_id" => "c_deep",
        "parent_external_id" => "rp_because",
        "body" => "Really?",
        "quote" => "Because"
      },
      %{
        "external_id" => "c_on_reply",
        "parent_external_id" => "rp_done",
        "body" => "Done how?",
        "quote" => "Done",
        "quote_offset" => 0,
        "author_display_name" => "Alice",
        "review_round" => 2,
        "replies" => [%{"body" => "Because", "external_id" => "rp_because"}]
      },
      %{
        "external_id" => "r_on_general",
        "parent_external_id" => "r_general",
        "body" => "Which part?",
        "quote" => "Overall",
        "resolved" => true
      },
      %{"external_id" => "c_orphan", "parent_external_id" => "rp_gone", "body" => "Lost"},
      %{"external_id" => "c_no_anchor", "body" => "Nowhere"}
    ]
  end

  defp by_external_id(review_id) do
    Repo.all(from c in Comment, where: c.review_id == ^review_id)
    |> Map.new(&{&1.external_id, &1})
  end

  defp assert_shared_tree(review_id) do
    rows = by_external_id(review_id)

    refute Map.has_key?(rows, "c_orphan")
    refute Map.has_key?(rows, "c_no_anchor")

    assert rows["c_on_reply"].anchor_comment_id == rows["rp_done"].id
    assert rows["c_on_reply"].scope == "line"
    assert rows["c_on_reply"].file_path == "plan.md"
    assert is_nil(rows["c_on_reply"].start_line)
    assert rows["c_on_reply"].quote == "Done"
    assert rows["c_on_reply"].quote_offset == 0
    assert rows["c_on_reply"].review_round == 2
    assert rows["c_on_reply"].author_display_name == "Alice"
    assert rows["rp_because"].parent_id == rows["c_on_reply"].id
    assert rows["c_deep"].anchor_comment_id == rows["rp_because"].id
    assert rows["c_deep"].file_path == "plan.md"
    assert rows["r_on_general"].anchor_comment_id == rows["r_general"].id
    assert rows["r_on_general"].scope == "review"
    assert rows["r_on_general"].resolved
    rows
  end

  describe "share imports" do
    test "create_review inserts sub-threads once their anchors are in" do
      {:ok, review} =
        Reviews.create_review(
          anon_scope(),
          [%{"path" => "plan.md", "content" => @plan}],
          1,
          [hd(share_comments())],
          tl(share_comments()),
          sub_threads: share_sub_threads()
        )

      assert_shared_tree(review.id)
    end

    test "a re-share keeps the sub-threads anchored, and the verified author" do
      user = insert_user!("Alice")

      {:ok, review} =
        Reviews.create_review(
          Scope.for_user(user),
          [%{"path" => "plan.md", "content" => @plan}],
          1,
          share_comments(),
          [],
          sub_threads: share_sub_threads()
        )

      by_external_id(review.id)["c_on_reply"]
      |> Ecto.Changeset.change(user_id: user.id, author_identity: nil)
      |> Repo.update!()

      payload = %{
        "files" => [%{"path" => "plan.md", "content" => @plan}],
        "comments" => share_comments(),
        "sub_threads" => share_sub_threads()
      }

      for _ <- 1..2 do
        assert {:ok, :no_changes, _} =
                 Reviews.upsert_review(anon_scope(), review.token, review.delete_token, payload)

        rows = assert_shared_tree(review.id)
        assert rows["c_on_reply"].user_id == user.id
      end
    end

    test "an explicit empty sub_threads list replaces the stored ones" do
      {:ok, review} =
        Reviews.create_review(
          anon_scope(),
          [%{"path" => "plan.md", "content" => @plan}],
          1,
          share_comments(),
          [],
          sub_threads: share_sub_threads()
        )

      assert sub_threads_of(review.id) != []

      assert {:ok, :no_changes, _} =
               Reviews.upsert_review(anon_scope(), review.token, review.delete_token, %{
                 "files" => [%{"path" => "plan.md", "content" => @plan}],
                 "comments" => share_comments(),
                 "sub_threads" => []
               })

      assert sub_threads_of(review.id) == []
    end

    test "a re-share without sub_threads keeps the stored ones on their anchors" do
      scope = anon_scope()

      {:ok, review} =
        Reviews.create_review(
          scope,
          [%{"path" => "plan.md", "content" => @plan}],
          1,
          share_comments(),
          []
        )

      rows = by_external_id(review.id)
      on_reply = sub_thread!(scope, rows["rp_done"], review, "Done how?", "Done")
      {:ok, answer} = Reviews.create_reply(scope, on_reply.id, %{"body" => "So"}, review.id)
      on_answer = sub_thread!(scope, answer, review, "Sure?", "So")
      _on_general = sub_thread!(scope, rows["r_general"], review, "Which?", "Overall")

      # An older crit re-shares: no sub_threads key, and the general comment is
      # gone (resolved locally), so its sub-thread has nothing to stay on.
      assert {:ok, :no_changes, _} =
               Reviews.upsert_review(scope, review.token, review.delete_token, %{
                 "files" => [%{"path" => "plan.md", "content" => @plan}],
                 "comments" => [hd(share_comments())]
               })

      new_rows = by_external_id(review.id)
      kept = Map.new(sub_threads_of(review.id), &{&1.body, &1})
      assert kept |> Map.keys() |> Enum.sort() == ["Done how?", "Sure?"]
      %{"Done how?" => kept_on_reply, "Sure?" => kept_on_answer} = kept

      assert kept_on_reply.anchor_comment_id == new_rows["rp_done"].id
      assert kept_on_reply.author_identity == scope.identity
      assert kept_on_reply.inserted_at == on_reply.inserted_at
      assert [kept_answer] = Repo.all(from c in Comment, where: c.parent_id == ^kept_on_reply.id)
      assert kept_answer.body == "So"
      assert kept_on_answer.anchor_comment_id == kept_answer.id
      refute Repo.get(Comment, on_answer.id)
    end

    test "a re-share without sub_threads finds web-written anchors again by content" do
      scope = anon_scope()

      {:ok, review} =
        Reviews.create_review(
          scope,
          [%{"path" => "plan.md", "content" => @plan}],
          1,
          share_comments(),
          []
        )

      {:ok, web_root} =
        Reviews.create_comment(
          scope,
          review,
          %{"start_line" => 5, "end_line" => 5, "body" => "Web point", "scope" => "line"},
          file_path: "plan.md"
        )

      {:ok, web_reply} =
        Reviews.create_reply(scope, web_root.id, %{"body" => "web answer"}, review.id)

      sub_thread!(scope, web_root, review, "On the web point", "Web")
      sub_thread!(scope, web_reply, review, "On the web answer", "answer")

      # An older crit fetched the web thread (as web-1, its reply without an
      # id), its local carry moved it a line down, and it re-shares.
      imported_web_thread = %{
        "file" => "plan.md",
        "start_line" => 6,
        "end_line" => 6,
        "scope" => "line",
        "body" => "Web point",
        "external_id" => "web-1",
        "replies" => [%{"body" => "web answer"}]
      }

      assert {:ok, :no_changes, _} =
               Reviews.upsert_review(scope, review.token, review.delete_token, %{
                 "files" => [%{"path" => "plan.md", "content" => @plan}],
                 "comments" => share_comments() ++ [imported_web_thread]
               })

      new_web_root = by_external_id(review.id)["web-1"]
      [new_web_reply] = Repo.all(from c in Comment, where: c.parent_id == ^new_web_root.id)
      kept = Map.new(sub_threads_of(review.id), &{&1.body, &1})

      assert kept["On the web point"].anchor_comment_id == new_web_root.id
      assert kept["On the web answer"].anchor_comment_id == new_web_reply.id
    end

    test "a re-share without sub_threads tells same-content anchors apart by their order" do
      scope = anon_scope()
      plan = "# Plan\n\nStep 1\n\nStep 2\n\nStep 3\n"
      files = [%{"path" => "plan.md", "content" => plan}]
      {:ok, review} = Reviews.create_review(scope, files, 1, [], [])

      web = fn line ->
        {:ok, thread} =
          Reviews.create_comment(
            scope,
            review,
            %{"start_line" => line, "end_line" => line, "body" => "nit", "scope" => "line"},
            file_path: "plan.md"
          )

        thread
      end

      # Two "nit" threads, each with two "Done" replies and a "+1".
      threads =
        for line <- [5, 7] do
          thread = web.(line)

          replies =
            for body <- ["Done", "Done", "+1"] do
              {:ok, reply} = Reviews.create_reply(scope, thread.id, %{"body" => body}, review.id)
              reply
            end

          {thread, replies}
        end

      [{first, _}, {second, [done_a, done_b, second_plus]}] = threads
      sub_thread!(scope, first, review, "On the first nit", "nit")
      sub_thread!(scope, second, review, "On the second nit", "nit")
      sub_thread!(scope, done_a, review, "On a Done", "Done")
      sub_thread!(scope, done_b, review, "On the other Done", "Done")
      sub_thread!(scope, second_plus, review, "On the second +1", "+1")

      # An older crit fetched both threads (web-1, web-2, replies without ids)
      # and re-shares them, without sub_threads.
      reshared =
        for {{thread, replies}, n} <- Enum.with_index(threads, 1) do
          %{
            "file" => "plan.md",
            "start_line" => thread.start_line,
            "end_line" => thread.end_line,
            "scope" => "line",
            "body" => "nit",
            "external_id" => "web-#{n}",
            "replies" => Enum.map(replies, &%{"body" => &1.body})
          }
        end

      assert {:ok, :no_changes, _} =
               Reviews.upsert_review(scope, review.token, review.delete_token, %{
                 "files" => files,
                 "comments" => reshared
               })

      rows = by_external_id(review.id)
      second_replies = Repo.all(from c in Comment, where: c.parent_id == ^rows["web-2"].id)
      new_dones = for r <- second_replies, r.body == "Done", into: MapSet.new(), do: r.id
      [new_second_plus] = for r <- second_replies, r.body == "+1", do: r
      kept = Map.new(sub_threads_of(review.id), &{&1.body, &1.anchor_comment_id})

      assert kept["On the first nit"] == rows["web-1"].id
      assert kept["On the second nit"] == rows["web-2"].id
      # Each "Done" of the second thread keeps its own sub-thread.
      assert MapSet.new([kept["On a Done"], kept["On the other Done"]]) == new_dones
      assert kept["On the second +1"] == new_second_plus.id
    end

    test "create_review counts the sub-threads it inserts, not those it drops" do
      before = Crit.Statistics.totals().comments_created

      {:ok, review} =
        Reviews.create_review(
          anon_scope(),
          [%{"path" => "plan.md", "content" => @plan}],
          1,
          share_comments(),
          [],
          sub_threads: [
            %{"external_id" => "c_kept", "parent_external_id" => "c_root", "body" => "kept"},
            %{"external_id" => "c_lost", "parent_external_id" => "nowhere", "body" => "lost"}
          ]
        )

      assert Enum.map(sub_threads_of(review.id), & &1.body) == ["kept"]
      # The two threads of share_comments/0, and the one sub-thread inserted.
      assert Crit.Statistics.totals().comments_created - before == 3
    end
  end
end
