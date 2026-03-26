defmodule Crit.Repo.Migrations.AddShareSync do
  use Ecto.Migration

  def up do
    alter table(:comments) do
      add :external_id, :string, size: 255
    end

    create index(:comments, [:external_id])

    create table(:review_round_snapshots, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :review_id, references(:reviews, type: :binary_id, on_delete: :delete_all), null: false
      add :round_number, :integer, null: false, default: 1
      add :file_path, :string, size: 500, null: false
      add :content, :text, null: false
      add :position, :integer, null: false, default: 0
      timestamps(updated_at: false)
    end

    create index(:review_round_snapshots, [:review_id, :round_number])

    execute """
    INSERT INTO review_round_snapshots (id, review_id, round_number, file_path, content, position, inserted_at)
    SELECT gen_random_uuid(), review_id, 1, file_path, content, position, inserted_at
    FROM review_files
    """

    drop table(:review_files)
  end

  def down do
    create table(:review_files, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :review_id, references(:reviews, type: :binary_id, on_delete: :delete_all), null: false
      add :file_path, :string, size: 500, null: false
      add :content, :text, null: false
      add :position, :integer, null: false, default: 0
      timestamps()
    end

    execute """
    INSERT INTO review_files (id, review_id, file_path, content, position, inserted_at, updated_at)
    SELECT gen_random_uuid(), review_id, file_path, content, position, inserted_at, inserted_at
    FROM review_round_snapshots WHERE round_number = 1
    """

    drop table(:review_round_snapshots)

    alter table(:comments) do
      remove :external_id
    end
  end
end
