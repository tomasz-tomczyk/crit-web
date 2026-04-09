defmodule Crit.DeviceCodeCleanerTest do
  use Crit.DataCase, async: false

  alias Crit.{DeviceCodeCleaner, DeviceCodes, DeviceCode, Repo}

  setup do
    Application.put_env(:crit, :device_code_cleaner_interval_ms, 10)

    on_exit(fn ->
      Application.delete_env(:crit, :device_code_cleaner_interval_ms)
    end)

    :ok
  end

  test "deletes expired device codes after the configured interval" do
    {:ok, %{record: record}} = DeviceCodes.create_device_code()

    record
    |> Ecto.Changeset.change(
      expires_at: DateTime.utc_now() |> DateTime.add(-1, :second) |> DateTime.truncate(:second)
    )
    |> Repo.update!()

    start_supervised!({DeviceCodeCleaner, []})
    Process.sleep(50)

    assert is_nil(Repo.get(DeviceCode, record.id))
  end

  test "does not delete fresh pending device codes" do
    {:ok, %{record: record}} = DeviceCodes.create_device_code()

    start_supervised!({DeviceCodeCleaner, []})
    Process.sleep(50)

    assert Repo.get(DeviceCode, record.id)
  end

  test "runs cleanup repeatedly on the interval" do
    {:ok, %{record: record}} = DeviceCodes.create_device_code()

    start_supervised!({DeviceCodeCleaner, []})
    Process.sleep(50)

    # Fresh record — still present
    assert Repo.get(DeviceCode, record.id)

    # Now expire it and wait for the next tick
    record
    |> Ecto.Changeset.change(
      expires_at: DateTime.utc_now() |> DateTime.add(-1, :second) |> DateTime.truncate(:second)
    )
    |> Repo.update!()

    Process.sleep(50)

    assert is_nil(Repo.get(DeviceCode, record.id))
  end
end
