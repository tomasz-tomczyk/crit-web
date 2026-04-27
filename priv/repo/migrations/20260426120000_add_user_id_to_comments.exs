defmodule Crit.Repo.Migrations.AddUserIdToComments do
  use Ecto.Migration

  def change do
    alter table(:comments) do
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all), null: true
    end

    create index(:comments, [:user_id], where: "user_id IS NOT NULL")
  end
end
