defmodule Crit.Settings do
  @moduledoc """
  Context for the singleton instance settings row.

  Reads happen on every consumer call — single-row Postgres lookup is sub-ms.
  Caching is a future optimisation if profiles show contention.
  """

  alias Crit.{Repo, Setting}

  @singleton_id 1

  @doc """
  Returns the singleton settings row. Raises if missing — the migration
  seeds id=1 so this should never fail in a normally-migrated DB.
  """
  def get do
    Repo.get!(Setting, @singleton_id)
  end

  @doc """
  Updates the singleton settings row.

  Returns `{:ok, setting}` or `{:error, changeset}`.
  """
  def update(attrs) do
    get()
    |> Setting.changeset(attrs)
    |> Repo.update()
  end

  @doc "Changeset for forms (no DB write)."
  def change(setting \\ get(), attrs \\ %{}) do
    Setting.changeset(setting, attrs)
  end
end
