defmodule Crit.Reviews.InactiveCleanupWorkerTest do
  use Crit.DataCase, async: false
  use Oban.Testing, repo: Crit.Repo

  import Ecto.Query
  import Crit.ReviewsFixtures

  alias Crit.{Review, Repo}
  alias Crit.Reviews.InactiveCleanupWorker

  setup do
    on_exit(fn -> Application.delete_env(:crit, :selfhosted) end)
    :ok
  end

  defp set_last_activity(review, days_ago) do
    old_time = DateTime.add(DateTime.utc_now(), -days_ago, :day)

    Repo.update_all(
      from(r in Review, where: r.id == ^review.id),
      set: [last_activity_at: old_time]
    )
  end

  test "deletes reviews inactive for more than 30 days" do
    stale = review_fixture()
    recent = review_fixture()
    set_last_activity(stale, 31)
    set_last_activity(recent, 29)

    assert :ok = perform_job(InactiveCleanupWorker, %{})

    assert is_nil(Repo.get(Review, stale.id))
    assert Repo.get(Review, recent.id)
  end

  test "does not delete reviews in self-hosted mode" do
    review = review_fixture()
    set_last_activity(review, 31)
    Application.put_env(:crit, :selfhosted, true)

    assert :ok = perform_job(InactiveCleanupWorker, %{})

    assert Repo.get(Review, review.id)
  end

  test "is scheduled daily by the Oban cron plugin" do
    oban = "config/config.exs" |> Config.Reader.read!(env: :prod) |> get_in([:crit, Oban])

    {Oban.Plugins.Cron, cron_opts} =
      Enum.find(oban[:plugins], &match?({Oban.Plugins.Cron, _}, &1))

    assert {expr, InactiveCleanupWorker} =
             Enum.find(cron_opts[:crontab], &match?({_, InactiveCleanupWorker}, &1))

    assert {:ok, %Oban.Cron.Expression{}} = Oban.Cron.Expression.parse(expr)
    assert oban[:queues][:maintenance]
  end
end
