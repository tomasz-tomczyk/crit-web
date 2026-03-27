defmodule Crit.Repo.Migrations.AddUserIdIndexToUserApiTokens do
  use Ecto.Migration

  def change do
    create index(:user_api_tokens, [:user_id])
  end
end
