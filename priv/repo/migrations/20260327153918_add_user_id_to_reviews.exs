defmodule Crit.Repo.Migrations.AddUserIdToReviews do
  use Ecto.Migration

  def change do
    alter table(:reviews) do
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all), null: true
    end
  end
end
