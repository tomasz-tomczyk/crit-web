defmodule Crit.Repo.Migrations.UniqueExternalIdPerReview do
  use Ecto.Migration

  def change do
    create unique_index(:comments, [:review_id, :external_id],
             where: "external_id IS NOT NULL",
             name: :comments_review_id_external_id_index
           )
  end
end
