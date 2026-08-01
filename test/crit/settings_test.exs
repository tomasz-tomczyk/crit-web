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
      assert setting.allowed_comment_policies == [:open, :logged_in_only, :disallowed]
      assert setting.allowed_review_visibilities == [:unlisted, :public, :organization]
    end
  end

  describe "update/1" do
    test "MB/KB virtual fields write the underlying byte columns" do
      {:ok, updated} =
        Settings.update(%{
          "max_document_mb" => 5,
          "max_comments_per_review" => 100,
          "max_comment_body_kb" => 50,
          "allowed_comment_policies" => ["open", "disallowed"],
          "allowed_review_visibilities" => ["unlisted"]
        })

      assert updated.id == 1
      assert updated.max_document_bytes == 5 * 1_048_576
      assert updated.max_comments_per_review == 100
      assert updated.max_comment_body_bytes == 50 * 1024
      assert updated.allowed_comment_policies == [:open, :disallowed]
      assert updated.allowed_review_visibilities == [:unlisted]
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

    test "rejects empty policy allow-lists" do
      assert {:error, changeset} =
               Settings.update(%{
                 "max_document_mb" => 10,
                 "max_comments_per_review" => 100,
                 "max_comment_body_kb" => 50,
                 "allowed_comment_policies" => [],
                 "allowed_review_visibilities" => []
               })

      refute changeset.valid?
      assert {_msg, _} = changeset.errors[:allowed_comment_policies]
      assert {_msg, _} = changeset.errors[:allowed_review_visibilities]
    end

    test "rejects invalid policy values" do
      assert {:error, changeset} =
               Settings.update(%{
                 "max_document_mb" => 10,
                 "max_comments_per_review" => 100,
                 "max_comment_body_kb" => 50,
                 "allowed_comment_policies" => ["open", "bogus"],
                 "allowed_review_visibilities" => ["public"]
               })

      refute changeset.valid?
      assert {_msg, _} = changeset.errors[:allowed_comment_policies]
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

    test "allows zero notification retention to keep terminal records forever" do
      setting = Settings.get()

      assert {:ok, updated} =
               Settings.update(%{
                 max_document_mb: Crit.Setting.bytes_to_mb(setting.max_document_bytes),
                 max_comments_per_review: setting.max_comments_per_review,
                 max_comment_body_kb: Crit.Setting.bytes_to_kb(setting.max_comment_body_bytes),
                 notification_retention_days: 0
               })

      assert updated.notification_retention_days == 0
    end
  end

  describe "singleton invariant" do
    test "the CHECK constraint refuses inserts with id != 1" do
      assert_raise Ecto.ConstraintError, ~r/singleton/, fn ->
        Crit.Repo.insert!(%Crit.Setting{
          id: 2,
          max_document_bytes: 1,
          max_comments_per_review: 1,
          max_comment_body_bytes: 1,
          allowed_comment_policies: [:open],
          allowed_review_visibilities: [:organization]
        })
      end
    end
  end

  describe "share policy helpers" do
    test "choose old defaults when still allowed, otherwise the first allowed value" do
      {:ok, setting} =
        Settings.update(%{
          "max_document_mb" => 10,
          "max_comments_per_review" => 100,
          "max_comment_body_kb" => 50,
          "allowed_comment_policies" => ["logged_in_only", "disallowed"],
          "allowed_review_visibilities" => ["public"]
        })

      assert Settings.default_comment_policy(setting) == :logged_in_only
      assert Settings.default_visibility(setting) == :public
    end

    test "personal default visibility ignores organization-only policy" do
      {:ok, setting} =
        Settings.update(%{
          "max_document_mb" => 10,
          "max_comments_per_review" => 100,
          "max_comment_body_kb" => 50,
          "allowed_comment_policies" => ["open"],
          "allowed_review_visibilities" => ["organization"]
        })

      assert Settings.default_visibility(setting) == nil
    end
  end

  describe "mailer_configured?/0" do
    setup do
      original = Application.get_env(:crit, Crit.Mailer)
      on_exit(fn -> Application.put_env(:crit, Crit.Mailer, original) end)
      :ok
    end

    test "true for Local adapter" do
      Application.put_env(:crit, Crit.Mailer, adapter: Swoosh.Adapters.Local)
      assert Settings.mailer_configured?()
    end

    test "true for Test adapter" do
      Application.put_env(:crit, Crit.Mailer, adapter: Swoosh.Adapters.Test)
      assert Settings.mailer_configured?()
    end

    test "true for SMTP adapter when SMTP_HOST and SMTP_FROM are set" do
      Application.put_env(:crit, Crit.Mailer, adapter: Swoosh.Adapters.SMTP)
      System.put_env("SMTP_HOST", "smtp.example.com")
      System.put_env("SMTP_FROM", "crit@example.com")

      on_exit(fn ->
        System.delete_env("SMTP_HOST")
        System.delete_env("SMTP_FROM")
      end)

      assert Settings.mailer_configured?()
    end

    test "false for SMTP adapter when env vars are missing" do
      Application.put_env(:crit, Crit.Mailer, adapter: Swoosh.Adapters.SMTP)
      System.delete_env("SMTP_HOST")
      System.delete_env("SMTP_FROM")

      refute Settings.mailer_configured?()
    end
  end
end
