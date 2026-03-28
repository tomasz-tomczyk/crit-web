defmodule Crit.ReviewCleanerTest do
  use Crit.DataCase, async: false

  import Ecto.Query
  import Crit.ReviewsFixtures

  alias Crit.{ReviewCleaner, Review, Repo}

  setup do
    Application.put_env(:crit, :review_cleaner_interval_ms, 10)

    on_exit(fn ->
      Application.delete_env(:crit, :review_cleaner_interval_ms)
      Application.delete_env(:crit, :selfhosted)
    end)

    :ok
  end

  defp set_last_activity(review, days_ago) do
    old_time = DateTime.add(DateTime.utc_now(), -days_ago, :day)

    Repo.update_all(
      from(r in Review, where: r.id == ^review.id),
      set: [last_activity_at: old_time]
    )
  end

  test "deletes inactive reviews after the configured interval" do
    review = review_fixture()
    set_last_activity(review, 31)

    start_supervised!({ReviewCleaner, []})
    Process.sleep(50)

    assert is_nil(Repo.get(Review, review.id))
  end

  test "does not delete active reviews" do
    review = review_fixture()

    start_supervised!({ReviewCleaner, []})
    Process.sleep(50)

    assert Repo.get(Review, review.id)
  end

  test "does not delete reviews in self-hosted mode" do
    review = review_fixture()
    set_last_activity(review, 31)

    Application.put_env(:crit, :selfhosted, true)
    start_supervised!({ReviewCleaner, []})
    Process.sleep(50)

    assert Repo.get(Review, review.id)
  end

  test "runs cleanup repeatedly on the interval" do
    r1 = review_fixture()

    start_supervised!({ReviewCleaner, []})
    Process.sleep(50)

    # r1 was recent — still present
    assert Repo.get(Review, r1.id)

    # Now make it stale and wait for the next tick
    set_last_activity(r1, 31)
    Process.sleep(50)

    assert is_nil(Repo.get(Review, r1.id))
  end
end
