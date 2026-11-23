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

  describe "lang and file_type" do
    @base %{round_number: 0, file_path: "a.conf", content: "x", position: 0}

    test "accepts a known file_type and a short lang" do
      cs =
        ReviewRoundSnapshot.changeset(
          %ReviewRoundSnapshot{},
          Map.merge(@base, %{lang: "nginx", file_type: "markdown"})
        )

      assert cs.valid?
      assert Ecto.Changeset.get_field(cs, :lang) == "nginx"
      assert Ecto.Changeset.get_field(cs, :file_type) == "markdown"
    end

    test "rejects an unknown file_type" do
      cs =
        ReviewRoundSnapshot.changeset(%ReviewRoundSnapshot{}, Map.put(@base, :file_type, "html"))

      refute cs.valid?
    end

    test "rejects a lang over 64 characters" do
      cs =
        ReviewRoundSnapshot.changeset(
          %ReviewRoundSnapshot{},
          Map.put(@base, :lang, String.duplicate("a", 65))
        )

      refute cs.valid?
    end
  end
end
