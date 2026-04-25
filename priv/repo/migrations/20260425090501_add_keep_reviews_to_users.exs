defmodule Crit.Repo.Migrations.AddKeepReviewsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :keep_reviews, :boolean, default: false, null: false
    end
  end
end
