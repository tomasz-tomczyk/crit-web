defmodule Crit.Repo.Migrations.AddScopeToComments do
  use Ecto.Migration

  def change do
    alter table(:comments) do
      add :scope, :string, default: "line"
      modify :start_line, :integer, null: true, default: nil
      modify :end_line, :integer, null: true, default: nil
    end
  end
end
