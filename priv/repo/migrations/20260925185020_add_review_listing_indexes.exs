defmodule Crit.Repo.Migrations.AddReviewListingIndexes do
  use Ecto.Migration

  # Back the GET /api/reviews cursor order (inserted_at desc, id desc) for the
  # per-user and per-org listings. The single-column user_id and
  # organization_id indexes are leading prefixes of these, so drop them.
  def up do
    create index(:reviews, [:user_id, "inserted_at DESC", "id DESC"])
    create index(:reviews, [:organization_id, "inserted_at DESC", "id DESC"])

    drop index(:reviews, [:user_id])
    drop index(:reviews, [:organization_id])
  end

  def down do
    create index(:reviews, [:user_id])
    create index(:reviews, [:organization_id])

    drop index(:reviews, [:user_id, "inserted_at DESC", "id DESC"])
    drop index(:reviews, [:organization_id, "inserted_at DESC", "id DESC"])
  end
end
