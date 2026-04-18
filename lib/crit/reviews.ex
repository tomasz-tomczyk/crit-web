defmodule Crit.Reviews do
  @moduledoc "Context for reviews and comments."

  import Ecto.Query
  alias Crit.{Repo, Review, Comment, ReviewRoundSnapshot, Statistics}

  @max_total_size 10_485_760

  @doc "Fetch a review by its token, preloading comments sorted by start_line."
  def get_by_token(token) do
    review =
      Repo.one(
        from r in Review,
          where: r.token == ^token,
          preload: [
            comments:
              ^from(c in Comment,
                where: is_nil(c.parent_id),
                order_by: [asc: c.start_line, asc: c.end_line],
                preload: [:replies]
              )
          ]
      )

    case review do
      nil -> nil
      r -> Map.put(r, :files, get_current_files(r))
    end
  end

  defp get_current_files(review) do
    Repo.all(
      from s in ReviewRoundSnapshot,
        where: s.review_id == ^review.id and s.round_number == ^review.review_round,
        order_by: [asc: s.position]
    )
  end

  @doc """
  Touch last_activity_at if it is older than 1 hour, to avoid a DB write on every page load.
  """
  def touch_last_activity(%Review{id: id, last_activity_at: last_at}) do
    one_hour_ago = DateTime.add(DateTime.utc_now(), -3600, :second) |> DateTime.truncate(:second)

    if DateTime.before?(last_at, one_hour_ago) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      Repo.update_all(from(r in Review, where: r.id == ^id), set: [last_activity_at: now])
    end

    :ok
  end

  @doc "List all comments for a review, ordered by start_line."
  def list_comments(%Review{id: id}), do: list_comments(id)

  def list_comments(review_id) when is_binary(review_id) do
    Repo.all(
      from c in Comment,
        where: c.review_id == ^review_id and is_nil(c.parent_id),
        order_by: [asc: c.start_line, asc: c.end_line],
        preload: [:replies]
    )
  end

  @doc "Create a comment for a review with a given identity."
  def create_comment(
        %Review{id: review_id},
        attrs,
        identity,
        display_name \\ nil,
        file_path \\ nil
      ) do
    %Comment{}
    |> Comment.create_changeset(attrs)
    |> Ecto.Changeset.put_change(:review_id, review_id)
    |> Ecto.Changeset.put_change(:author_identity, identity)
    |> Ecto.Changeset.put_change(:author_display_name, display_name)
    |> then(fn cs ->
      if file_path, do: Ecto.Changeset.put_change(cs, :file_path, file_path), else: cs
    end)
    |> Repo.insert()
    |> tap(fn
      {:ok, _} -> Statistics.increment_comment()
      _ -> :ok
    end)
  end

  @doc "Update a comment's body if the identity matches the author."
  def update_comment(comment_id, body, identity) do
    case Repo.get(Comment, comment_id) do
      nil ->
        {:error, :not_found}

      %Comment{author_identity: author} = comment when author == identity ->
        comment
        |> Comment.create_changeset(%{
          "start_line" => comment.start_line,
          "end_line" => comment.end_line,
          "body" => body,
          "scope" => comment.scope || "line"
        })
        |> Repo.update()

      _ ->
        {:error, :unauthorized}
    end
  end

  @doc "Delete a comment if the identity matches the author."
  def delete_comment(comment_id, identity) do
    case Repo.get(Comment, comment_id) do
      nil ->
        {:error, :not_found}

      %Comment{author_identity: author} = comment when author == identity ->
        Repo.delete(comment)

      _ ->
        {:error, :unauthorized}
    end
  end

  @doc "Create a review from the share API payload. Files is a list of %{\"path\" => _, \"content\" => _} maps."
  def create_review(
        files_attrs,
        review_round,
        comments_attrs,
        review_comments_attrs \\ [],
        opts \\ []
      ) do
    total_size = files_attrs |> Enum.map(&byte_size(&1["content"] || "")) |> Enum.sum()
    user_id = Keyword.get(opts, :user_id)

    if total_size > @max_total_size do
      {:error, :total_size_exceeded}
    else
      review_changeset =
        %Review{}
        |> Review.create_changeset(%{"review_round" => review_round || 0})
        |> then(fn cs ->
          if user_id, do: Ecto.Changeset.put_change(cs, :user_id, user_id), else: cs
        end)

      Ecto.Multi.new()
      |> Ecto.Multi.insert(
        :review,
        review_changeset
      )
      |> Ecto.Multi.run(:files, fn _repo, %{review: review} ->
        case insert_round_snapshots(review, review.review_round, files_attrs) do
          :ok -> {:ok, :ok}
          error -> error
        end
      end)
      |> Ecto.Multi.run(:comments, fn _repo, %{review: review} ->
        case insert_imported_comments(review, comments_attrs) do
          :ok -> {:ok, :ok}
          error -> error
        end
      end)
      |> Ecto.Multi.run(:review_comments, fn _repo, %{review: review} ->
        case insert_imported_comments(review, review_comments_attrs) do
          :ok -> {:ok, :ok}
          error -> error
        end
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{review: review}} ->
          comment_count = length(comments_attrs) + length(review_comments_attrs)
          total_bytes = files_attrs |> Enum.map(&byte_size(&1["content"] || "")) |> Enum.sum()

          total_lines =
            files_attrs
            |> Enum.map(&((&1["content"] || "") |> String.split("\n") |> length()))
            |> Enum.sum()

          Statistics.increment_review(
            length(files_attrs),
            comment_count,
            total_bytes,
            total_lines
          )

          {:ok, review}

        {:error, _step, reason, _changes} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Update an existing review identified by token+delete_token with new files and comments.
  Appends a new round of snapshots if anything changed — no data is deleted.
  Returns {:ok, :updated, review}, {:ok, :no_changes, review}, or {:error, reason}.
  """
  def upsert_review(token, delete_token, payload) do
    with {:ok, review} <- fetch_review_for_update(token, delete_token) do
      files = payload["files"] || []
      comments = payload["comments"] || []

      if content_changed?(review, files) do
        new_round = review.review_round + 1

        Ecto.Multi.new()
        |> Ecto.Multi.run(:snapshots, fn _repo, _changes ->
          case insert_round_snapshots(review, new_round, files) do
            :ok -> {:ok, :ok}
            {:error, _} = error -> error
          end
        end)
        |> Ecto.Multi.run(:comments, fn _repo, _changes ->
          case replace_comments(review, comments) do
            :ok -> {:ok, :ok}
            {:error, _} = error -> error
          end
        end)
        |> Ecto.Multi.update(:review, Ecto.Changeset.change(review, review_round: new_round))
        |> Repo.transaction()
        |> case do
          {:ok, %{review: updated}} ->
            total_bytes = files |> Enum.map(&byte_size(&1["content"] || "")) |> Enum.sum()

            total_lines =
              files
              |> Enum.map(&((&1["content"] || "") |> String.split("\n") |> length()))
              |> Enum.sum()

            Statistics.increment_content(length(files), total_bytes, total_lines)
            {:ok, :updated, updated}

          {:error, _step, reason, _changes} ->
            {:error, reason}
        end
      else
        Ecto.Multi.new()
        |> Ecto.Multi.run(:comments, fn _repo, _changes ->
          case replace_comments(review, comments) do
            :ok -> {:ok, :ok}
            {:error, _} = error -> error
          end
        end)
        |> Repo.transaction()
        |> case do
          {:ok, _} -> {:ok, :no_changes, review}
          {:error, _step, reason, _changes} -> {:error, reason}
        end
      end
    end
  end

  defp fetch_review_for_update(token, delete_token) do
    case Repo.one(from r in Review, where: r.token == ^token) do
      nil -> {:error, :not_found}
      %{delete_token: ^delete_token} = review -> {:ok, review}
      _ -> {:error, :unauthorized}
    end
  end

  defp content_changed?(review, new_files) do
    current =
      get_current_files(review)
      |> Map.new(fn f -> {f.file_path, :crypto.hash(:sha256, f.content)} end)

    incoming =
      new_files
      |> Map.new(fn f -> {f["path"], :crypto.hash(:sha256, f["content"] || "")} end)

    current != incoming
  end

  defp replace_comments(review, new_comments) do
    Repo.delete_all(from c in Comment, where: c.review_id == ^review.id)

    Enum.reduce_while(new_comments, :ok, fn attrs, :ok ->
      scope = attrs["scope"] || infer_scope(attrs)
      replies_attrs = attrs["replies"] || []

      %Comment{}
      |> Comment.create_changeset(%{
        "start_line" => attrs["start_line"],
        "end_line" => attrs["end_line"],
        "body" => attrs["body"],
        "file_path" => attrs["file"],
        "quote" => attrs["quote"],
        "author_display_name" => attrs["author_display_name"] || attrs["author"],
        "review_round" => attrs["review_round"] || 1,
        "resolved" => attrs["resolved"] || false,
        "scope" => scope,
        "external_id" => attrs["external_id"]
      })
      |> Ecto.Changeset.put_change(:review_id, review.id)
      |> Ecto.Changeset.put_change(:author_identity, "imported")
      |> Repo.insert()
      |> case do
        {:ok, comment} ->
          case insert_replies(comment, replies_attrs) do
            :ok -> {:cont, :ok}
            {:error, _} = error -> {:halt, error}
          end

        {:error, changeset} ->
          {:halt, {:error, changeset}}
      end
    end)
  end

  defp insert_round_snapshots(review, round_number, files_attrs) do
    Enum.with_index(files_attrs)
    |> Enum.reduce_while(:ok, fn {file_attrs, idx}, :ok ->
      orphaned = file_attrs["orphaned"] == true

      result =
        %ReviewRoundSnapshot{}
        |> ReviewRoundSnapshot.changeset(%{
          "file_path" => file_attrs["path"],
          "content" => file_attrs["content"] || "",
          "round_number" => round_number,
          "position" => idx,
          "status" => file_attrs["status"] || "modified",
          "orphaned" => orphaned
        })
        |> Ecto.Changeset.put_change(:review_id, review.id)
        |> Repo.insert()

      case result do
        {:ok, _} -> {:cont, :ok}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp insert_imported_comments(review, comments_attrs) do
    Enum.reduce_while(comments_attrs, :ok, fn attrs, :ok ->
      replies_attrs = attrs["replies"] || []
      scope = attrs["scope"] || infer_scope(attrs)

      %Comment{}
      |> Comment.create_changeset(Map.put(attrs, "scope", scope))
      |> Ecto.Changeset.put_change(:review_id, review.id)
      |> Ecto.Changeset.put_change(:author_identity, "imported")
      |> Ecto.Changeset.put_change(:file_path, attrs["file"])
      |> Ecto.Changeset.put_change(:resolved, attrs["resolved"] == true)
      |> Ecto.Changeset.put_change(
        :author_display_name,
        attrs["author_display_name"] || attrs["author"]
      )
      |> Repo.insert()
      |> case do
        {:ok, comment} ->
          case insert_replies(comment, replies_attrs) do
            :ok -> {:cont, :ok}
            error -> {:halt, error}
          end

        {:error, changeset} ->
          {:halt, {:error, changeset}}
      end
    end)
  end

  defp infer_scope(attrs) do
    start_line = attrs["start_line"] || 0
    file = attrs["file"]

    cond do
      is_nil(file) and start_line == 0 -> "review"
      start_line == 0 -> "file"
      true -> "line"
    end
  end

  defp insert_replies(_comment, []), do: :ok

  defp insert_replies(comment, replies_attrs) do
    Enum.reduce_while(replies_attrs, :ok, fn attrs, :ok ->
      %Comment{}
      |> Comment.reply_changeset(attrs)
      |> Ecto.Changeset.put_change(:parent_id, comment.id)
      |> Ecto.Changeset.put_change(:review_id, comment.review_id)
      |> Ecto.Changeset.put_change(:author_identity, "imported")
      |> Ecto.Changeset.put_change(
        :author_display_name,
        attrs["author_display_name"] || attrs["author"]
      )
      |> Repo.insert()
      |> case do
        {:ok, _} -> {:cont, :ok}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  def create_round_snapshot(review_id, round_number, file_path, content) do
    %ReviewRoundSnapshot{}
    |> ReviewRoundSnapshot.changeset(%{
      "file_path" => file_path,
      "content" => content,
      "round_number" => round_number,
      "position" => 0
    })
    |> Ecto.Changeset.put_change(:review_id, review_id)
    |> Repo.insert()
  end

  @doc "Check whether any round snapshots exist for a given review and round."
  def has_round_snapshots?(review_id, round_number) do
    Repo.exists?(
      from s in ReviewRoundSnapshot,
        where: s.review_id == ^review_id and s.round_number == ^round_number
    )
  end

  @doc "Return a %{file_path => content} map for all snapshots at a given round (for diff display)."
  def get_round_snapshots(review_id, round_number) do
    Repo.all(
      from s in ReviewRoundSnapshot,
        where: s.review_id == ^review_id and s.round_number == ^round_number,
        select: {s.file_path, s.content}
    )
    |> Map.new()
  end

  @doc """
  Deletes all reviews whose last_activity_at is older than `days` days ago.
  Returns {:ok, count} where count is the number of deleted reviews.
  Cascade at the database level handles comments and review_files automatically.
  """
  def delete_inactive(days) when is_integer(days) and days > 0 do
    cutoff = DateTime.add(DateTime.utc_now(), -days, :day)
    base = from r in Review, where: r.last_activity_at < ^cutoff

    query =
      case Application.get_env(:crit, :demo_review_token) do
        nil -> base
        demo_token -> from r in base, where: r.token != ^demo_token
      end

    {count, _} = Repo.delete_all(query)
    {:ok, count}
  end

  @doc "Delete a review by its delete token. Returns :ok or {:error, :not_found} or {:error, :delete_failed}."
  def delete_by_delete_token(delete_token) do
    case Repo.get_by(Review, delete_token: delete_token) do
      nil ->
        {:error, :not_found}

      review ->
        case Repo.delete(review) do
          {:ok, _} -> :ok
          {:error, _changeset} -> {:error, :delete_failed}
        end
    end
  end

  @doc """
  Returns all reviews as plain maps with comment/file counts and first file path.
  Sorted by last_activity_at descending. Does not include delete_token.
  """
  def list_reviews_with_counts do
    first_file_subquery =
      from(rf in ReviewRoundSnapshot,
        where: rf.review_id == parent_as(:review).id,
        order_by: [asc: rf.position],
        limit: 1,
        select: rf.file_path
      )

    from(r in Review, as: :review)
    |> join(:left, [r], c in Comment, on: c.review_id == r.id)
    |> join(:left, [r, _c], rf in ReviewRoundSnapshot, on: rf.review_id == r.id)
    |> join(:left_lateral, [r, _c, _rf], fp in subquery(first_file_subquery), on: true)
    |> group_by([r, _c, _rf, fp], [
      r.id,
      r.token,
      r.inserted_at,
      r.last_activity_at,
      r.user_id,
      fp.file_path
    ])
    |> select([r, c, rf, fp], %{
      id: r.id,
      token: r.token,
      inserted_at: r.inserted_at,
      last_activity_at: r.last_activity_at,
      user_id: r.user_id,
      comment_count: count(c.id, :distinct),
      file_count: count(rf.id, :distinct),
      first_file_path: fp.file_path
    })
    |> order_by([r], desc: r.last_activity_at)
    |> Repo.all()
  end

  @doc """
  Returns reviews for a specific user as plain maps with comment/file counts.
  Same as `list_reviews_with_counts/0` but filtered to the given user_id.
  """
  def list_user_reviews_with_counts(user_id) do
    first_file_subquery =
      from(rf in ReviewRoundSnapshot,
        where: rf.review_id == parent_as(:review).id,
        order_by: [asc: rf.position],
        limit: 1,
        select: rf.file_path
      )

    from(r in Review, as: :review)
    |> where([r], r.user_id == ^user_id)
    |> join(:left, [r], c in Comment, on: c.review_id == r.id)
    |> join(:left, [r, _c], rf in ReviewRoundSnapshot, on: rf.review_id == r.id)
    |> join(:left_lateral, [r, _c, _rf], fp in subquery(first_file_subquery), on: true)
    |> group_by([r, _c, _rf, fp], [
      r.id,
      r.token,
      r.inserted_at,
      r.last_activity_at,
      r.user_id,
      fp.file_path
    ])
    |> select([r, c, rf, fp], %{
      id: r.id,
      token: r.token,
      inserted_at: r.inserted_at,
      last_activity_at: r.last_activity_at,
      user_id: r.user_id,
      comment_count: count(c.id, :distinct),
      file_count: count(rf.id, :distinct),
      first_file_path: fp.file_path
    })
    |> order_by([r], desc: r.last_activity_at)
    |> Repo.all()
  end

  @doc """
  Delete a review by its id.

  Accepts an optional `owner_id` keyword argument. When provided, deletion is
  only allowed if the review's `user_id` matches `owner_id` or if the review
  has no owner (legacy reviews created before OAuth was introduced).

  Returns `:ok`, `{:error, :not_found}`, or `{:error, :unauthorized}`.
  """
  def delete_review(id, opts \\ []) do
    owner_id = Keyword.get(opts, :owner_id)

    case Repo.get(Review, id) do
      nil ->
        {:error, :not_found}

      review ->
        if owner_id && review.user_id && review.user_id != owner_id do
          {:error, :unauthorized}
        else
          case Repo.delete(review) do
            {:ok, _} -> :ok
            {:error, _} -> {:error, :delete_failed}
          end
        end
    end
  end

  @doc "Update the display name on all comments by a given identity. Returns {count, nil}."
  def update_display_name(identity, display_name) do
    from(c in Comment, where: c.author_identity == ^identity)
    |> Repo.update_all(set: [author_display_name: display_name])
  end

  @doc """
  Returns {id, token} pairs for all reviews that have comments by the given identity.
  Used to broadcast display name changes to affected live review pages.
  """
  def reviews_for_identity(identity) do
    from(c in Comment,
      where: c.author_identity == ^identity,
      join: r in Review,
      on: r.id == c.review_id,
      distinct: true,
      select: {r.id, r.token}
    )
    |> Repo.all()
  end

  @doc "Toggle the resolved state of a comment. Scoped to the given review."
  def resolve_comment(comment_id, resolved, review_id) when is_boolean(resolved) do
    case Repo.get_by(Comment, id: comment_id, review_id: review_id) do
      nil -> {:error, :not_found}
      %Comment{parent_id: parent} when parent != nil -> {:error, :not_found}
      comment -> comment |> Ecto.Changeset.change(resolved: resolved) |> Repo.update()
    end
  end

  @doc "Create a reply to an existing comment. Scoped to the given review."
  def create_reply(comment_id, attrs, identity, display_name, review_id) do
    case Repo.get_by(Comment, id: comment_id, review_id: review_id) do
      nil ->
        {:error, :not_found}

      %Comment{parent_id: parent} when parent != nil ->
        {:error, :not_found}

      parent ->
        %Comment{}
        |> Comment.reply_changeset(attrs)
        |> Ecto.Changeset.put_change(:parent_id, comment_id)
        |> Ecto.Changeset.put_change(:review_id, parent.review_id)
        |> Ecto.Changeset.put_change(:author_identity, identity)
        |> Ecto.Changeset.put_change(:author_display_name, display_name)
        |> Repo.insert()
        |> tap(fn
          {:ok, _} -> Statistics.increment_comment()
          _ -> :ok
        end)
    end
  end

  @doc "Update a reply's body if the identity matches the author."
  def update_reply(reply_id, body, identity) do
    case Repo.get(Comment, reply_id) do
      nil ->
        {:error, :not_found}

      %Comment{parent_id: nil} ->
        {:error, :not_found}

      %Comment{author_identity: author} = reply when author == identity ->
        reply |> Comment.reply_changeset(%{"body" => body}) |> Repo.update()

      _ ->
        {:error, :unauthorized}
    end
  end

  @doc "Delete a reply if the identity matches the author."
  def delete_reply(reply_id, identity) do
    case Repo.get(Comment, reply_id) do
      nil ->
        {:error, :not_found}

      %Comment{parent_id: nil} ->
        {:error, :not_found}

      %Comment{author_identity: author} = reply when author == identity ->
        Repo.delete(reply)

      _ ->
        {:error, :unauthorized}
    end
  end

  @doc "Serialize a comment to the API JSON shape."
  def serialize_comment(%Comment{} = c) do
    replies =
      case c.replies do
        %Ecto.Association.NotLoaded{} -> []
        list -> list
      end

    %{
      id: c.id,
      start_line: c.start_line,
      end_line: c.end_line,
      body: c.body,
      quote: c.quote,
      scope: c.scope || "line",
      author_identity: c.author_identity,
      author_display_name: c.author_display_name,
      review_round: c.review_round,
      file_path: c.file_path,
      resolved: c.resolved,
      external_id: c.external_id,
      created_at: DateTime.to_iso8601(c.inserted_at),
      updated_at: DateTime.to_iso8601(c.updated_at),
      replies: Enum.map(replies, &serialize_reply/1)
    }
  end

  @doc "Serialize a reply to the API JSON shape."
  def serialize_reply(%Comment{} = r) do
    %{
      id: r.id,
      body: r.body,
      author_identity: r.author_identity,
      author_display_name: r.author_display_name,
      created_at: DateTime.to_iso8601(r.inserted_at)
    }
  end
end
