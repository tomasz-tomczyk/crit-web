defmodule Crit.Repo.Migrations.AddReviewListingIndexes do
  use Ecto.Migration

  # Back the GET /api/reviews cursor order (inserted_at desc, id desc) for the
  # per-user and per-org listings.
  def change do
    create index(:reviews, [:user_id, "inserted_at DESC", "id DESC"])
    create index(:reviews, [:organization_id, "inserted_at DESC", "id DESC"])
  end
end
