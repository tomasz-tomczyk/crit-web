defmodule Crit.DeviceCodeCleanerTest do
  use Crit.DataCase, async: false

  alias Crit.{DeviceCodeCleaner, DeviceCodes, DeviceCode, Repo}

  setup do
    Application.put_env(:crit, :device_code_cleaner_interval_ms, :timer.hours(24))

    on_exit(fn ->
      Application.delete_env(:crit, :device_code_cleaner_interval_ms)
    end)

    :ok
  end

  defp run_cleaner(pid) do
    send(pid, :run)
    :sys.get_state(pid)
    :ok
  end

  test "handles multiple cleanup runs" do
    {:ok, %{record: record}} = DeviceCodes.create_device_code()

    pid = start_supervised!({DeviceCodeCleaner, []})
    run_cleaner(pid)

    # Fresh record — still present
    assert Repo.get(DeviceCode, record.id)

    # Now expire it and trigger another run.
    record
    |> Ecto.Changeset.change(
      expires_at: DateTime.utc_now() |> DateTime.add(-1, :second) |> DateTime.truncate(:second)
    )
    |> Repo.update!()

    run_cleaner(pid)

    assert is_nil(Repo.get(DeviceCode, record.id))
  end
end
