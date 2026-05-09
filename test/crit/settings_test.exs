defmodule Crit.SettingsTest do
  use Crit.DataCase, async: true

  alias Crit.Settings

  describe "get/0" do
    test "returns the seeded singleton row" do
      setting = Settings.get()
      assert setting.id == 1
      assert is_integer(setting.max_document_bytes)
      assert is_integer(setting.max_comments_per_review)
      assert is_integer(setting.max_comment_body_bytes)
    end
  end

  describe "update/1" do
    test "happy path" do
      {:ok, updated} =
        Settings.update(%{
          max_document_bytes: 1_000_000,
          max_comments_per_review: 100,
          max_comment_body_bytes: 2_000
        })

      assert updated.id == 1
      assert updated.max_document_bytes == 1_000_000
      assert Settings.get().max_comments_per_review == 100
    end

    test "rejects negative numbers" do
      original = Settings.get()

      assert {:error, changeset} = Settings.update(%{max_document_bytes: -1})
      refute changeset.valid?
      assert {_msg, _} = changeset.errors[:max_document_bytes]

      assert Settings.get().max_document_bytes == original.max_document_bytes
    end
  end

  describe "singleton invariant" do
    test "the CHECK constraint refuses inserts with id != 1" do
      assert_raise Ecto.ConstraintError, ~r/singleton/, fn ->
        Crit.Repo.insert!(%Crit.Setting{
          id: 2,
          max_document_bytes: 1,
          max_comments_per_review: 1,
          max_comment_body_bytes: 1
        })
      end
    end
  end
end
