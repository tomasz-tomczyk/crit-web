defmodule Crit.Repo.Migrations.AddVisibilityToReviews do
  use Ecto.Migration

  def change do
    alter table(:reviews) do
      add :visibility, :string, null: false, default: "unlisted"
    end

    create index(:reviews, [:visibility],
             where: "visibility = 'public'",
             name: :reviews_public_visibility_index
           )
  end
end
