defmodule Crit.Repo.Migrations.AddLocalAuth do
  use Ecto.Migration

  def up do
    alter table(:users) do
      add :hashed_password, :string
      modify :provider, :string, null: true, from: {:string, null: false}
      modify :provider_uid, :string, null: true, from: {:string, null: false}
    end

    repo = repo()

    duplicates =
      repo.query!("""
        SELECT lower(email) AS e, count(*) AS n
        FROM users
        WHERE email IS NOT NULL
        GROUP BY 1
        HAVING count(*) > 1
      """).rows

    if duplicates != [] do
      rows = Enum.map_join(duplicates, "\n  ", fn [e, n] -> "#{e} (#{n} rows)" end)

      raise """
      Cannot add unique index on users(email): duplicate emails found.

      Resolve before re-running this migration:
        #{rows}
      """
    end

    create unique_index(:users, ["lower(email)"],
             name: :users_email_lower_idx,
             where: "email IS NOT NULL"
           )

    create table(:users_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string
      add :inserted_at, :utc_datetime, null: false
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token])
  end

  def down do
    drop unique_index(:users_tokens, [:context, :token])
    drop index(:users_tokens, [:user_id])
    drop table(:users_tokens)

    drop unique_index(:users, ["lower(email)"], name: :users_email_lower_idx)

    alter table(:users) do
      remove :hashed_password
      modify :provider, :string, null: false, from: {:string, null: true}
      modify :provider_uid, :string, null: false, from: {:string, null: true}
    end
  end
end
