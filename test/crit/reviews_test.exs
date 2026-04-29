defmodule Crit.ReviewsTest do
  use Crit.DataCase, async: true

  alias Crit.{Repo, Review, Reviews}
  alias Crit.Accounts.Scope

  import Crit.ReviewsFixtures

  defp insert_user!(attrs \\ %{}) do
    base = %{
      provider: "test",
      provider_uid: "uid-#{System.unique_integer([:positive])}",
      email: "u-#{System.unique_integer([:positive])}@example.com",
      name: "Alex"
    }

    %Crit.User{}
    |> Crit.User.changeset(Map.merge(base, attrs))
    |> Repo.insert!()
  end

  defp anon_scope(identity \\ nil, display_name \\ nil) do
    Scope.for_visitor(identity || "anon-#{System.unique_integer([:positive])}", display_name)
  end

  defp default_files, do: [%{"path" => "test.md", "content" => "# Hello"}]

  describe "create_review/6" do
    test "anonymous → user_id nil" do
      scope = anon_scope()
      assert {:ok, review} = Reviews.create_review(scope, default_files(), 0, [])
      assert review.user_id == nil
    end

    test "authenticated → user_id = scope.user.id" do
      user = insert_user!()
      scope = Scope.for_user(user)
      assert {:ok, review} = Reviews.create_review(scope, default_files(), 0, [])
      assert review.user_id == user.id
    end

    test "creates a review with files" do
      scope = anon_scope()
      files = [%{"path" => "test.md", "content" => "# Hello"}]
      {:ok, review} = Reviews.create_review(scope, files, 0, [])

      review = Reviews.get_by_token(review.token)
      assert review.review_round == 0
      assert review.token != nil
      assert review.delete_token != nil
      assert length(review.files) == 1
      assert hd(review.files).file_path == "test.md"
      assert hd(review.files).content == "# Hello"
    end

    test "creates a review with seed comments" do
      scope = anon_scope()
      files = [%{"path" => "test.md", "content" => "# Hello"}]

      comments = [
        %{"file" => "test.md", "start_line" => 1, "end_line" => 2, "body" => "First comment"},
        %{"file" => "test.md", "start_line" => 3, "end_line" => 3, "body" => "Second comment"}
      ]

      {:ok, review} = Reviews.create_review(scope, files, 1, comments)

      loaded = Reviews.list_comments(review)
      assert length(loaded) == 2
      assert Enum.all?(loaded, &(&1.author_identity == "imported"))
    end

    test "returns error for file with invalid content (missing content)" do
      scope = anon_scope()
      files = [%{"path" => "a.go"}]
      assert {:error, %Ecto.Changeset{}} = Reviews.create_review(scope, files, 0, [])
    end

    test "returns error when total size exceeds 10 MB" do
      scope = anon_scope()
      big_content = String.duplicate("x", 5_500_000)

      files = [
        %{"path" => "a.go", "content" => big_content},
        %{"path" => "b.go", "content" => big_content}
      ]

      assert {:error, :total_size_exceeded} = Reviews.create_review(scope, files, 0, [])
    end

    test "creates review with multiple files and per-file comments" do
      scope = anon_scope()

      files = [
        %{"path" => "src/main.go", "content" => "package main"},
        %{"path" => "src/util.go", "content" => "package util"}
      ]

      comments = [
        %{"file" => "src/main.go", "start_line" => 1, "end_line" => 1, "body" => "rename this"},
        %{"file" => "src/util.go", "start_line" => 1, "end_line" => 1, "body" => "nice"}
      ]

      assert {:ok, review} = Reviews.create_review(scope, files, 1, comments)
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
      scope = anon_scope()

      files = [
        %{"path" => "z.go", "content" => "z"},
        %{"path" => "a.go", "content" => "a"}
      ]

      {:ok, review} = Reviews.create_review(scope, files, 0, [])
      review = Reviews.get_by_token(review.token)

      assert Enum.map(review.files, & &1.file_path) == ["z.go", "a.go"]
    end

    test "create_review imports comments with resolved and replies" do
      scope = anon_scope()
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

      {:ok, review} = Reviews.create_review(scope, files, 0, comments)
      review = Reviews.get_by_token(review.token)
      comment = hd(review.comments)

      assert comment.resolved == true
      assert length(comment.replies) == 2
      assert hd(comment.replies).body == "done"
    end

    test "create_review stores external_id on comments" do
      scope = anon_scope()
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

      {:ok, review} = Reviews.create_review(scope, files, 1, comments, [])
      review = Repo.preload(review, :comments)

      assert hd(review.comments).external_id == "local-c1"
    end

    test "serialize_comment includes external_id" do
      scope = anon_scope()

      {:ok, review} =
        Reviews.create_review(
          scope,
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
      scope = anon_scope()
      files = [%{"path" => "a.go", "content" => "a"}]

      comments = [
        %{"file" => "nonexistent.go", "start_line" => 1, "end_line" => 1, "body" => "orphan"}
      ]

      {:ok, review} = Reviews.create_review(scope, files, 0, comments)
      review = Reviews.get_by_token(review.token)

      assert length(review.comments) == 1
      assert hd(review.comments).file_path == "nonexistent.go"
    end

    test "cli_args still threads through opts" do
      scope = anon_scope()

      assert {:ok, review} =
               Reviews.create_review(scope, default_files(), 1, [], [], cli_args: ["status"])

      assert review.cli_args == ["status"]
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
      scope = anon_scope()

      files = [
        %{"path" => "c.go", "content" => "c"},
        %{"path" => "a.go", "content" => "a"},
        %{"path" => "b.go", "content" => "b"}
      ]

      {:ok, review} = Reviews.create_review(scope, files, 0, [])
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

  describe "create_comment/4 (scope)" do
    test "anonymous → user_id nil, author_identity = scope.identity" do
      review = review_fixture()
      scope = Scope.for_visitor("ident-anon", "Pat")

      assert {:ok, comment} =
               Reviews.create_comment(scope, review, %{
                 "start_line" => 1,
                 "end_line" => 2,
                 "body" => "Nice!"
               })

      assert comment.body == "Nice!"
      assert comment.user_id == nil
      assert comment.author_identity == "ident-anon"
      assert comment.author_display_name == "Pat"
    end

    test "authenticated → user_id = scope.user.id, author_identity nil" do
      review = review_fixture()
      user = insert_user!()
      scope = Scope.for_user(user)

      assert {:ok, comment} =
               Reviews.create_comment(scope, review, %{
                 "start_line" => 1,
                 "end_line" => 1,
                 "body" => "hi"
               })

      assert comment.user_id == user.id
      assert comment.author_identity == nil
    end

    test "stores file_path when provided in opts" do
      scope = anon_scope("identity1")

      {:ok, review} =
        Reviews.create_review(scope, [%{"path" => "a.go", "content" => "a"}], 0, [])

      {:ok, comment} =
        Reviews.create_comment(
          scope,
          review,
          %{"start_line" => 1, "end_line" => 1, "body" => "hi"},
          file_path: "a.go"
        )

      assert comment.file_path == "a.go"
    end

    test "comment without file_path opt has nil file_path" do
      review = review_fixture()
      scope = anon_scope("identity1")

      {:ok, comment} =
        Reviews.create_comment(scope, review, %{
          "start_line" => 1,
          "end_line" => 1,
          "body" => "hi"
        })

      assert comment.file_path == nil
    end
  end

  describe "update_comment/3 (scope) — owner check" do
    test "anonymous author can update via matching identity" do
      review = review_fixture()
      scope = Scope.for_visitor("ident-anon", "Pat")

      {:ok, c} =
        Reviews.create_comment(scope, review, %{
          "start_line" => 1,
          "end_line" => 1,
          "body" => "Original"
        })

      assert {:ok, updated} = Reviews.update_comment(scope, c.id, "Updated body")
      assert updated.body == "Updated body"
    end

    test "different identity cannot update anonymous comment" do
      review = review_fixture()
      a = Scope.for_visitor("a", "A")
      b = Scope.for_visitor("b", "B")

      {:ok, c} =
        Reviews.create_comment(a, review, %{
          "start_line" => 1,
          "end_line" => 1,
          "body" => "Original"
        })

      assert {:error, :unauthorized} = Reviews.update_comment(b, c.id, "Hacked")
    end

    test "authenticated author can update own comment" do
      review = review_fixture()
      user = insert_user!()
      scope = Scope.for_user(user)

      {:ok, c} =
        Reviews.create_comment(scope, review, %{
          "start_line" => 1,
          "end_line" => 1,
          "body" => "Original"
        })

      assert {:ok, updated} = Reviews.update_comment(scope, c.id, "Updated body")
      assert updated.body == "Updated body"
    end
  end

  describe "delete_comment/2 (scope)" do
    test "deletes when identity matches" do
      review = review_fixture()
      scope = Scope.for_visitor("ident-anon")

      {:ok, comment} =
        Reviews.create_comment(scope, review, %{
          "start_line" => 1,
          "end_line" => 1,
          "body" => "To delete"
        })

      {:ok, _deleted} = Reviews.delete_comment(scope, comment.id)
      assert Reviews.list_comments(review) == []
    end

    test "rejects deletion when identity does not match" do
      review = review_fixture()
      a = Scope.for_visitor("ident-a")
      b = Scope.for_visitor("ident-b")

      {:ok, comment} =
        Reviews.create_comment(a, review, %{
          "start_line" => 1,
          "end_line" => 1,
          "body" => "Protected"
        })

      assert {:error, :unauthorized} = Reviews.delete_comment(b, comment.id)
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
      scope = anon_scope()

      {:ok, review} =
        Reviews.create_review(
          scope,
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

  describe "list_user_reviews_with_counts/1 (scope)" do
    test "returns empty list for anonymous scope" do
      _ = review_fixture()
      assert Reviews.list_user_reviews_with_counts(anon_scope()) == []
    end

    test "returns only the user's reviews for authenticated scope" do
      owner = insert_user!()
      other = insert_user!()
      _user_review = review_fixture(%{user_id: owner.id})
      _other_review = review_fixture(%{user_id: other.id})
      _anon_review = review_fixture()

      [result] = Reviews.list_user_reviews_with_counts(Scope.for_user(owner))
      assert result.user_id == owner.id
    end
  end

  describe "update_display_name/2 (scope)" do
    test "updates display name on all comments by the scope's identity" do
      review = review_fixture()
      identity = Ecto.UUID.generate()
      scope = Scope.for_visitor(identity, "OldName")

      {:ok, _c1} =
        Reviews.create_comment(scope, review, %{
          "start_line" => 1,
          "end_line" => 1,
          "body" => "First"
        })

      {:ok, _c2} =
        Reviews.create_comment(scope, review, %{
          "start_line" => 2,
          "end_line" => 2,
          "body" => "Second"
        })

      {2, _} = Reviews.update_display_name(scope, "NewName")

      comments = Reviews.list_comments(review)
      assert Enum.all?(comments, &(&1.author_display_name == "NewName"))
    end

    test "does not affect comments by other identities" do
      review = review_fixture()
      scope_a = Scope.for_visitor(Ecto.UUID.generate(), "Alice")
      scope_b = Scope.for_visitor(Ecto.UUID.generate(), "Bob")

      {:ok, _} =
        Reviews.create_comment(scope_a, review, %{
          "start_line" => 1,
          "end_line" => 1,
          "body" => "A"
        })

      {:ok, _} =
        Reviews.create_comment(scope_b, review, %{
          "start_line" => 2,
          "end_line" => 2,
          "body" => "B"
        })

      Reviews.update_display_name(scope_a, "Alicia")

      comments = Reviews.list_comments(review)
      a = Enum.find(comments, &(&1.author_identity == scope_a.identity))
      b = Enum.find(comments, &(&1.author_identity == scope_b.identity))

      assert a.author_display_name == "Alicia"
      assert b.author_display_name == "Bob"
    end

    test "updates comments across multiple reviews" do
      review1 = review_fixture()
      review2 = review_fixture(%{files: [%{"path" => "other.md", "content" => "# Other"}]})
      scope = Scope.for_visitor(Ecto.UUID.generate(), "Old")

      {:ok, _} =
        Reviews.create_comment(scope, review1, %{
          "start_line" => 1,
          "end_line" => 1,
          "body" => "On review 1"
        })

      {:ok, _} =
        Reviews.create_comment(scope, review2, %{
          "start_line" => 1,
          "end_line" => 1,
          "body" => "On review 2"
        })

      {2, _} = Reviews.update_display_name(scope, "New")

      assert hd(Reviews.list_comments(review1)).author_display_name == "New"
      assert hd(Reviews.list_comments(review2)).author_display_name == "New"
    end

    test "returns {0, nil} when identity has no comments" do
      assert {0, _} = Reviews.update_display_name(anon_scope(), "Nobody")
    end

    test "no-ops for authenticated scopes" do
      user = insert_user!()
      scope = Scope.for_user(user)
      assert :ok = Reviews.update_display_name(scope, "Anything")
    end
  end

  describe "reviews_for_identity/1 (scope)" do
    test "returns review id and token pairs for the scope's identity" do
      review = review_fixture()
      scope = anon_scope()

      {:ok, _} =
        Reviews.create_comment(scope, review, %{
          "start_line" => 1,
          "end_line" => 1,
          "body" => "hi"
        })

      assert [{review.id, review.token}] == Reviews.reviews_for_identity(scope)
    end

    test "returns distinct reviews even with multiple comments" do
      review = review_fixture()
      scope = anon_scope()

      {:ok, _} =
        Reviews.create_comment(scope, review, %{
          "start_line" => 1,
          "end_line" => 1,
          "body" => "one"
        })

      {:ok, _} =
        Reviews.create_comment(scope, review, %{
          "start_line" => 2,
          "end_line" => 2,
          "body" => "two"
        })

      assert [{review.id, review.token}] == Reviews.reviews_for_identity(scope)
    end

    test "returns empty list for identity with no comments" do
      assert [] == Reviews.reviews_for_identity(anon_scope())
    end

    test "returns empty list for authenticated scope" do
      assert [] == Reviews.reviews_for_identity(Scope.for_user(insert_user!()))
    end
  end

  describe "resolve_comment/4 (scope) — gating" do
    setup do
      owner = insert_user!()
      owner_scope = Scope.for_user(owner)
      anon_author_scope = Scope.for_visitor("anon-1", "Anon")
      {:ok, review} = Reviews.create_review(owner_scope, default_files(), 0, [])

      {:ok, anon_comment} =
        Reviews.create_comment(anon_author_scope, review, %{
          "start_line" => 1,
          "end_line" => 1,
          "body" => "anon"
        })

      {:ok, auth_comment} =
        Reviews.create_comment(owner_scope, review, %{
          "start_line" => 2,
          "end_line" => 2,
          "body" => "auth"
        })

      %{owner: owner, review: review, anon_comment: anon_comment, auth_comment: auth_comment}
    end

    test "review owner can resolve any comment", ctx do
      scope = Scope.for_user(ctx.owner)

      assert {:ok, _} =
               Reviews.resolve_comment(scope, ctx.anon_comment.id, true, ctx.review.id)

      assert {:ok, _} =
               Reviews.resolve_comment(scope, ctx.auth_comment.id, true, ctx.review.id)
    end

    test "anonymous author can resolve own anonymous comment", ctx do
      scope = Scope.for_visitor("anon-1")

      assert {:ok, _} =
               Reviews.resolve_comment(scope, ctx.anon_comment.id, true, ctx.review.id)
    end

    test "different anonymous viewer cannot resolve", ctx do
      scope = Scope.for_visitor("someone-else")

      assert {:error, :unauthorized} =
               Reviews.resolve_comment(scope, ctx.anon_comment.id, true, ctx.review.id)
    end

    test "different authenticated user cannot resolve other people's comments", ctx do
      intruder = insert_user!()
      scope = Scope.for_user(intruder)

      assert {:error, :unauthorized} =
               Reviews.resolve_comment(scope, ctx.anon_comment.id, true, ctx.review.id)
    end

    test "rejects resolving a comment from a different review", ctx do
      scope = Scope.for_user(ctx.owner)
      other_review_id = Ecto.UUID.generate()

      assert {:error, :not_found} =
               Reviews.resolve_comment(scope, ctx.anon_comment.id, true, other_review_id)
    end

    test "rejects resolving a reply", %{review: review, owner: owner} do
      scope = Scope.for_user(owner)
      anon_scope = Scope.for_visitor("reply-anon")

      {:ok, parent} =
        Reviews.create_comment(scope, review, %{
          "start_line" => 5,
          "end_line" => 5,
          "body" => "parent"
        })

      {:ok, reply} =
        Reviews.create_reply(anon_scope, parent.id, %{"body" => "done"}, review.id)

      assert {:error, :not_found} = Reviews.resolve_comment(scope, reply.id, true, review.id)
    end

    test "unresolves a resolved comment", ctx do
      scope = Scope.for_user(ctx.owner)
      {:ok, _} = Reviews.resolve_comment(scope, ctx.anon_comment.id, true, ctx.review.id)

      assert {:ok, updated} =
               Reviews.resolve_comment(scope, ctx.anon_comment.id, false, ctx.review.id)

      assert updated.resolved == false
    end
  end

  describe "reply CRUD (scope)" do
    setup do
      scope = anon_scope("anon-1")
      {:ok, review} = Reviews.create_review(scope, default_files(), 0, [])

      {:ok, comment} =
        Reviews.create_comment(scope, review, %{
          "start_line" => 1,
          "end_line" => 1,
          "body" => "fix"
        })

      %{review: review, comment: comment, author_scope: scope}
    end

    test "create_reply/4 adds a reply", %{review: review, comment: comment} do
      scope = Scope.for_visitor("id2", "Bob")

      assert {:ok, reply} =
               Reviews.create_reply(scope, comment.id, %{"body" => "done"}, review.id)

      assert reply.body == "done"
      assert reply.author_identity == "id2"
      assert reply.author_display_name == "Bob"
      assert reply.parent_id == comment.id
    end

    test "create_reply/4 rejects reply to comment from different review", %{comment: comment} do
      scope = Scope.for_visitor("id2", "Bob")
      other_review_id = Ecto.UUID.generate()

      assert {:error, :not_found} =
               Reviews.create_reply(scope, comment.id, %{"body" => "done"}, other_review_id)
    end

    test "create_reply/4 rejects replying to a reply", %{review: review, comment: comment} do
      scope = Scope.for_visitor("id2", "Bob")

      {:ok, reply} =
        Reviews.create_reply(scope, comment.id, %{"body" => "done"}, review.id)

      other = Scope.for_visitor("id3")

      assert {:error, :not_found} =
               Reviews.create_reply(other, reply.id, %{"body" => "nested"}, review.id)
    end

    test "update_reply/3 updates own reply", %{review: review, comment: comment} do
      scope = Scope.for_visitor("id2", "Bob")
      {:ok, reply} = Reviews.create_reply(scope, comment.id, %{"body" => "done"}, review.id)

      assert {:ok, updated} = Reviews.update_reply(scope, reply.id, "actually not done")
      assert updated.body == "actually not done"
    end

    test "update_reply/3 rejects other's reply", %{review: review, comment: comment} do
      scope = Scope.for_visitor("id2", "Bob")
      {:ok, reply} = Reviews.create_reply(scope, comment.id, %{"body" => "done"}, review.id)

      intruder = Scope.for_visitor("id3")
      assert {:error, :unauthorized} = Reviews.update_reply(intruder, reply.id, "hacked")
    end

    test "delete_reply/2 deletes own reply", %{review: review, comment: comment} do
      scope = Scope.for_visitor("id2", "Bob")
      {:ok, reply} = Reviews.create_reply(scope, comment.id, %{"body" => "done"}, review.id)

      assert {:ok, _} = Reviews.delete_reply(scope, reply.id)
    end

    test "delete_reply/2 rejects other's reply", %{review: review, comment: comment} do
      scope = Scope.for_visitor("id2", "Bob")
      {:ok, reply} = Reviews.create_reply(scope, comment.id, %{"body" => "done"}, review.id)

      intruder = Scope.for_visitor("id3")
      assert {:error, :unauthorized} = Reviews.delete_reply(intruder, reply.id)
    end
  end

  describe "serialize_reply/1" do
    test "returns expected shape" do
      scope = anon_scope("id1")
      {:ok, review} = Reviews.create_review(scope, default_files(), 0, [])

      {:ok, comment} =
        Reviews.create_comment(scope, review, %{
          "start_line" => 1,
          "end_line" => 1,
          "body" => "parent"
        })

      reply_scope = Scope.for_visitor("id2", "Bob")

      {:ok, reply} =
        Reviews.create_reply(reply_scope, comment.id, %{"body" => "test reply"}, review.id)

      serialized = Reviews.serialize_reply(reply)

      assert serialized.id == reply.id
      assert serialized.body == "test reply"
      assert serialized.author_identity == "id2"
      assert serialized.author_display_name == "Bob"
      assert Map.has_key?(serialized, :created_at)

      expected_keys =
        MapSet.new([
          :id,
          :body,
          :author_identity,
          :author_display_name,
          :user_id,
          :created_at
        ])

      assert MapSet.new(Map.keys(serialized)) == expected_keys
    end

    test "formats inserted_at as ISO8601" do
      scope = anon_scope("id1")
      {:ok, review} = Reviews.create_review(scope, default_files(), 0, [])

      {:ok, comment} =
        Reviews.create_comment(scope, review, %{
          "start_line" => 1,
          "end_line" => 1,
          "body" => "parent"
        })

      reply_scope = Scope.for_visitor("id2")

      {:ok, reply} =
        Reviews.create_reply(reply_scope, comment.id, %{"body" => "reply"}, review.id)

      serialized = Reviews.serialize_reply(reply)
      assert {:ok, _dt, _offset} = DateTime.from_iso8601(serialized.created_at)
    end
  end

  describe "review_round_snapshot" do
    test "create_round_snapshot/4 stores file content for a round" do
      scope = anon_scope()

      {:ok, review} =
        Reviews.create_review(scope, [%{"path" => "plan.md", "content" => "v1"}], 1, [], [])

      {:ok, snap} = Reviews.create_round_snapshot(review.id, 1, "plan.md", "v1 content")

      assert snap.review_id == review.id
      assert snap.round_number == 1
      assert snap.file_path == "plan.md"
      assert snap.content == "v1 content"
    end

    test "get_round_snapshots/2 returns a file_path => content map for a round" do
      scope = anon_scope()

      {:ok, review} =
        Reviews.create_review(scope, [%{"path" => "plan.md", "content" => "v1"}], 1, [], [])

      Reviews.create_round_snapshot(review.id, 1, "plan.md", "round 1 content")
      Reviews.create_round_snapshot(review.id, 1, "other.md", "other round 1")
      Reviews.create_round_snapshot(review.id, 2, "plan.md", "round 2 content")

      result = Reviews.get_round_snapshots(review.id, 1)

      assert result == %{"plan.md" => "round 1 content", "other.md" => "other round 1"}
    end
  end

  describe "upsert_review/4 (scope)" do
    test "rejects upsert with oversize cli_args" do
      scope = anon_scope()

      {:ok, review} =
        Reviews.create_review(scope, [%{"path" => "f.md", "content" => "v1"}], 1, [], [])

      oversize = for i <- 1..65, do: "arg-#{i}"

      assert {:error, %Ecto.Changeset{} = cs} =
               Reviews.upsert_review(scope, review.token, review.delete_token, %{
                 "files" => [%{"path" => "f.md", "content" => "v2"}],
                 "comments" => [],
                 "cli_args" => oversize
               })

      assert {"may not contain more than 64 entries", _} = cs.errors[:cli_args]
    end

    test "rejects upsert with cli_args containing oversize entry (no content change)" do
      scope = anon_scope()

      {:ok, review} =
        Reviews.create_review(scope, [%{"path" => "f.md", "content" => "same"}], 1, [], [])

      huge = String.duplicate("x", 257)

      assert {:error, %Ecto.Changeset{} = cs} =
               Reviews.upsert_review(scope, review.token, review.delete_token, %{
                 "files" => [%{"path" => "f.md", "content" => "same"}],
                 "comments" => [],
                 "cli_args" => [huge]
               })

      assert {"each entry may not exceed 256 bytes", _} = cs.errors[:cli_args]
    end

    test "returns {:error, :unauthorized} when delete_token is wrong" do
      scope = anon_scope()

      {:ok, review} =
        Reviews.create_review(scope, [%{"path" => "f.md", "content" => "v1"}], 1, [], [])

      result =
        Reviews.upsert_review(scope, review.token, "wrong-token", %{
          "files" => [%{"path" => "f.md", "content" => "v2"}],
          "comments" => [],
          "review_round" => 1
        })

      assert result == {:error, :unauthorized}
    end

    test "returns {:ok, :no_changes, review} when content is identical" do
      scope = anon_scope()

      {:ok, review} =
        Reviews.create_review(scope, [%{"path" => "f.md", "content" => "same"}], 1, [], [])

      {:ok, :no_changes, returned} =
        Reviews.upsert_review(scope, review.token, review.delete_token, %{
          "files" => [%{"path" => "f.md", "content" => "same"}],
          "comments" => [],
          "review_round" => 1
        })

      assert returned.id == review.id
      assert returned.review_round == review.review_round
    end

    test "increments review_round when file content changes" do
      scope = anon_scope()

      {:ok, review} =
        Reviews.create_review(scope, [%{"path" => "f.md", "content" => "v1"}], 1, [], [])

      {:ok, :updated, updated} =
        Reviews.upsert_review(scope, review.token, review.delete_token, %{
          "files" => [%{"path" => "f.md", "content" => "v2"}],
          "comments" => [],
          "review_round" => 1
        })

      assert updated.review_round == review.review_round + 1
    end

    test "preserves initial round content after upsert (no data deleted)" do
      scope = anon_scope()

      {:ok, review} =
        Reviews.create_review(scope, [%{"path" => "f.md", "content" => "old"}], 1, [], [])

      initial_round = review.review_round

      Reviews.upsert_review(scope, review.token, review.delete_token, %{
        "files" => [%{"path" => "f.md", "content" => "new"}],
        "comments" => [],
        "review_round" => 1
      })

      snaps = Reviews.get_round_snapshots(review.id, initial_round)
      assert snaps["f.md"] == "old"
    end

    test "get_by_token returns latest round file content after upsert" do
      scope = anon_scope()

      {:ok, review} =
        Reviews.create_review(scope, [%{"path" => "f.md", "content" => "v1"}], 1, [], [])

      Reviews.upsert_review(scope, review.token, review.delete_token, %{
        "files" => [%{"path" => "f.md", "content" => "v2 updated"}],
        "comments" => [],
        "review_round" => 1
      })

      updated = Reviews.get_by_token(review.token)
      assert hd(updated.files).content == "v2 updated"
    end

    test "replaces comments and preserves external_id and resolved state" do
      scope = anon_scope()

      {:ok, review} =
        Reviews.create_review(scope, [%{"path" => "f.md", "content" => "v1"}], 1, [], [])

      Reviews.upsert_review(scope, review.token, review.delete_token, %{
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

    test "preserves author_display_name from payload" do
      scope = anon_scope()

      {:ok, review} =
        Reviews.create_review(scope, [%{"path" => "f.md", "content" => "v1"}], 1, [], [])

      Reviews.upsert_review(scope, review.token, review.delete_token, %{
        "files" => [%{"path" => "f.md", "content" => "v2"}],
        "comments" => [
          %{
            "file" => "f.md",
            "start_line" => 1,
            "end_line" => 1,
            "body" => "nice work",
            "author_display_name" => "Tomasz"
          }
        ],
        "review_round" => 1
      })

      updated = Reviews.get_by_token(review.token)
      [comment] = updated.comments
      assert comment.author_display_name == "Tomasz"
    end

    test "author_display_name is nil when not provided (not defaulted to 'crit')" do
      scope = anon_scope()

      {:ok, review} =
        Reviews.create_review(scope, [%{"path" => "f.md", "content" => "v1"}], 1, [], [])

      Reviews.upsert_review(scope, review.token, review.delete_token, %{
        "files" => [%{"path" => "f.md", "content" => "v2"}],
        "comments" => [
          %{
            "file" => "f.md",
            "start_line" => 1,
            "end_line" => 1,
            "body" => "comment without author"
          }
        ],
        "review_round" => 1
      })

      updated = Reviews.get_by_token(review.token)
      [comment] = updated.comments
      assert is_nil(comment.author_display_name)
    end

    test "falls back to author field when author_display_name is not provided" do
      scope = anon_scope()

      {:ok, review} =
        Reviews.create_review(scope, [%{"path" => "f.md", "content" => "v1"}], 1, [], [])

      Reviews.upsert_review(scope, review.token, review.delete_token, %{
        "files" => [%{"path" => "f.md", "content" => "v2"}],
        "comments" => [
          %{
            "file" => "f.md",
            "start_line" => 1,
            "end_line" => 1,
            "body" => "from export",
            "author" => "ExportUser"
          }
        ],
        "review_round" => 1
      })

      updated = Reviews.get_by_token(review.token)
      [comment] = updated.comments
      assert comment.author_display_name == "ExportUser"
    end

    test "preserves author_display_name on replies during upsert" do
      scope = anon_scope()

      {:ok, review} =
        Reviews.create_review(scope, [%{"path" => "f.md", "content" => "v1"}], 1, [], [])

      Reviews.upsert_review(scope, review.token, review.delete_token, %{
        "files" => [%{"path" => "f.md", "content" => "v2"}],
        "comments" => [
          %{
            "file" => "f.md",
            "start_line" => 1,
            "end_line" => 1,
            "body" => "original comment",
            "author_display_name" => "Tomasz",
            "replies" => [
              %{"body" => "reply text", "author_display_name" => "Reviewer"}
            ]
          }
        ],
        "review_round" => 1
      })

      updated = Reviews.get_by_token(review.token)
      [comment] = updated.comments
      assert comment.author_display_name == "Tomasz"
      [reply] = comment.replies
      assert reply.author_display_name == "Reviewer"
    end
  end

  describe "delete_review/2 (scope)" do
    test "anonymous → :unauthorized" do
      review = review_fixture()
      assert {:error, :unauthorized} = Reviews.delete_review(anon_scope(), review.id)
    end

    test "authenticated owner → ok" do
      user = insert_user!()
      scope = Scope.for_user(user)
      {:ok, review} = Reviews.create_review(scope, default_files(), 0, [])
      assert :ok = Reviews.delete_review(scope, review.id)
      assert Repo.get(Review, review.id) == nil
    end

    test "different authenticated user → :unauthorized" do
      owner = insert_user!()
      intruder = insert_user!()
      {:ok, review} = Reviews.create_review(Scope.for_user(owner), default_files(), 0, [])
      assert {:error, :unauthorized} = Reviews.delete_review(Scope.for_user(intruder), review.id)
    end

    test "owner of an unowned (legacy) review → ok" do
      anon_owner = anon_scope()
      {:ok, review} = Reviews.create_review(anon_owner, default_files(), 0, [])
      auth_user = insert_user!()
      # Legacy review (user_id == nil) — any authed user can delete.
      assert :ok = Reviews.delete_review(Scope.for_user(auth_user), review.id)
    end

    test "returns error for unknown id" do
      user = insert_user!()

      assert {:error, :not_found} =
               Reviews.delete_review(Scope.for_user(user), Ecto.UUID.generate())
    end

    test "with owner_id deletes when owner matches" do
      {:ok, user} =
        Crit.Accounts.find_or_create_from_oauth("github", %{
          "sub" => "owner-#{System.unique_integer([:positive])}",
          "name" => "Owner",
          "email" => "owner@example.test"
        })

      review = review_fixture(%{user_id: user.id})

      assert :ok = Reviews.delete_review(review.id, owner_id: user.id)
      assert Repo.get(Review, review.id) == nil
    end

    test "with owner_id refuses when owner does not match" do
      {:ok, owner} =
        Crit.Accounts.find_or_create_from_oauth("github", %{
          "sub" => "owner-#{System.unique_integer([:positive])}",
          "name" => "Owner2",
          "email" => "owner2@example.test"
        })

      {:ok, other} =
        Crit.Accounts.find_or_create_from_oauth("github", %{
          "sub" => "other-#{System.unique_integer([:positive])}",
          "name" => "Other",
          "email" => "other@example.test"
        })

      review = review_fixture(%{user_id: owner.id})

      assert {:error, :unauthorized} = Reviews.delete_review(review.id, owner_id: other.id)
      assert Repo.get(Review, review.id)
    end

    test "with owner_id refuses to delete an anonymous (user_id == nil) review" do
      {:ok, other} =
        Crit.Accounts.find_or_create_from_oauth("github", %{
          "sub" => "other-#{System.unique_integer([:positive])}",
          "name" => "Other2",
          "email" => "other2@example.test"
        })

      review = review_fixture()
      assert is_nil(review.user_id)

      assert {:error, :unauthorized} = Reviews.delete_review(review.id, owner_id: other.id)
      assert Repo.get(Review, review.id)
    end
  end
end
