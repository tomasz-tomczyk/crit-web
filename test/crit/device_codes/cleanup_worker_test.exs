defmodule Crit.DeviceCodes.CleanupWorkerTest do
  use Crit.DataCase, async: false
  use Oban.Testing, repo: Crit.Repo

  alias Crit.{DeviceCode, DeviceCodes, Repo}
  alias Crit.DeviceCodes.CleanupWorker

  setup do
    on_exit(fn -> Application.delete_env(:crit, :selfhosted) end)
    :ok
  end

  defp expire(record) do
    record
    |> Ecto.Changeset.change(
      expires_at: DateTime.utc_now() |> DateTime.add(-1, :second) |> DateTime.truncate(:second)
    )
    |> Repo.update!()
  end

  test "deletes expired device codes and keeps fresh ones" do
    {:ok, %{record: expired}} = DeviceCodes.create_device_code()
    {:ok, %{record: fresh}} = DeviceCodes.create_device_code()
    expire(expired)

    assert :ok = perform_job(CleanupWorker, %{})

    assert is_nil(Repo.get(DeviceCode, expired.id))
    assert Repo.get(DeviceCode, fresh.id)
  end

  test "still deletes expired device codes in self-hosted mode" do
    {:ok, %{record: record}} = DeviceCodes.create_device_code()
    expire(record)
    Application.put_env(:crit, :selfhosted, true)

    assert :ok = perform_job(CleanupWorker, %{})

    assert is_nil(Repo.get(DeviceCode, record.id))
  end

  test "is scheduled daily by the Oban cron plugin" do
    oban =
      Path.expand("../../../config/config.exs", __DIR__)
      |> Config.Reader.read!(env: :prod)
      |> get_in([:crit, Oban])

    {Oban.Plugins.Cron, cron_opts} =
      Enum.find(oban[:plugins], &match?({Oban.Plugins.Cron, _}, &1))

    assert {expr, CleanupWorker} =
             Enum.find(cron_opts[:crontab], &match?({_, CleanupWorker}, &1))

    assert {:ok, %Oban.Cron.Expression{}} = Oban.Cron.Expression.parse(expr)
    assert Keyword.has_key?(oban[:queues], CleanupWorker.__opts__()[:queue])
  end
end
