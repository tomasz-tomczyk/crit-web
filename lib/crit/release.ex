defmodule Crit.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :crit

  import Ecto.Query, only: [from: 2]

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    # Reconcile ADMIN_EMAILS → users.role on every boot, not just when
    # migrations are pending. The operator's normal "edit env, restart
    # container" loop should apply the new admin set without anyone having
    # to log in.
    reconcile_admin_emails()
  end

  @doc """
  Reconciles `users.role` against the parsed `ADMIN_EMAILS` list. Promotes
  users whose email is now listed; demotes users whose email is no longer
  listed. Idempotent. Two `update_all` queries.
  """
  def reconcile_admin_emails do
    emails = Application.get_env(:crit, :admin_emails, [])
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, _, _} =
      Ecto.Migrator.with_repo(Crit.Repo, fn _repo ->
        # Promote env-listed users to admin.
        if emails != [] do
          from(u in Crit.User,
            where: fragment("lower(?)", u.email) in ^emails and u.role != ^:admin,
            update: [set: [role: ^:admin, updated_at: ^now]]
          )
          |> Crit.Repo.update_all([])
        end

        # Demote any admin whose email is no longer listed.
        if emails != [] do
          from(u in Crit.User,
            where: u.role == ^:admin and fragment("lower(?)", u.email) not in ^emails,
            update: [set: [role: ^:user, updated_at: ^now]]
          )
          |> Crit.Repo.update_all([])
        end
      end)

    :ok
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
