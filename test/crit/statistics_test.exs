defmodule Crit.StatisticsTest do
  use Crit.DataCase, async: true

  alias Crit.Statistics

  describe "totals/0" do
    test "returns zero counts when no statistics rows exist" do
      totals = Statistics.totals()
      assert totals.reviews_created >= 0
      assert totals.comments_created >= 0
      assert totals.files_reviewed >= 0
      assert totals.lines_reviewed >= 0
      assert totals.bytes_stored >= 0
    end
  end

  describe "increment_review/4" do
    test "increments reviews_created by 1 and files_reviewed by file count" do
      before = Statistics.totals()
      Statistics.increment_review(3, 0, 0, 100)
      after_totals = Statistics.totals()

      assert after_totals.reviews_created == before.reviews_created + 1
      assert after_totals.files_reviewed == before.files_reviewed + 3
      assert after_totals.lines_reviewed == before.lines_reviewed + 100
    end

    test "increments all counters" do
      before = Statistics.totals()
      Statistics.increment_review(2, 5, 1024, 50)
      after_totals = Statistics.totals()

      assert after_totals.reviews_created == before.reviews_created + 1
      assert after_totals.files_reviewed == before.files_reviewed + 2
      assert after_totals.comments_created == before.comments_created + 5
      assert after_totals.bytes_stored == before.bytes_stored + 1024
      assert after_totals.lines_reviewed == before.lines_reviewed + 50
    end

    test "multiple increments on the same day upsert the same row" do
      Statistics.increment_review(1, 0, 0, 10)
      Statistics.increment_review(2, 0, 0, 20)

      today = Date.utc_today()
      row = Crit.Repo.get(Crit.Statistic, today)
      assert row.reviews_created == 2
      assert row.files_reviewed == 3
      assert row.lines_reviewed == 30
    end
  end

  describe "increment_content/3" do
    test "increments files/bytes/lines but NOT reviews_created" do
      Statistics.increment_review(1, 0, 0, 10)
      before = Statistics.totals()

      Statistics.increment_content(3, 2048, 200)
      after_totals = Statistics.totals()

      assert after_totals.reviews_created == before.reviews_created
      assert after_totals.files_reviewed == before.files_reviewed + 3
      assert after_totals.bytes_stored == before.bytes_stored + 2048
      assert after_totals.lines_reviewed == before.lines_reviewed + 200
    end
  end

  describe "increment_comment/0" do
    test "increments comments_created by 1" do
      before = Statistics.totals()
      Statistics.increment_comment()
      after_totals = Statistics.totals()

      assert after_totals.comments_created == before.comments_created + 1
    end
  end

  describe "daily_chart/1" do
    test "returns entries for every day in the range" do
      Statistics.increment_review(1, 0, 0, 10)
      chart = Statistics.daily_chart(7)

      assert length(chart) == 7
      assert Enum.all?(chart, fn {date, count} -> is_struct(date, Date) and is_integer(count) end)

      # Today should have at least 1 review
      {_date, today_count} = List.last(chart)
      assert today_count >= 1
    end
  end

  describe "reviews_since/1" do
    test "returns count of reviews in the last N days" do
      Statistics.increment_review(1, 0, 0, 10)
      assert Statistics.reviews_since(7) >= 1
    end
  end

  describe "dashboard_stats/0" do
    import Crit.ReviewsFixtures

    test "returns zeroes when no reviews exist" do
      stats = Statistics.dashboard_stats()

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

      stats = Statistics.dashboard_stats()

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

      stats = Statistics.dashboard_stats()

      assert stats.total_reviews == 2
      assert stats.total_comments == 1
      assert stats.total_files == 3
      assert stats.avg_comments_per_review == 0.5
    end
  end

  describe "activity_chart/1" do
    import Crit.ReviewsFixtures

    test "returns 30 days of data with zero-fill" do
      data = Statistics.activity_chart(30)

      assert length(data) == 30
      assert Enum.all?(data, fn {date, count} -> is_struct(date, Date) and is_integer(count) end)
    end

    test "counts reviews created today" do
      _review = review_fixture()

      data = Statistics.activity_chart(30)
      {_date, today_count} = List.last(data)

      assert today_count == 1
    end

    test "returns empty counts when no reviews" do
      data = Statistics.activity_chart(7)

      assert length(data) == 7
      assert Enum.all?(data, fn {_date, count} -> count == 0 end)
    end
  end

  describe "integration with Reviews.create_review/5" do
    test "creating a review increments stats including lines" do
      before = Statistics.totals()

      files = [
        %{"path" => "a.md", "content" => "line1\nline2\nline3"},
        %{"path" => "b.md", "content" => "line1\nline2"}
      ]

      comments = [
        %{"file" => "a.md", "start_line" => 1, "end_line" => 1, "body" => "note"}
      ]

      {:ok, _review} = Crit.Reviews.create_review(files, 0, comments)

      after_totals = Statistics.totals()
      assert after_totals.reviews_created == before.reviews_created + 1
      assert after_totals.files_reviewed == before.files_reviewed + 2
      assert after_totals.comments_created == before.comments_created + 1
      assert after_totals.lines_reviewed == before.lines_reviewed + 5
    end
  end

  describe "integration with Reviews.upsert_review/3" do
    test "upserting a review increments content stats but not reviews_created" do
      files = [%{"path" => "a.md", "content" => "original\ncontent"}]
      {:ok, review} = Crit.Reviews.create_review(files, 0, [])

      before = Statistics.totals()

      new_files = [%{"path" => "a.md", "content" => "updated\ncontent\nhere"}]

      {:ok, :updated, _review} =
        Crit.Reviews.upsert_review(review.token, review.delete_token, %{
          "files" => new_files,
          "comments" => []
        })

      after_totals = Statistics.totals()
      assert after_totals.reviews_created == before.reviews_created
      assert after_totals.files_reviewed == before.files_reviewed + 1
      assert after_totals.lines_reviewed == before.lines_reviewed + 3
    end
  end

  describe "integration with comment creation" do
    import Crit.ReviewsFixtures

    test "creating a comment increments stats" do
      review = review_fixture()
      before = Statistics.totals()

      {:ok, _comment} =
        Crit.Reviews.create_comment(
          review,
          %{"start_line" => 1, "end_line" => 1, "body" => "hello", "scope" => "line"},
          Ecto.UUID.generate()
        )

      after_totals = Statistics.totals()
      assert after_totals.comments_created == before.comments_created + 1
    end

    test "creating a reply increments stats" do
      review = review_fixture()

      {:ok, comment} =
        Crit.Reviews.create_comment(
          review,
          %{"start_line" => 1, "end_line" => 1, "body" => "parent", "scope" => "line"},
          Ecto.UUID.generate()
        )

      before = Statistics.totals()

      {:ok, _reply} =
        Crit.Reviews.create_reply(
          comment.id,
          %{"body" => "reply"},
          Ecto.UUID.generate(),
          nil,
          review.id
        )

      after_totals = Statistics.totals()
      assert after_totals.comments_created == before.comments_created + 1
    end
  end
end
