defmodule Crit.Repo.Migrations.AddAnchorCommentIdToComments do
  use Ecto.Migration

  # A sub-thread is a root comment on a passage of another message of the
  # review, deleted with it.
  def change do
    alter table(:comments) do
      add :anchor_comment_id, references(:comments, type: :binary_id, on_delete: :delete_all)
    end

    create index(:comments, [:anchor_comment_id])
  end
end
