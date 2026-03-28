defmodule Crit.Repo.Migrations.AddUserIdIndexToReviews do
  use Ecto.Migration

  def change do
    create index(:reviews, [:user_id])
  end
end
