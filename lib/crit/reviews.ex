defmodule Crit.Reviews do
  @moduledoc "Context for reviews and comments."

  import Ecto.Query
  alias Crit.{Repo, Review, Comment, ReviewFile}

  @max_total_size 10_485_760

  @doc "Fetch a review by its token, preloading comments sorted by start_line."
  def get_by_token(token) do
    query =
      from r in Review,
        where: r.token == ^token,
        preload: [
          files: ^from(f in ReviewFile, order_by: [asc: f.position]),
          comments:
            ^from(c in Comment,
              where: is_nil(c.parent_id),
              order_by: [asc: c.start_line, asc: c.end_line],
              preload: [:replies]
            )
        ]

    Repo.one(query)
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
          "body" => body
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
  def create_review(files_attrs, review_round, comments_attrs) do
    total_size = files_attrs |> Enum.map(&byte_size(&1["content"] || "")) |> Enum.sum()

    if total_size > @max_total_size do
      {:error, :total_size_exceeded}
    else
      Ecto.Multi.new()
      |> Ecto.Multi.insert(
        :review,
        %Review{} |> Review.create_changeset(%{"review_round" => review_round || 0})
      )
      |> Ecto.Multi.run(:files, fn _repo, %{review: review} ->
        case insert_files(review, files_attrs) do
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
      |> Repo.transaction()
      |> case do
        {:ok, %{review: review}} -> {:ok, review}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    end
  end

  defp insert_files(review, files_attrs) do
    Enum.with_index(files_attrs)
    |> Enum.reduce_while(:ok, fn {file_attrs, idx}, :ok ->
      %ReviewFile{}
      |> ReviewFile.create_changeset(%{
        "file_path" => file_attrs["path"],
        "content" => file_attrs["content"],
        "position" => idx
      })
      |> Ecto.Changeset.put_change(:review_id, review.id)
      |> Repo.insert()
      |> case do
        {:ok, _} -> {:cont, :ok}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp insert_imported_comments(review, comments_attrs) do
    Enum.reduce_while(comments_attrs, :ok, fn attrs, :ok ->
      replies_attrs = attrs["replies"] || []

      %Comment{}
      |> Comment.create_changeset(attrs)
      |> Ecto.Changeset.put_change(:review_id, review.id)
      |> Ecto.Changeset.put_change(:author_identity, "imported")
      |> Ecto.Changeset.put_change(:file_path, attrs["file"])
      |> Ecto.Changeset.put_change(:resolved, attrs["resolved"] == true)
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

  @doc "Returns aggregate stats for the self-hosted dashboard."
  def dashboard_stats do
    total_reviews = Repo.aggregate(Review, :count)
    total_comments = Repo.aggregate(Comment, :count)
    total_files = Repo.aggregate(ReviewFile, :count)

    week_ago = DateTime.utc_now() |> DateTime.add(-7, :day) |> DateTime.truncate(:second)

    reviews_this_week =
      Repo.aggregate(from(r in Review, where: r.inserted_at >= ^week_ago), :count)

    avg_comments_per_review =
      if total_reviews > 0, do: total_comments * 1.0 / total_reviews, else: 0.0

    total_storage_bytes =
      Repo.one(
        from(rf in ReviewFile,
          select: fragment("coalesce(sum(octet_length(?)), 0)", rf.content)
        )
      ) || 0

    %{
      total_reviews: total_reviews,
      total_comments: total_comments,
      total_files: total_files,
      reviews_this_week: reviews_this_week,
      avg_comments_per_review: avg_comments_per_review,
      total_storage_bytes: total_storage_bytes
    }
  end

  @doc "Returns a list of {date, count} tuples for the last N days (UTC)."
  def activity_chart(days \\ 30) do
    start_date = Date.utc_today() |> Date.add(-(days - 1))

    counts_by_date =
      from(r in Review,
        where: r.inserted_at >= ^DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC"),
        group_by: fragment("?::date", r.inserted_at),
        select: {fragment("?::date", r.inserted_at), count(r.id)}
      )
      |> Repo.all()
      |> Map.new()

    Enum.map(0..(days - 1), fn offset ->
      date = Date.add(start_date, offset)
      {date, Map.get(counts_by_date, date, 0)}
    end)
  end

  @doc """
  Returns all reviews as plain maps with comment/file counts and first file path.
  Sorted by last_activity_at descending. Does not include delete_token.
  """
  def list_reviews_with_counts do
    first_file_subquery =
      from(rf in ReviewFile,
        where: rf.review_id == parent_as(:review).id,
        order_by: [asc: rf.position],
        limit: 1,
        select: rf.file_path
      )

    from(r in Review, as: :review)
    |> join(:left, [r], c in Comment, on: c.review_id == r.id)
    |> join(:left, [r, _c], rf in ReviewFile, on: rf.review_id == r.id)
    |> join(:left_lateral, [r, _c, _rf], fp in subquery(first_file_subquery), on: true)
    |> group_by([r, _c, _rf, fp], [r.id, r.token, r.inserted_at, r.last_activity_at, fp.file_path])
    |> select([r, c, rf, fp], %{
      id: r.id,
      token: r.token,
      inserted_at: r.inserted_at,
      last_activity_at: r.last_activity_at,
      comment_count: count(c.id, :distinct),
      file_count: count(rf.id, :distinct),
      first_file_path: fp.file_path
    })
    |> order_by([r], desc: r.last_activity_at)
    |> Repo.all()
  end

  @doc "Delete a review by its id. Returns :ok or {:error, :not_found}."
  def delete_review(id) do
    case Repo.get(Review, id) do
      nil ->
        {:error, :not_found}

      review ->
        case Repo.delete(review) do
          {:ok, _} -> :ok
          {:error, _} -> {:error, :delete_failed}
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
      author_identity: c.author_identity,
      author_display_name: c.author_display_name,
      review_round: c.review_round,
      file_path: c.file_path,
      resolved: c.resolved,
      created_at: DateTime.to_iso8601(c.inserted_at),
      updated_at: DateTime.to_iso8601(c.updated_at),
      replies:
        Enum.map(replies, fn r ->
          %{
            id: r.id,
            body: r.body,
            author_identity: r.author_identity,
            author_display_name: r.author_display_name,
            created_at: DateTime.to_iso8601(r.inserted_at)
          }
        end)
    }
  end
end
