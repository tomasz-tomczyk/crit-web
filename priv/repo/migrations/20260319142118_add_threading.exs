defmodule Crit.Repo.Migrations.AddThreading do
  use Ecto.Migration

  def change do
    alter table(:comments) do
      add :resolved, :boolean, default: false, null: false
      add :parent_id, references(:comments, type: :binary_id, on_delete: :delete_all)
      modify :start_line, :integer, null: true, from: {:integer, null: false}
      modify :end_line, :integer, null: true, from: {:integer, null: false}
    end

    create index(:comments, [:parent_id])
  end
end
