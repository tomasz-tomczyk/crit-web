defmodule Crit.Repo.Migrations.AddReviewTypeToReviews do
  use Ecto.Migration

  def change do
    alter table(:reviews) do
      add :review_type, :string, null: false, default: "files"
    end
  end
end
