defmodule Crit.Repo.Migrations.CreateDeviceCodes do
  use Ecto.Migration

  def change do
    create table(:device_codes, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :device_code, :string, null: false
      add :user_code, :string, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
      add :status, :string, null: false, default: "pending"
      add :access_token, :string
      add :last_polled_at, :utc_datetime
      add :expires_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:device_codes, [:device_code])

    create unique_index(:device_codes, [:user_code],
             where: "status = 'pending'",
             name: :device_codes_user_code_pending_index
           )
  end
end
