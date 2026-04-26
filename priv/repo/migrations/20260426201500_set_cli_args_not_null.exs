defmodule Crit.Repo.Migrations.SetCliArgsNotNull do
  use Ecto.Migration

  def change do
    execute(
      "UPDATE reviews SET cli_args = '{}' WHERE cli_args IS NULL",
      "SELECT 1"
    )

    alter table(:reviews) do
      modify :cli_args, {:array, :string}, default: [], null: false, from: {{:array, :string}, default: [], null: true}
    end
  end
end
