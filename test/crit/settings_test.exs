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
    test "MB/KB virtual fields write the underlying byte columns" do
      {:ok, updated} =
        Settings.update(%{
          "max_document_mb" => 5,
          "max_comments_per_review" => 100,
          "max_comment_body_kb" => 50
        })

      assert updated.id == 1
      assert updated.max_document_bytes == 5 * 1_048_576
      assert updated.max_comments_per_review == 100
      assert updated.max_comment_body_bytes == 50 * 1024
    end

    test "fractional MB rounds to bytes" do
      {:ok, updated} =
        Settings.update(%{
          "max_document_mb" => 1.5,
          "max_comments_per_review" => 100,
          "max_comment_body_kb" => 50
        })

      assert updated.max_document_bytes == round(1.5 * 1_048_576)
    end

    test "rejects zero" do
      original = Settings.get()

      assert {:error, changeset} =
               Settings.update(%{
                 "max_document_mb" => 0,
                 "max_comments_per_review" => 100,
                 "max_comment_body_kb" => 50
               })

      refute changeset.valid?
      assert {_msg, _} = changeset.errors[:max_document_mb]
      assert Settings.get().max_document_bytes == original.max_document_bytes
    end

    test "rejects negative numbers" do
      assert {:error, changeset} =
               Settings.update(%{
                 "max_document_mb" => 10,
                 "max_comments_per_review" => 100,
                 "max_comment_body_kb" => -1
               })

      refute changeset.valid?
      assert {_msg, _} = changeset.errors[:max_comment_body_kb]
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
