defmodule Crit.Repo.Migrations.ReplaceUserCodeWithSessionCode do
  use Ecto.Migration

  def change do
    # Existing device codes have no session_code; they are short-lived
    # (15 min expiry) so safe to drop before altering the schema.
    execute "DELETE FROM device_codes", ""

    alter table(:device_codes) do
      remove :user_code, :string, null: false
      add :session_code, :string, null: false
    end

    drop_if_exists index(:device_codes, [:user_code],
                     where: "status = 'pending'",
                     name: :device_codes_user_code_pending_index
                   )

    create unique_index(:device_codes, [:session_code],
             where: "status = 'pending'",
             name: :device_codes_session_code_pending_index
           )
  end
end
