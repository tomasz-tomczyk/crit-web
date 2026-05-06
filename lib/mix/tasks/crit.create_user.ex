defmodule Mix.Tasks.Crit.CreateUser do
  @moduledoc """
  Creates a local-auth user from the shell.

      mix crit.create_user EMAIL PASSWORD

  Useful for bootstrap and recovery from a locked-out admin (combined with
  `ADMIN_EMAILS` once the admin-role feature ships).
  """
  @shortdoc "Create a local-auth user"

  use Mix.Task

  @impl Mix.Task
  def run([email, password]) do
    Mix.Task.run("app.start")

    case Crit.Accounts.register_user(%{email: email, password: password}) do
      {:ok, user} ->
        Mix.shell().info("Created user #{user.email} (id #{user.id})")

      {:error, changeset} ->
        Mix.raise("Failed to create user: #{inspect(changeset.errors)}")
    end
  end

  def run(_args) do
    Mix.raise("Usage: mix crit.create_user EMAIL PASSWORD")
  end
end
