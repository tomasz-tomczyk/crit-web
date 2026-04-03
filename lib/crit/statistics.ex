defmodule Crit.Statistics do
  @moduledoc "Context for reading and incrementing persistent platform statistics."

  import Ecto.Query
  alias Crit.{Repo, Statistic}

  @doc "Returns lifetime totals by summing all daily rows."
  def totals do
    Repo.one(
      from(s in Statistic,
        select: %{
          reviews_created: type(coalesce(sum(s.reviews_created), 0), :integer),
          comments_created: type(coalesce(sum(s.comments_created), 0), :integer),
          files_reviewed: type(coalesce(sum(s.files_reviewed), 0), :integer),
          lines_reviewed: type(coalesce(sum(s.lines_reviewed), 0), :integer),
          bytes_stored: type(coalesce(sum(s.bytes_stored), 0), :integer)
        }
      )
    ) ||
      %{
        reviews_created: 0,
        comments_created: 0,
        files_reviewed: 0,
        lines_reviewed: 0,
        bytes_stored: 0
      }
  end

  @doc "Returns a list of {date, reviews_created} tuples for the last N days."
  def daily_chart(days \\ 30) do
    start_date = Date.utc_today() |> Date.add(-(days - 1))

    counts =
      from(s in Statistic,
        where: s.date >= ^start_date,
        select: {s.date, s.reviews_created}
      )
      |> Repo.all()
      |> Map.new()

    Enum.map(0..(days - 1), fn offset ->
      date = Date.add(start_date, offset)
      {date, Map.get(counts, date, 0)}
    end)
  end

  @doc "Returns the total reviews_created in the last N days."
  def reviews_since(days) do
    start_date = Date.utc_today() |> Date.add(-days)

    Repo.one(
      from(s in Statistic,
        where: s.date > ^start_date,
        select: type(coalesce(sum(s.reviews_created), 0), :integer)
      )
    ) || 0
  end

  @doc """
  Increments counters for a newly created review.
  Upserts today's row — creates it if this is the first event of the day,
  otherwise increments the existing row. No pre-initialization needed.
  """
  def increment_review(file_count, comment_count, bytes, lines) do
    today = Date.utc_today()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.query!(
      """
      INSERT INTO statistics (date, reviews_created, comments_created, files_reviewed, lines_reviewed, bytes_stored, inserted_at, updated_at)
      VALUES ($1, 1, $2, $3, $4, $5, $6, $6)
      ON CONFLICT (date) DO UPDATE SET
        reviews_created = statistics.reviews_created + 1,
        comments_created = statistics.comments_created + $2,
        files_reviewed = statistics.files_reviewed + $3,
        lines_reviewed = statistics.lines_reviewed + $4,
        bytes_stored = statistics.bytes_stored + $5,
        updated_at = $6
      """,
      [today, comment_count, file_count, lines, bytes, now]
    )

    :ok
  end

  @doc """
  Increments content counters (files, bytes, lines) without incrementing reviews_created.
  Used for review upserts — the review already counted as 1 review, but the new
  content throughput is real activity worth tracking.
  """
  def increment_content(file_count, bytes, lines) do
    today = Date.utc_today()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.query!(
      """
      INSERT INTO statistics (date, reviews_created, comments_created, files_reviewed, lines_reviewed, bytes_stored, inserted_at, updated_at)
      VALUES ($1, 0, 0, $2, $3, $4, $5, $5)
      ON CONFLICT (date) DO UPDATE SET
        files_reviewed = statistics.files_reviewed + $2,
        lines_reviewed = statistics.lines_reviewed + $3,
        bytes_stored = statistics.bytes_stored + $4,
        updated_at = $5
      """,
      [today, file_count, lines, bytes, now]
    )

    :ok
  end

  @doc "Increments comments_created by 1 for a comment added on a shared review."
  def increment_comment do
    today = Date.utc_today()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.query!(
      """
      INSERT INTO statistics (date, reviews_created, comments_created, files_reviewed, lines_reviewed, bytes_stored, inserted_at, updated_at)
      VALUES ($1, 0, 1, 0, 0, 0, $2, $2)
      ON CONFLICT (date) DO UPDATE SET
        comments_created = statistics.comments_created + 1,
        updated_at = $2
      """,
      [today, now]
    )

    :ok
  end

  @doc "Returns aggregate stats for the self-hosted dashboard."
  def dashboard_stats do
    totals = totals()
    week_stats = reviews_since(7)

    avg_comments_per_review =
      if totals.reviews_created > 0,
        do: totals.comments_created * 1.0 / totals.reviews_created,
        else: 0.0

    %{
      total_reviews: totals.reviews_created,
      total_comments: totals.comments_created,
      total_files: totals.files_reviewed,
      reviews_this_week: week_stats,
      avg_comments_per_review: avg_comments_per_review,
      total_storage_bytes: totals.bytes_stored
    }
  end

  @doc "Returns a list of {date, count} tuples for the last N days (UTC)."
  def activity_chart(days \\ 30) do
    daily_chart(days)
  end
end
