defmodule Crit.Repo.Migrations.AddAdminRoleAndSettings do
  use Ecto.Migration

  def change do
    # ---- users.role ---------------------------------------------------------
    # `keep_reviews` is intentionally NOT dropped here — it remains relevant
    # for the hosted instance's 30-day-inactivity cleanup (see
    # `Crit.Reviews.delete_inactive/1`). It is unrelated to account deletion,
    # which is a hard cascade regardless of `keep_reviews`.
    alter table(:users) do
      add :role, :string, null: false, default: "user"
    end

    create constraint(:users, :role_must_be_valid, check: "role IN ('admin', 'user')")

    # ---- settings table -----------------------------------------------------
    create table(:settings, primary_key: false) do
      add :id, :integer, primary_key: true
      add :max_document_bytes, :integer, null: false, default: 10_485_760
      add :max_comments_per_review, :integer, null: false, default: 500
      add :max_comment_body_bytes, :integer, null: false, default: 51_200
      timestamps(type: :utc_datetime)
    end

    # Singleton: the settings table is intended to hold exactly one row,
    # which represents this instance's configuration. The CHECK constraint
    # `id = 1` means Postgres rejects any INSERT with a different id, so it's
    # impossible to end up with two settings rows by accident. We seed id=1
    # below and from then on every read/write targets `id = 1`.
    create constraint(:settings, :singleton, check: "id = 1")

    execute(
      "INSERT INTO settings (id, inserted_at, updated_at) VALUES (1, NOW(), NOW())",
      "DELETE FROM settings WHERE id = 1"
    )

    # ---- flip reviews.user_id and comments.user_id to delete_all ------------
    # Existing FK names follow Ecto's default `<table>_<col>_fkey`. We drop
    # the existing constraints, then re-add fresh ones with `on_delete:
    # :delete_all`. `execute/2` is used (rather than `modify ... from:`) to
    # avoid Ecto trying to drop the constraint a second time.
    drop constraint(:reviews, "reviews_user_id_fkey")

    execute(
      "ALTER TABLE reviews ADD CONSTRAINT reviews_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE",
      "ALTER TABLE reviews ADD CONSTRAINT reviews_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL"
    )

    drop constraint(:comments, "comments_user_id_fkey")

    execute(
      "ALTER TABLE comments ADD CONSTRAINT comments_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE",
      "ALTER TABLE comments ADD CONSTRAINT comments_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL"
    )
  end
end
