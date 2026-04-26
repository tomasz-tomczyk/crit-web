defmodule Crit.Repo.Migrations.AddCliArgsToReviews do
  use Ecto.Migration

  def change do
    alter table(:reviews) do
      add :cli_args, {:array, :string}, default: [], null: false
    end
  end
end
