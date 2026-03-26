defmodule Crit.ReviewsTest do
  use Crit.DataCase, async: true

  alias Crit.{Repo, Review, Reviews}

  import Crit.ReviewsFixtures

  describe "create_review/3" do
    test "creates a review with files" do
      files = [%{"path" => "test.md", "content" => "# Hello"}]
      {:ok, review} = Reviews.create_review(files, 0, [])

      review = Reviews.get_by_token(review.token)
      assert review.review_round == 0
      assert review.token != nil
      assert review.delete_token != nil
      assert length(review.files) == 1
      assert hd(review.files).file_path == "test.md"
      assert hd(review.files).content == "# Hello"
    end

    test "creates a review with seed comments" do
      files = [%{"path" => "test.md", "content" => "# Hello"}]

      comments = [
        %{"file" => "test.md", "start_line" => 1, "end_line" => 2, "body" => "First comment"},
        %{"file" => "test.md", "start_line" => 3, "end_line" => 3, "body" => "Second comment"}
      ]

      {:ok, review} = Reviews.create_review(files, 1, comments)

      loaded = Reviews.list_comments(review)
      assert length(loaded) == 2
      assert Enum.all?(loaded, &(&1.author_identity == "imported"))
    end

    test "returns error for file with invalid content (missing content)" do
      files = [%{"path" => "a.go"}]
      assert {:error, %Ecto.Changeset{}} = Reviews.create_review(files, 0, [])
    end

    test "returns error when total size exceeds 10 MB" do
      big_content = String.duplicate("x", 5_500_000)

      files = [
        %{"path" => "a.go", "content" => big_content},
        %{"path" => "b.go", "content" => big_content}
      ]

      assert {:error, :total_size_exceeded} = Reviews.create_review(files, 0, [])
    end

    test "creates review with multiple files and per-file comments" do
      files = [
        %{"path" => "src/main.go", "content" => "package main"},
        %{"path" => "src/util.go", "content" => "package util"}
      ]

      comments = [
        %{"file" => "src/main.go", "start_line" => 1, "end_line" => 1, "body" => "rename this"},
        %{"file" => "src/util.go", "start_line" => 1, "end_line" => 1, "body" => "nice"}
      ]

      assert {:ok, review} = Reviews.create_review(files, 1, comments)
      assert review.token
      assert review.delete_token

      review = Reviews.get_by_token(review.token)
      assert length(review.files) == 2

      assert Enum.map(review.files, & &1.file_path) |> Enum.sort() == [
               "src/main.go",
               "src/util.go"
             ]

      assert length(review.comments) == 2

      main_comment = Enum.find(review.comments, &(&1.file_path == "src/main.go"))
      assert main_comment.body == "rename this"

      util_comment = Enum.find(review.comments, &(&1.file_path == "src/util.go"))
      assert util_comment.body == "nice"
    end

    test "files are ordered by position" do
      files = [
        %{"path" => "z.go", "content" => "z"},
        %{"path" => "a.go", "content" => "a"}
      ]

      {:ok, review} = Reviews.create_review(files, 0, [])
      review = Reviews.get_by_token(review.token)

      assert Enum.map(review.files, & &1.file_path) == ["z.go", "a.go"]
    end

    test "create_review imports comments with resolved and replies" do
      files = [%{"path" => "f.md", "content" => "x"}]

      comments = [
        %{
          "file" => "f.md",
          "start_line" => 1,
          "end_line" => 1,
          "body" => "fix this",
          "resolved" => true,
          "replies" => [
            %{"body" => "done", "author_display_name" => "Alice"},
            %{"body" => "verified", "author_display_name" => "Bob"}
          ]
        }
      ]

      {:ok, review} = Reviews.create_review(files, 0, comments)
      review = Reviews.get_by_token(review.token)
      comment = hd(review.comments)

      assert comment.resolved == true
      assert length(comment.replies) == 2
      assert hd(comment.replies).body == "done"
    end

    test "create_review stores external_id on comments" do
      files = [%{"path" => "plan.md", "content" => "# Plan"}]

      comments = [
        %{
          "file" => "plan.md",
          "start_line" => 1,
          "end_line" => 1,
          "body" => "fix this",
          "external_id" => "local-c1"
        }
      ]

      {:ok, review} = Reviews.create_review(files, 1, comments, [])
      review = Repo.preload(review, :comments)

      assert hd(review.comments).external_id == "local-c1"
    end

    test "serialize_comment includes external_id" do
      {:ok, review} =
        Reviews.create_review(
          [%{"path" => "plan.md", "content" => "# Plan"}],
          1,
          [
            %{
              "file" => "plan.md",
              "start_line" => 1,
              "end_line" => 1,
              "body" => "test",
              "external_id" => "local-abc"
            }
          ],
          []
        )

      review = Repo.preload(review, :comments)
      serialized = Reviews.serialize_comment(hd(review.comments))

      assert serialized.external_id == "local-abc"
    end

    test "comments referencing non-existent files are still inserted" do
      files = [%{"path" => "a.go", "content" => "a"}]

      comments = [
        %{"file" => "nonexistent.go", "start_line" => 1, "end_line" => 1, "body" => "orphan"}
      ]

      {:ok, review} = Reviews.create_review(files, 0, comments)
      review = Reviews.get_by_token(review.token)

      assert length(review.comments) == 1
      assert hd(review.comments).file_path == "nonexistent.go"
    end
  end

  describe "get_by_token/1" do
    test "returns review with preloaded comments" do
      review = review_fixture()
      _comment = comment_fixture(review)

      found = Reviews.get_by_token(review.token)

      assert found.id == review.id
      assert Ecto.assoc_loaded?(found.comments)
      assert length(found.comments) == 1
    end

    test "returns nil for unknown token" do
      assert Reviews.get_by_token("nonexistent-token") == nil
    end

    test "preloads files in position order" do
      files = [
        %{"path" => "c.go", "content" => "c"},
        %{"path" => "a.go", "content" => "a"},
        %{"path" => "b.go", "content" => "b"}
      ]

      {:ok, review} = Reviews.create_review(files, 0, [])
      found = Reviews.get_by_token(review.token)

      assert Ecto.assoc_loaded?(found.files)
      assert Enum.map(found.files, & &1.file_path) == ["c.go", "a.go", "b.go"]
    end
  end

  describe "delete_by_delete_token/1" do
    test "deletes an existing review" do
      review = review_fixture()

      assert :ok = Reviews.delete_by_delete_token(review.delete_token)
      assert Repo.get(Review, review.id) == nil
    end

    test "returns error for unknown token" do
      assert {:error, :not_found} = Reviews.delete_by_delete_token("nonexistent")
    end
  end

  describe "create_comment/4" do
    test "creates a comment with identity" do
      review = review_fixture()
      identity = Ecto.UUID.generate()

      {:ok, comment} =
        Reviews.create_comment(
          review,
          %{"start_line" => 1, "end_line" => 2, "body" => "Nice!"},
          identity
        )

      assert comment.body == "Nice!"
      assert comment.start_line == 1
      assert comment.end_line == 2
      assert comment.author_identity == identity
      assert comment.author_display_name == nil
    end

    test "creates a comment with display_name" do
      review = review_fixture()
      identity = Ecto.UUID.generate()

      {:ok, comment} =
        Reviews.create_comment(
          review,
          %{"start_line" => 1, "end_line" => 1, "body" => "Good"},
          identity,
          "Alice"
        )

      assert comment.author_display_name == "Alice"
    end
  end

  describe "create_comment/5 with file_path" do
    test "creates comment with file_path" do
      {:ok, review} =
        Reviews.create_review(
          [%{"path" => "a.go", "content" => "a"}],
          0,
          []
        )

      {:ok, comment} =
        Reviews.create_comment(
          review,
          %{"start_line" => 1, "end_line" => 1, "body" => "hi"},
          "identity1",
          nil,
          "a.go"
        )

      assert comment.file_path == "a.go"
    end

    test "comment without file_path has nil file_path" do
      review = review_fixture()

      {:ok, comment} =
        Reviews.create_comment(
          review,
          %{"start_line" => 1, "end_line" => 1, "body" => "hi"},
          "identity1"
        )

      assert comment.file_path == nil
    end
  end

  describe "update_comment/3" do
    test "updates when identity matches" do
      review = review_fixture()
      identity = Ecto.UUID.generate()

      {:ok, comment} =
        Reviews.create_comment(
          review,
          %{"start_line" => 1, "end_line" => 1, "body" => "Original"},
          identity
        )

      {:ok, updated} = Reviews.update_comment(comment.id, "Updated body", identity)

      assert updated.body == "Updated body"
    end

    test "rejects update when identity does not match" do
      review = review_fixture()
      author_identity = Ecto.UUID.generate()

      {:ok, comment} =
        Reviews.create_comment(
          review,
          %{"start_line" => 1, "end_line" => 1, "body" => "Original"},
          author_identity
        )

      assert {:error, :unauthorized} = Reviews.update_comment(comment.id, "Hacked", "other-id")
    end
  end

  describe "delete_comment/2" do
    test "deletes when identity matches" do
      review = review_fixture()
      identity = Ecto.UUID.generate()

      {:ok, comment} =
        Reviews.create_comment(
          review,
          %{"start_line" => 1, "end_line" => 1, "body" => "To delete"},
          identity
        )

      {:ok, _deleted} = Reviews.delete_comment(comment.id, identity)

      assert Reviews.list_comments(review) == []
    end

    test "rejects deletion when identity does not match" do
      review = review_fixture()
      author_identity = Ecto.UUID.generate()

      {:ok, comment} =
        Reviews.create_comment(
          review,
          %{"start_line" => 1, "end_line" => 1, "body" => "Protected"},
          author_identity
        )

      assert {:error, :unauthorized} = Reviews.delete_comment(comment.id, "other-id")
    end
  end

  describe "list_comments/1" do
    test "returns comments ordered by start_line" do
      review = review_fixture()

      comment_fixture(review, %{"start_line" => 5, "end_line" => 5})
      comment_fixture(review, %{"start_line" => 1, "end_line" => 1})
      comment_fixture(review, %{"start_line" => 3, "end_line" => 3})

      comments = Reviews.list_comments(review)
      lines = Enum.map(comments, & &1.start_line)

      assert lines == [1, 3, 5]
    end
  end

  describe "touch_last_activity/1" do
    test "updates timestamp when stale (>1 hour)" do
      review = review_fixture()

      old_time = DateTime.utc_now() |> DateTime.add(-7200, :second) |> DateTime.truncate(:second)

      review
      |> Ecto.Changeset.change(last_activity_at: old_time)
      |> Repo.update!()

      review = Repo.get!(Review, review.id)

      Reviews.touch_last_activity(review)

      refreshed = Repo.get!(Review, review.id)
      assert DateTime.diff(refreshed.last_activity_at, old_time) > 0
    end

    test "does not update timestamp when fresh (<1 hour)" do
      review = review_fixture()

      before = Repo.get!(Review, review.id)
      Reviews.touch_last_activity(before)
      after_touch = Repo.get!(Review, review.id)

      assert DateTime.diff(after_touch.last_activity_at, before.last_activity_at) == 0
    end
  end

  describe "dashboard_stats/0" do
    test "returns zeroes when no reviews exist" do
      stats = Reviews.dashboard_stats()

      assert stats.total_reviews == 0
      assert stats.total_comments == 0
      assert stats.total_files == 0
      assert stats.reviews_this_week == 0
      assert stats.avg_comments_per_review == 0.0
      assert stats.total_storage_bytes == 0
    end

    test "counts reviews, comments, files, and storage" do
      review = review_fixture()
      comment_fixture(review)
      comment_fixture(review, %{"start_line" => 2, "end_line" => 2, "body" => "Second"})

      stats = Reviews.dashboard_stats()

      assert stats.total_reviews == 1
      assert stats.total_comments == 2
      assert stats.total_files == 1
      assert stats.reviews_this_week == 1
      assert stats.avg_comments_per_review == 2.0
      assert stats.total_storage_bytes > 0
    end

    test "counts multiple reviews correctly" do
      r1 = review_fixture()
      comment_fixture(r1)

      _r2 =
        review_fixture(%{
          files: [
            %{"path" => "a.go", "content" => "package a"},
            %{"path" => "b.go", "content" => "package b"}
          ]
        })

      stats = Reviews.dashboard_stats()

      assert stats.total_reviews == 2
      assert stats.total_comments == 1
      assert stats.total_files == 3
      assert stats.avg_comments_per_review == 0.5
    end
  end

  describe "activity_chart/1" do
    test "returns 30 days of data with zero-fill" do
      data = Reviews.activity_chart(30)

      assert length(data) == 30
      assert Enum.all?(data, fn {date, count} -> is_struct(date, Date) and is_integer(count) end)
    end

    test "counts reviews created today" do
      _review = review_fixture()

      data = Reviews.activity_chart(30)
      {_date, today_count} = List.last(data)

      assert today_count == 1
    end

    test "returns empty counts when no reviews" do
      data = Reviews.activity_chart(7)

      assert length(data) == 7
      assert Enum.all?(data, fn {_date, count} -> count == 0 end)
    end
  end

  describe "list_reviews_with_counts/0" do
    test "returns empty list when no reviews" do
      assert Reviews.list_reviews_with_counts() == []
    end

    test "returns reviews with counts and first file path" do
      review = review_fixture()
      comment_fixture(review)

      [result] = Reviews.list_reviews_with_counts()

      assert result.token == review.token
      assert result.first_file_path == "test.md"
      assert result.comment_count == 1
      assert result.file_count == 1
      assert result.id == review.id
      assert %DateTime{} = result.last_activity_at
      refute Map.has_key?(result, :delete_token)
    end

    test "sorts by last_activity_at descending" do
      r1 = review_fixture()
      r2 = review_fixture(%{files: [%{"path" => "second.md", "content" => "# Second"}]})

      old_time = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)

      r1
      |> Ecto.Changeset.change(last_activity_at: old_time)
      |> Repo.update!()

      results = Reviews.list_reviews_with_counts()

      assert length(results) == 2
      assert hd(results).token == r2.token
    end

    test "returns correct counts for multi-file review with comments" do
      {:ok, review} =
        Reviews.create_review(
          [
            %{"path" => "a.go", "content" => "package a"},
            %{"path" => "b.go", "content" => "package b"}
          ],
          0,
          [
            %{"file" => "a.go", "start_line" => 1, "end_line" => 1, "body" => "c1"},
            %{"file" => "a.go", "start_line" => 2, "end_line" => 2, "body" => "c2"},
            %{"file" => "b.go", "start_line" => 1, "end_line" => 1, "body" => "c3"}
          ]
        )

      [result] = Reviews.list_reviews_with_counts()

      assert result.token == review.token
      assert result.comment_count == 3
      assert result.file_count == 2
      assert result.first_file_path == "a.go"
    end
  end

  describe "update_display_name/2" do
    test "updates display name on all comments by the given identity" do
      review = review_fixture()
      identity = Ecto.UUID.generate()

      {:ok, _c1} =
        Reviews.create_comment(
          review,
          %{"start_line" => 1, "end_line" => 1, "body" => "First"},
          identity,
          "OldName"
        )

      {:ok, _c2} =
        Reviews.create_comment(
          review,
          %{"start_line" => 2, "end_line" => 2, "body" => "Second"},
          identity,
          "OldName"
        )

      {2, _} = Reviews.update_display_name(identity, "NewName")

      comments = Reviews.list_comments(review)
      assert Enum.all?(comments, &(&1.author_display_name == "NewName"))
    end

    test "does not affect comments by other identities" do
      review = review_fixture()
      identity_a = Ecto.UUID.generate()
      identity_b = Ecto.UUID.generate()

      {:ok, _} =
        Reviews.create_comment(
          review,
          %{"start_line" => 1, "end_line" => 1, "body" => "A's comment"},
          identity_a,
          "Alice"
        )

      {:ok, _} =
        Reviews.create_comment(
          review,
          %{"start_line" => 2, "end_line" => 2, "body" => "B's comment"},
          identity_b,
          "Bob"
        )

      Reviews.update_display_name(identity_a, "Alicia")

      comments = Reviews.list_comments(review)
      a_comment = Enum.find(comments, &(&1.author_identity == identity_a))
      b_comment = Enum.find(comments, &(&1.author_identity == identity_b))

      assert a_comment.author_display_name == "Alicia"
      assert b_comment.author_display_name == "Bob"
    end

    test "updates comments across multiple reviews" do
      review1 = review_fixture()

      review2 =
        review_fixture(%{files: [%{"path" => "other.md", "content" => "# Other"}]})

      identity = Ecto.UUID.generate()

      {:ok, _} =
        Reviews.create_comment(
          review1,
          %{"start_line" => 1, "end_line" => 1, "body" => "On review 1"},
          identity,
          "Old"
        )

      {:ok, _} =
        Reviews.create_comment(
          review2,
          %{"start_line" => 1, "end_line" => 1, "body" => "On review 2"},
          identity,
          "Old"
        )

      {2, _} = Reviews.update_display_name(identity, "New")

      assert hd(Reviews.list_comments(review1)).author_display_name == "New"
      assert hd(Reviews.list_comments(review2)).author_display_name == "New"
    end

    test "returns {0, nil} when identity has no comments" do
      assert {0, _} = Reviews.update_display_name(Ecto.UUID.generate(), "Nobody")
    end
  end

  describe "reviews_for_identity/1" do
    test "returns review id and token pairs" do
      review = review_fixture()
      identity = Ecto.UUID.generate()

      {:ok, _} =
        Reviews.create_comment(
          review,
          %{"start_line" => 1, "end_line" => 1, "body" => "hi"},
          identity
        )

      assert [{review.id, review.token}] == Reviews.reviews_for_identity(identity)
    end

    test "returns distinct reviews even with multiple comments" do
      review = review_fixture()
      identity = Ecto.UUID.generate()

      {:ok, _} =
        Reviews.create_comment(
          review,
          %{"start_line" => 1, "end_line" => 1, "body" => "one"},
          identity
        )

      {:ok, _} =
        Reviews.create_comment(
          review,
          %{"start_line" => 2, "end_line" => 2, "body" => "two"},
          identity
        )

      assert [{review.id, review.token}] == Reviews.reviews_for_identity(identity)
    end

    test "returns empty list for identity with no comments" do
      assert [] == Reviews.reviews_for_identity(Ecto.UUID.generate())
    end
  end

  describe "resolve_comment/3" do
    test "resolves an existing comment" do
      {:ok, review} = Reviews.create_review([%{"path" => "f.md", "content" => "x"}], 0, [])

      {:ok, comment} =
        Reviews.create_comment(
          review,
          %{"start_line" => 1, "end_line" => 1, "body" => "fix"},
          "id1"
        )

      assert {:ok, updated} = Reviews.resolve_comment(comment.id, true, review.id)
      assert updated.resolved == true
    end

    test "unresolves a resolved comment" do
      {:ok, review} = Reviews.create_review([%{"path" => "f.md", "content" => "x"}], 0, [])

      {:ok, comment} =
        Reviews.create_comment(
          review,
          %{"start_line" => 1, "end_line" => 1, "body" => "fix"},
          "id1"
        )

      {:ok, _} = Reviews.resolve_comment(comment.id, true, review.id)
      assert {:ok, updated} = Reviews.resolve_comment(comment.id, false, review.id)
      assert updated.resolved == false
    end

    test "rejects resolving a comment from a different review" do
      {:ok, review} = Reviews.create_review([%{"path" => "f.md", "content" => "x"}], 0, [])

      {:ok, comment} =
        Reviews.create_comment(
          review,
          %{"start_line" => 1, "end_line" => 1, "body" => "fix"},
          "id1"
        )

      other_review_id = Ecto.UUID.generate()
      assert {:error, :not_found} = Reviews.resolve_comment(comment.id, true, other_review_id)
    end

    test "rejects resolving a reply" do
      {:ok, review} = Reviews.create_review([%{"path" => "f.md", "content" => "x"}], 0, [])

      {:ok, comment} =
        Reviews.create_comment(
          review,
          %{"start_line" => 1, "end_line" => 1, "body" => "fix"},
          "id1"
        )

      {:ok, reply} = Reviews.create_reply(comment.id, %{"body" => "done"}, "id2", nil, review.id)
      assert {:error, :not_found} = Reviews.resolve_comment(reply.id, true, review.id)
    end
  end

  describe "reply CRUD" do
    setup do
      {:ok, review} = Reviews.create_review([%{"path" => "f.md", "content" => "x"}], 0, [])

      {:ok, comment} =
        Reviews.create_comment(
          review,
          %{"start_line" => 1, "end_line" => 1, "body" => "fix"},
          "id1"
        )

      %{review: review, comment: comment}
    end

    test "create_reply/5 adds a reply", %{review: review, comment: comment} do
      assert {:ok, reply} =
               Reviews.create_reply(comment.id, %{"body" => "done"}, "id2", "Bob", review.id)

      assert reply.body == "done"
      assert reply.author_identity == "id2"
      assert reply.author_display_name == "Bob"
      assert reply.parent_id == comment.id
    end

    test "create_reply/5 rejects reply to comment from different review", %{comment: comment} do
      other_review_id = Ecto.UUID.generate()

      assert {:error, :not_found} =
               Reviews.create_reply(
                 comment.id,
                 %{"body" => "done"},
                 "id2",
                 "Bob",
                 other_review_id
               )
    end

    test "create_reply/5 rejects replying to a reply", %{review: review, comment: comment} do
      {:ok, reply} =
        Reviews.create_reply(comment.id, %{"body" => "done"}, "id2", "Bob", review.id)

      assert {:error, :not_found} =
               Reviews.create_reply(reply.id, %{"body" => "nested"}, "id3", nil, review.id)
    end

    test "update_reply/3 updates own reply", %{review: review, comment: comment} do
      {:ok, reply} =
        Reviews.create_reply(comment.id, %{"body" => "done"}, "id2", "Bob", review.id)

      assert {:ok, updated} = Reviews.update_reply(reply.id, "actually not done", "id2")
      assert updated.body == "actually not done"
    end

    test "update_reply/3 rejects other's reply", %{review: review, comment: comment} do
      {:ok, reply} =
        Reviews.create_reply(comment.id, %{"body" => "done"}, "id2", "Bob", review.id)

      assert {:error, :unauthorized} = Reviews.update_reply(reply.id, "hacked", "id3")
    end

    test "delete_reply/2 deletes own reply", %{review: review, comment: comment} do
      {:ok, reply} =
        Reviews.create_reply(comment.id, %{"body" => "done"}, "id2", "Bob", review.id)

      assert {:ok, _} = Reviews.delete_reply(reply.id, "id2")
    end

    test "delete_reply/2 rejects other's reply", %{review: review, comment: comment} do
      {:ok, reply} =
        Reviews.create_reply(comment.id, %{"body" => "done"}, "id2", "Bob", review.id)

      assert {:error, :unauthorized} = Reviews.delete_reply(reply.id, "id3")
    end
  end

  describe "review_round_snapshot" do
    test "create_round_snapshot/4 stores file content for a round" do
      {:ok, review} =
        Reviews.create_review([%{"path" => "plan.md", "content" => "v1"}], 1, [], [])

      {:ok, snap} = Reviews.create_round_snapshot(review.id, 1, "plan.md", "v1 content")

      assert snap.review_id == review.id
      assert snap.round_number == 1
      assert snap.file_path == "plan.md"
      assert snap.content == "v1 content"
    end

    test "get_round_snapshots/2 returns a file_path => content map for a round" do
      {:ok, review} =
        Reviews.create_review([%{"path" => "plan.md", "content" => "v1"}], 1, [], [])

      Reviews.create_round_snapshot(review.id, 1, "plan.md", "round 1 content")
      Reviews.create_round_snapshot(review.id, 1, "other.md", "other round 1")
      Reviews.create_round_snapshot(review.id, 2, "plan.md", "round 2 content")

      result = Reviews.get_round_snapshots(review.id, 1)

      assert result == %{"plan.md" => "round 1 content", "other.md" => "other round 1"}
    end
  end

  describe "upsert_review/3" do
    test "returns {:error, :unauthorized} when delete_token is wrong" do
      {:ok, review} = Reviews.create_review([%{"path" => "f.md", "content" => "v1"}], 1, [], [])

      result =
        Reviews.upsert_review(review.token, "wrong-token", %{
          "files" => [%{"path" => "f.md", "content" => "v2"}],
          "comments" => [],
          "review_round" => 1
        })

      assert result == {:error, :unauthorized}
    end

    test "returns {:ok, :no_changes, review} when content is identical" do
      {:ok, review} = Reviews.create_review([%{"path" => "f.md", "content" => "same"}], 1, [], [])

      {:ok, :no_changes, returned} =
        Reviews.upsert_review(review.token, review.delete_token, %{
          "files" => [%{"path" => "f.md", "content" => "same"}],
          "comments" => [],
          "review_round" => 1
        })

      assert returned.id == review.id
      assert returned.review_round == review.review_round
    end

    test "increments review_round when file content changes" do
      {:ok, review} = Reviews.create_review([%{"path" => "f.md", "content" => "v1"}], 1, [], [])

      {:ok, :updated, updated} =
        Reviews.upsert_review(review.token, review.delete_token, %{
          "files" => [%{"path" => "f.md", "content" => "v2"}],
          "comments" => [],
          "review_round" => 1
        })

      assert updated.review_round == review.review_round + 1
    end

    test "preserves initial round content after upsert (no data deleted)" do
      {:ok, review} = Reviews.create_review([%{"path" => "f.md", "content" => "old"}], 1, [], [])
      initial_round = review.review_round

      Reviews.upsert_review(review.token, review.delete_token, %{
        "files" => [%{"path" => "f.md", "content" => "new"}],
        "comments" => [],
        "review_round" => 1
      })

      snaps = Reviews.get_round_snapshots(review.id, initial_round)
      assert snaps["f.md"] == "old"
    end

    test "get_by_token returns latest round file content after upsert" do
      {:ok, review} = Reviews.create_review([%{"path" => "f.md", "content" => "v1"}], 1, [], [])

      Reviews.upsert_review(review.token, review.delete_token, %{
        "files" => [%{"path" => "f.md", "content" => "v2 updated"}],
        "comments" => [],
        "review_round" => 1
      })

      updated = Reviews.get_by_token(review.token)
      assert hd(updated.files).content == "v2 updated"
    end

    test "replaces comments and preserves external_id and resolved state" do
      {:ok, review} = Reviews.create_review([%{"path" => "f.md", "content" => "v1"}], 1, [], [])

      Reviews.upsert_review(review.token, review.delete_token, %{
        "files" => [%{"path" => "f.md", "content" => "v2"}],
        "comments" => [
          %{
            "file" => "f.md",
            "start_line" => 1,
            "end_line" => 1,
            "body" => "addressed",
            "external_id" => "local-c1",
            "resolved" => true
          }
        ],
        "review_round" => 1
      })

      updated = Reviews.get_by_token(review.token)
      [comment] = updated.comments
      assert comment.external_id == "local-c1"
      assert comment.resolved == true
    end
  end

  describe "delete_review/1" do
    test "deletes a review by id" do
      review = review_fixture()

      assert :ok = Reviews.delete_review(review.id)
      assert Repo.get(Review, review.id) == nil
    end

    test "returns error for unknown id" do
      assert {:error, :not_found} = Reviews.delete_review(Ecto.UUID.generate())
    end
  end
end
