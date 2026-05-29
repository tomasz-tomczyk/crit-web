defmodule Crit.ReviewRoundSnapshotTest do
  use Crit.DataCase, async: true
  alias Crit.ReviewRoundSnapshot

  test "accepts base64 encoding" do
    cs =
      ReviewRoundSnapshot.changeset(%ReviewRoundSnapshot{}, %{
        round_number: 0,
        file_path: "logo.png",
        content: "AAAA",
        position: 0,
        status: "modified",
        encoding: "base64"
      })

    assert cs.valid?
    assert Ecto.Changeset.get_field(cs, :encoding) == "base64"
  end

  test "rejects unknown encoding" do
    cs =
      ReviewRoundSnapshot.changeset(%ReviewRoundSnapshot{}, %{
        round_number: 0,
        file_path: "a.txt",
        content: "x",
        position: 0,
        status: "modified",
        encoding: "rot13"
      })

    refute cs.valid?
  end
end
