defmodule Crit.Repo.Migrations.CreateStatistics do
  use Ecto.Migration

  def up do
    create table(:statistics, primary_key: false) do
      add :date, :date, primary_key: true, null: false
      add :reviews_created, :bigint, null: false, default: 0
      add :comments_created, :bigint, null: false, default: 0
      add :files_reviewed, :bigint, null: false, default: 0
      add :lines_reviewed, :bigint, null: false, default: 0
      add :bytes_stored, :bigint, null: false, default: 0
      timestamps()
    end

    execute """
    WITH review_dates AS (
      SELECT inserted_at::date AS date, COUNT(*) AS cnt FROM reviews GROUP BY 1
    ),
    comment_dates AS (
      SELECT inserted_at::date AS date, COUNT(*) AS cnt FROM comments GROUP BY 1
    ),
    file_dates AS (
      SELECT inserted_at::date AS date, COUNT(DISTINCT (review_id, file_path)) AS cnt
      FROM review_round_snapshots GROUP BY 1
    ),
    line_dates AS (
      SELECT inserted_at::date AS date,
        COALESCE(SUM(array_length(string_to_array(content, E'\\n'), 1)), 0) AS cnt
      FROM review_round_snapshots GROUP BY 1
    ),
    byte_dates AS (
      SELECT inserted_at::date AS date, COALESCE(SUM(octet_length(content)), 0) AS cnt
      FROM review_round_snapshots GROUP BY 1
    ),
    all_dates AS (
      SELECT date FROM review_dates
      UNION SELECT date FROM comment_dates
      UNION SELECT date FROM file_dates
    )
    INSERT INTO statistics (date, reviews_created, comments_created, files_reviewed, lines_reviewed, bytes_stored, inserted_at, updated_at)
    SELECT
      d.date,
      COALESCE(r.cnt, 0),
      COALESCE(c.cnt, 0),
      COALESCE(f.cnt, 0),
      COALESCE(l.cnt, 0),
      COALESCE(b.cnt, 0),
      NOW(),
      NOW()
    FROM all_dates d
    LEFT JOIN review_dates r ON r.date = d.date
    LEFT JOIN comment_dates c ON c.date = d.date
    LEFT JOIN file_dates f ON f.date = d.date
    LEFT JOIN line_dates l ON l.date = d.date
    LEFT JOIN byte_dates b ON b.date = d.date
    """
  end

  def down do
    drop table(:statistics)
  end
end
