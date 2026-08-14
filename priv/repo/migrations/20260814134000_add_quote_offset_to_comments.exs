defmodule Crit.Repo.Migrations.AddQuoteOffsetToComments do
  use Ecto.Migration

  def change do
    alter table(:comments) do
      add :quote_offset, :integer
    end
  end
end
