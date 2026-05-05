defmodule Crit.Repo.Migrations.NormalizeReviewRoundSnapshotStatus do
  use Ecto.Migration

  # The schema enum is being narrowed from
  # [:added, :modified, :deleted, :renamed, :removed] to [:modified, :removed].
  # Files-mode share (the only producer) only ever emits "modified" or "removed",
  # so this is a defensive backfill — any rogue values get folded to "modified".
  def up do
    execute("""
    UPDATE review_round_snapshots
       SET status = 'modified'
     WHERE status NOT IN ('modified', 'removed')
    """)
  end

  def down do
    :ok
  end
end
