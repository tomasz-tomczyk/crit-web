defmodule Crit.ReviewCleanerTest do
  use Crit.DataCase, async: false

  import Ecto.Query
  import Crit.ReviewsFixtures

  alias Crit.{ReviewCleaner, Review, Repo}

  setup do
    Application.put_env(:crit, :review_cleaner_interval_ms, :timer.hours(24))

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

  defp run_cleaner(pid) do
    send(pid, :run)
    :sys.get_state(pid)
    :ok
  end

  test "does not delete reviews in self-hosted mode" do
    review = review_fixture()
    set_last_activity(review, 31)

    Application.put_env(:crit, :selfhosted, true)
    pid = start_supervised!({ReviewCleaner, []})
    run_cleaner(pid)

    assert Repo.get(Review, review.id)
  end

  test "handles multiple cleanup runs" do
    r1 = review_fixture()

    pid = start_supervised!({ReviewCleaner, []})
    run_cleaner(pid)

    # r1 was recent — still present
    assert Repo.get(Review, r1.id)

    # Now make it stale and trigger another run.
    set_last_activity(r1, 31)
    run_cleaner(pid)

    assert is_nil(Repo.get(Review, r1.id))
  end
end
