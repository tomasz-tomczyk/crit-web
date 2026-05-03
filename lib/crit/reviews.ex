defmodule Crit.Reviews do
  @moduledoc "Context for reviews and comments."

  import Ecto.Query
  alias Crit.{Repo, Review, Comment, ReviewRoundSnapshot, Statistics, User}
  alias Crit.Accounts.Scope

  @max_total_size 10_485_760

  @doc "Fetch a review by its token, preloading comments sorted by start_line."
  def get_by_token(token) do
    review =
      Repo.one(
        from r in Review,
          where: r.token == ^token,
          preload: [
            :user,
            comments:
              ^from(c in Comment,
                where: is_nil(c.parent_id),
                order_by: [asc: c.start_line, asc: c.end_line, asc: c.inserted_at],
                preload: [:user, replies: [:user]]
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
        order_by: [asc: c.start_line, asc: c.end_line, asc: c.inserted_at],
        preload: [:user, replies: [:user]]
    )
  end

  @doc """
  Create a comment for a review within the given scope.

  Anonymous scope (`scope.user == nil`) → `user_id = nil`,
  `author_identity = scope.identity`.
  Authenticated scope → `user_id = scope.user.id`, `author_identity = nil`.

  Opts:
    * `:file_path` — file path the comment is anchored to
  """
  def create_comment(%Scope{} = scope, %Review{id: review_id}, attrs, opts \\ []) do
    user_id = Scope.user_id(scope)
    identity = scope.identity
    display_name = scope.display_name
    file_path = Keyword.get(opts, :file_path)

    %Comment{}
    |> Comment.create_changeset(attrs)
    |> Ecto.Changeset.put_change(:review_id, review_id)
    |> Ecto.Changeset.put_change(:author_identity, if(user_id, do: nil, else: identity))
    |> Ecto.Changeset.put_change(:author_display_name, display_name)
    |> Ecto.Changeset.put_change(:user_id, user_id)
    |> then(fn cs ->
      if file_path, do: Ecto.Changeset.put_change(cs, :file_path, file_path), else: cs
    end)
    |> Repo.insert()
    |> tap(fn
      {:ok, _} -> Statistics.increment_comment()
      _ -> :ok
    end)
  end

  @doc """
  Update a comment's body if the caller's scope owns it.

  Authorization rules:
    * `user_id IS NOT NULL` on the comment → must match `scope.user.id`
    * `user_id IS NULL` → must match `scope.identity`
  """
  def update_comment(%Scope{} = scope, comment_id, body) do
    case Repo.get(Comment, comment_id) do
      nil ->
        {:error, :not_found}

      %Comment{} = comment ->
        if comment_owned_by?(scope, comment) do
          comment
          |> Comment.body_changeset(%{"body" => body})
          |> Repo.update()
        else
          {:error, :unauthorized}
        end
    end
  end

  @doc "Delete a comment if the caller's scope owns it. See `update_comment/3` for ownership rules."
  def delete_comment(%Scope{} = scope, comment_id) do
    case Repo.get(Comment, comment_id) do
      nil ->
        {:error, :not_found}

      %Comment{} = comment ->
        if comment_owned_by?(scope, comment) do
          Repo.delete(comment)
        else
          {:error, :unauthorized}
        end
    end
  end

  @doc """
  Promote a review from :unlisted to :public. Only the authenticated owner
  (`scope.user.id == review.user_id`) may promote.

  Visibility is one-way: there is no `make_unlisted/2`. Per the gist model,
  the URL is the review's public identity — to "unpublish", delete and recreate.

  Returns `{:ok, review}`, `{:error, :not_found}`, `{:error, :unauthorized}`,
  `{:error, :already_public}`, or `{:error, %Ecto.Changeset{}}`.
  """
  def make_public(%Scope{} = scope, review_id) do
    with {:ok, review} <- fetch_review_for_owner(scope, review_id),
         :ok <- ensure_unlisted(review) do
      review
      |> Review.visibility_changeset(%{visibility: :public})
      |> Repo.update()
    end
  end

  defp ensure_unlisted(%Review{visibility: :unlisted}), do: :ok
  defp ensure_unlisted(%Review{visibility: :public}), do: {:error, :already_public}

  defp fetch_review_for_owner(%Scope{} = scope, review_id) do
    with {:ok, uuid} <- Ecto.UUID.cast(review_id),
         %Review{} = review <- Repo.get(Review, uuid),
         true <- scope_can_modify_review?(scope, review) do
      {:ok, review}
    else
      false -> {:error, :unauthorized}
      _ -> {:error, :not_found}
    end
  end

  # Owner-only mutation gate. Anonymous-owned reviews (`user_id: nil`) are
  # never modifiable through scope-authed paths — they're administered via
  # their `delete_token` (see `delete_by_delete_token/1`). When admin scopes
  # land, this is the seam to extend.
  defp scope_can_modify_review?(%Scope{}, %Review{user_id: nil}), do: false

  defp scope_can_modify_review?(%Scope{} = scope, %Review{user_id: owner_id}) do
    case Scope.user_id(scope) do
      nil -> false
      ^owner_id -> true
      _ -> false
    end
  end

  @doc "Returns tokens of every review with `visibility: :public`, ordered by recency."
  def list_public_review_tokens do
    Repo.all(
      from r in Review,
        where: r.visibility == :public,
        order_by: [desc: r.last_activity_at],
        select: r.token
    )
  end

  defp comment_owned_by?(%Scope{} = scope, %Comment{user_id: nil, author_identity: ai}) do
    not is_nil(ai) and ai == scope.identity
  end

  defp comment_owned_by?(%Scope{} = scope, %Comment{user_id: uid}) do
    case Scope.user_id(scope) do
      nil -> false
      current_user_id -> uid == current_user_id
    end
  end

  @doc """
  Create a review from the share API payload within the given scope. Files is a
  list of `%{"path" => _, "content" => _}` maps.

  Opts:
    * `:cli_args` — CLI arguments associated with the share action
  """
  def create_review(
        %Scope{} = scope,
        files_attrs,
        review_round,
        comments_attrs,
        review_comments_attrs \\ [],
        opts \\ []
      ) do
    total_bytes = files_attrs |> Enum.map(&byte_size(&1["content"] || "")) |> Enum.sum()

    total_lines =
      files_attrs
      |> Enum.map(&((&1["content"] || "") |> String.split("\n") |> length()))
      |> Enum.sum()

    user_id = Scope.user_id(scope)
    cli_args = Keyword.get(opts, :cli_args) || []

    if total_bytes > @max_total_size do
      {:error, :total_size_exceeded}
    else
      review_changeset =
        %Review{}
        |> Review.create_changeset(%{"review_round" => review_round || 0, "cli_args" => cli_args})
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
        case insert_imported_comments(review, comments_attrs, user_id) do
          :ok -> {:ok, :ok}
          error -> error
        end
      end)
      |> Ecto.Multi.run(:review_comments, fn _repo, %{review: review} ->
        case insert_imported_comments(review, review_comments_attrs, user_id) do
          :ok -> {:ok, :ok}
          error -> error
        end
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{review: review}} ->
          comment_count = length(comments_attrs) + length(review_comments_attrs)

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
  Update an existing review identified by token+delete_token with new files and comments
  within the given scope. Appends a new round of snapshots if anything changed —
  no data is deleted.

  Returns {:ok, :updated, review}, {:ok, :no_changes, review}, or {:error, reason}.
  """
  def upsert_review(%Scope{} = scope, token, delete_token, payload) do
    user_id = Scope.user_id(scope)

    with {:ok, review} <- fetch_review_for_update(token, delete_token) do
      files = payload["files"] || []
      comments = payload["comments"] || []
      cli_args = payload["cli_args"]

      review_changes =
        if cli_args, do: %{cli_args: cli_args}, else: %{}

      if content_changed?(review, files) do
        new_round = review.review_round + 1
        review_changes = Map.put(review_changes, :review_round, new_round)

        Ecto.Multi.new()
        |> Ecto.Multi.run(:snapshots, fn _repo, _changes ->
          case insert_round_snapshots(review, new_round, files) do
            :ok -> {:ok, :ok}
            {:error, _} = error -> error
          end
        end)
        |> Ecto.Multi.run(:comments, fn _repo, _changes ->
          case replace_comments(review, comments, user_id) do
            :ok -> {:ok, :ok}
            {:error, _} = error -> error
          end
        end)
        |> Ecto.Multi.update(:review, Review.update_changeset(review, review_changes))
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
        multi = Ecto.Multi.new()

        multi =
          Ecto.Multi.run(multi, :comments, fn _repo, _changes ->
            case replace_comments(review, comments, user_id) do
              :ok -> {:ok, :ok}
              {:error, _} = error -> error
            end
          end)

        multi =
          if review_changes != %{} do
            Ecto.Multi.update(multi, :review, Review.update_changeset(review, review_changes))
          else
            multi
          end

        multi
        |> Repo.transaction()
        |> case do
          {:ok, %{review: updated}} -> {:ok, :no_changes, updated}
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

  # Re-share path. We capture existing comments by external_id BEFORE deleting,
  # so we can preserve their server-verified `user_id` on roundtrip. Without
  # this carry-forward, every re-share would strip attribution from comments
  # authored by other users.
  defp replace_comments(review, new_comments, current_user_id) do
    existing_by_external_id =
      from(c in Comment,
        where: c.review_id == ^review.id and not is_nil(c.external_id) and is_nil(c.parent_id)
      )
      |> Repo.all()
      |> Map.new(fn c -> {c.external_id, c} end)

    # Same carry-forward for replies. Reply external_ids are the local CLI
    # reply IDs; assumed unique within a review (CLI stamps `rp_<random>` per
    # reply).
    existing_replies_by_external_id =
      from(c in Comment,
        where: c.review_id == ^review.id and not is_nil(c.external_id) and not is_nil(c.parent_id)
      )
      |> Repo.all()
      |> Map.new(fn c -> {c.external_id, c} end)

    Repo.delete_all(from c in Comment, where: c.review_id == ^review.id)

    Enum.reduce_while(new_comments, :ok, fn attrs, :ok ->
      scope = attrs["scope"] || infer_scope(attrs)
      replies_attrs = attrs["replies"] || []
      external_id = attrs["external_id"]

      existing = external_id && Map.get(existing_by_external_id, external_id)

      {resolved_user_id, resolved_identity, resolved_display_name} =
        resolve_attribution(existing, attrs, current_user_id)

      %Comment{}
      |> Comment.create_changeset(%{
        "start_line" => attrs["start_line"],
        "end_line" => attrs["end_line"],
        "body" => attrs["body"],
        "file_path" => attrs["file"],
        "quote" => attrs["quote"],
        "author_display_name" => resolved_display_name,
        "review_round" => attrs["review_round"] || 1,
        "resolved" => attrs["resolved"] || false,
        "scope" => scope,
        "external_id" => external_id
      })
      |> Ecto.Changeset.put_change(:review_id, review.id)
      |> Ecto.Changeset.put_change(:author_identity, resolved_identity)
      |> Ecto.Changeset.put_change(:user_id, resolved_user_id)
      |> Repo.insert()
      |> case do
        {:ok, comment} ->
          case insert_replies(
                 comment,
                 replies_attrs,
                 current_user_id,
                 existing_replies_by_external_id
               ) do
            :ok -> {:cont, :ok}
            {:error, _} = error -> {:halt, error}
          end

        {:error, changeset} ->
          {:halt, {:error, changeset}}
      end
    end)
  end

  # Decide (user_id, author_identity, author_display_name) for a comment
  # arriving via the share API.
  #
  # An existing row matched by external_id wins outright: if it already has a
  # verified user_id, preserve it. The current sharer (whether authed or not)
  # cannot rewrite attribution on a comment authored by someone else — that's
  # how foreign comments roundtrip safely through `crit fetch`/re-share.
  #
  # Otherwise, the only attribution the server trusts is the bearer token.
  # The payload's per-comment user_id is treated as intent only:
  #   * empty → anonymous (NULL), even when the request is authenticated.
  #     Lets users who logged in mid-flow share earlier anonymous comments
  #     without retroactively claiming them.
  #   * matches current_user_id → write the verified id.
  #   * any other value → treated as a spoof attempt; we have no row to
  #     roundtrip-match against (the first clause would have caught it),
  #     so we drop to NULL.
  #
  # Anonymous requests always end up with NULL user_id and the legacy
  # "imported" sentinel in author_identity (kept as a back-compat contract
  # for the Go CLI on unauthenticated shares).
  defp resolve_attribution(%Comment{user_id: existing_uid} = existing, _attrs, _current_user_id)
       when not is_nil(existing_uid) do
    {existing_uid, nil, existing.author_display_name}
  end

  defp resolve_attribution(_existing, attrs, current_user_id) do
    display_name = attrs["author_display_name"] || attrs["author"]
    payload_user_id = attrs["user_id"]

    cond do
      current_user_id && blank?(payload_user_id) ->
        {nil, "imported", display_name}

      current_user_id && payload_user_id == current_user_id ->
        {current_user_id, nil, display_name}

      current_user_id ->
        {nil, "imported", display_name}

      true ->
        {nil, "imported", display_name}
    end
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_), do: false

  defp insert_round_snapshots(review, round_number, files_attrs) do
    Enum.with_index(files_attrs)
    |> Enum.reduce_while(:ok, fn {file_attrs, idx}, :ok ->
      status = file_attrs["status"] || "modified"

      result =
        %ReviewRoundSnapshot{}
        |> ReviewRoundSnapshot.changeset(%{
          "file_path" => file_attrs["path"],
          "content" => file_attrs["content"] || "",
          "round_number" => round_number,
          "position" => idx,
          "status" => status
        })
        |> Ecto.Changeset.put_change(:review_id, review.id)
        |> Repo.insert()

      case result do
        {:ok, _} -> {:cont, :ok}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  # Initial-share path (POST). No existing rows to carry forward — the rules
  # collapse to:
  #   * Authenticated → write current_user_id, clear author_identity.
  #   * Anonymous → write "imported" sentinel into author_identity, NULL user_id.
  defp insert_imported_comments(review, comments_attrs, current_user_id) do
    Enum.reduce_while(comments_attrs, :ok, fn attrs, :ok ->
      replies_attrs = attrs["replies"] || []
      scope = attrs["scope"] || infer_scope(attrs)

      # Initial-share path has no existing-by-external_id rows to carry forward,
      # but rules #5/#6/#8 still apply per-comment. Delegate to resolve_attribution
      # with `nil` existing so per-payload `user_id` intent is honored.
      {resolved_user_id, resolved_identity, resolved_display_name} =
        resolve_attribution(nil, attrs, current_user_id)

      %Comment{}
      |> Comment.create_changeset(Map.put(attrs, "scope", scope))
      |> Ecto.Changeset.put_change(:review_id, review.id)
      |> Ecto.Changeset.put_change(:author_identity, resolved_identity)
      |> Ecto.Changeset.put_change(:user_id, resolved_user_id)
      |> Ecto.Changeset.put_change(:file_path, attrs["file"])
      |> Ecto.Changeset.put_change(:resolved, attrs["resolved"] == true)
      |> Ecto.Changeset.put_change(:author_display_name, resolved_display_name)
      |> Repo.insert()
      |> case do
        {:ok, comment} ->
          case insert_replies(comment, replies_attrs, current_user_id) do
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

  defp insert_replies(comment, replies_attrs, current_user_id),
    do: insert_replies(comment, replies_attrs, current_user_id, %{})

  defp insert_replies(_comment, [], _current_user_id, _existing_by_external_id), do: :ok

  defp insert_replies(comment, replies_attrs, current_user_id, existing_by_external_id) do
    Enum.reduce_while(replies_attrs, :ok, fn attrs, :ok ->
      external_id = attrs["external_id"]
      existing = external_id && Map.get(existing_by_external_id, external_id)

      {resolved_user_id, resolved_identity, resolved_display_name} =
        resolve_attribution(existing, attrs, current_user_id)

      %Comment{}
      |> Comment.reply_changeset(attrs)
      |> Ecto.Changeset.put_change(:parent_id, comment.id)
      |> Ecto.Changeset.put_change(:review_id, comment.review_id)
      |> Ecto.Changeset.put_change(:author_identity, resolved_identity)
      |> Ecto.Changeset.put_change(:user_id, resolved_user_id)
      |> Ecto.Changeset.put_change(:author_display_name, resolved_display_name)
      |> Ecto.Changeset.put_change(:external_id, external_id)
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

    ids_query =
      from r in Review,
        left_join: u in User,
        on: u.id == r.user_id,
        where:
          r.last_activity_at < ^cutoff and
            (is_nil(u.id) or u.keep_reviews == false),
        select: r.id

    ids_query =
      case Application.get_env(:crit, :demo_review_token) do
        nil -> ids_query
        demo_token -> from [r, _u] in ids_query, where: r.token != ^demo_token
      end

    {count, _} =
      Repo.delete_all(from r in Review, where: r.id in subquery(ids_query))

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
    reviews_with_counts_query(:all) |> Repo.all()
  end

  @doc """
  Returns reviews for the authenticated user in the scope, with comment/file counts.
  Returns `[]` for an anonymous scope (no user).
  """
  def list_user_reviews_with_counts(%Scope{user: %User{id: user_id}}) do
    reviews_with_counts_query({:user, user_id}) |> Repo.all()
  end

  def list_user_reviews_with_counts(%Scope{}), do: []

  defp reviews_with_counts_query(filter) do
    first_file_subquery =
      from(rf in ReviewRoundSnapshot,
        where: rf.review_id == parent_as(:review).id,
        order_by: [asc: rf.position],
        limit: 1,
        select: %{file_path: rf.file_path, content: rf.content}
      )

    base =
      from(r in Review, as: :review)
      |> join(:left, [r], c in Comment, on: c.review_id == r.id)
      |> join(:left, [r, _c], rf in ReviewRoundSnapshot, on: rf.review_id == r.id)
      |> join(:left_lateral, [r, _c, _rf], fp in subquery(first_file_subquery), on: true)
      |> join(:left, [r, _c, _rf, _fp], u in User, on: u.id == r.user_id)
      |> group_by([r, _c, _rf, fp, u], [
        r.id,
        r.token,
        r.inserted_at,
        r.last_activity_at,
        r.user_id,
        fp.file_path,
        fp.content,
        u.name,
        u.email,
        u.avatar_url
      ])
      |> select([r, c, rf, fp, u], %{
        id: r.id,
        token: r.token,
        inserted_at: r.inserted_at,
        last_activity_at: r.last_activity_at,
        user_id: r.user_id,
        comment_count: count(c.id, :distinct),
        file_count: count(rf.id, :distinct),
        first_file_path: fp.file_path,
        first_file_content: fp.content,
        author_name: u.name,
        author_email: u.email,
        author_avatar_url: u.avatar_url
      })
      |> order_by([r], desc: r.last_activity_at)

    case filter do
      :all -> base
      {:user, user_id} -> from [r, _c, _rf, _fp, _u] in base, where: r.user_id == ^user_id
    end
  end

  @doc """
  Delete a review by id within the given scope.

  Anonymous scope → `{:error, :unauthorized}`.
  Authenticated scope → allowed only when the review's `user_id` matches the
  scope's user. Anonymous reviews (`review.user_id == nil`) cannot be deleted
  via this path — they are deleted by their `delete_token` instead
  (`delete_by_delete_token/1`).

  Returns `:ok`, `{:error, :not_found}`, `{:error, :unauthorized}`, or
  `{:error, :delete_failed}`.
  """
  def delete_review(%Scope{} = scope, id) do
    case Repo.get(Review, id) do
      nil ->
        {:error, :not_found}

      review ->
        if scope_can_modify_review?(scope, review) do
          case Repo.delete(review) do
            {:ok, _} -> :ok
            {:error, _} -> {:error, :delete_failed}
          end
        else
          {:error, :unauthorized}
        end
    end
  end

  @doc """
  Update the display name on all comments owned by the scope's identity.

  No-ops for authenticated scopes (their display name is derived from the user
  record).
  """
  def update_display_name(%Scope{user: nil, identity: identity}, name)
      when is_binary(identity) and is_binary(name) do
    from(c in Comment, where: c.author_identity == ^identity)
    |> Repo.update_all(set: [author_display_name: name])

    :ok
  end

  def update_display_name(%Scope{}, _name), do: :ok

  @doc """
  Returns {id, token} pairs for all reviews that have comments by the scope's
  identity. Used to broadcast display name changes to affected live review pages.

  Returns `[]` for authenticated scopes.
  """
  def reviews_for_identity(%Scope{user: nil, identity: identity}) when is_binary(identity) do
    from(c in Comment,
      where: c.author_identity == ^identity,
      join: r in Review,
      on: r.id == c.review_id,
      distinct: true,
      select: {r.id, r.token}
    )
    |> Repo.all()
  end

  def reviews_for_identity(%Scope{}), do: []

  @doc """
  Toggle the resolved state of a comment. Scoped to the given review.

  Authorization rules:
    * Authenticated review owner → allowed.
    * Authenticated comment author → allowed.
    * Anonymous comment author with matching identity → allowed.
    * Otherwise → `{:error, :unauthorized}`.
  """
  def resolve_comment(%Scope{} = scope, comment_id, resolved, review_id)
      when is_boolean(resolved) do
    with %Comment{parent_id: nil} = comment <-
           Repo.get_by(Comment, id: comment_id, review_id: review_id) || {:error, :not_found},
         %Review{} = review <- Repo.get(Review, review_id) || {:error, :not_found},
         :ok <- can_resolve_comment?(scope, comment, review) do
      comment |> Ecto.Changeset.change(resolved: resolved) |> Repo.update()
    else
      %Comment{parent_id: parent} when parent != nil -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  defp can_resolve_comment?(%Scope{} = scope, %Comment{} = comment, %Review{} = review) do
    scope_uid = Scope.user_id(scope)

    cond do
      scope_uid != nil and scope_uid == review.user_id ->
        :ok

      scope_uid != nil and scope_uid == comment.user_id ->
        :ok

      comment.user_id == nil and scope.identity != nil and
          scope.identity == comment.author_identity ->
        :ok

      true ->
        {:error, :unauthorized}
    end
  end

  @doc """
  Create a reply to an existing comment within the given scope. Scoped to the
  given review.

  Same attribution rules as `create_comment/4`.
  """
  def create_reply(%Scope{} = scope, comment_id, attrs, review_id) do
    user_id = Scope.user_id(scope)
    identity = scope.identity
    display_name = scope.display_name

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
        |> Ecto.Changeset.put_change(:author_identity, if(user_id, do: nil, else: identity))
        |> Ecto.Changeset.put_change(:user_id, user_id)
        |> Ecto.Changeset.put_change(:author_display_name, display_name)
        |> Repo.insert()
        |> case do
          {:ok, reply} ->
            Statistics.increment_comment()
            {:ok, Repo.preload(reply, :user)}

          other ->
            other
        end
    end
  end

  @doc "Update a reply's body if the caller's scope owns it. See `update_comment/3` for ownership rules."
  def update_reply(%Scope{} = scope, reply_id, body) do
    case Repo.get(Comment, reply_id) do
      nil ->
        {:error, :not_found}

      %Comment{parent_id: nil} ->
        {:error, :not_found}

      %Comment{} = reply ->
        if comment_owned_by?(scope, reply) do
          reply |> Comment.reply_changeset(%{"body" => body}) |> Repo.update()
        else
          {:error, :unauthorized}
        end
    end
  end

  @doc "Delete a reply if the caller's scope owns it. See `update_comment/3` for ownership rules."
  def delete_reply(%Scope{} = scope, reply_id) do
    case Repo.get(Comment, reply_id) do
      nil ->
        {:error, :not_found}

      %Comment{parent_id: nil} ->
        {:error, :not_found}

      %Comment{} = reply ->
        if comment_owned_by?(scope, reply) do
          Repo.delete(reply)
        else
          {:error, :unauthorized}
        end
    end
  end

  @doc """
  Serialize a comment to the API JSON shape.

  `author_display_name` is resolved: when `user_id` is set and the `:user`
  association is loaded, the joined `users.name` wins over the stored
  display name (so renames propagate). Otherwise the stored value is used.
  Preload `:user` (and `replies: [:user]`) to avoid N+1 — done by default
  in `get_by_token/1` and `list_comments/1`.
  """
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
      author_display_name: resolve_display_name(c),
      user_id: c.user_id,
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
      author_display_name: resolve_display_name(r),
      user_id: r.user_id,
      created_at: DateTime.to_iso8601(r.inserted_at)
    }
  end

  defp resolve_display_name(%Comment{user_id: nil} = c), do: c.author_display_name

  defp resolve_display_name(%Comment{user: %User{name: name}})
       when is_binary(name) and name != "",
       do: name

  defp resolve_display_name(%Comment{} = c), do: c.author_display_name
end
