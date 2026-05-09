defmodule Crit.Authorization do
  @moduledoc """
  Authorization for instance-role actions.

  `ADMIN_EMAILS` (parsed in `config/runtime.exs` into `:crit, :admin_emails`)
  is the single source of truth for who is an admin. The `users.role` column
  is a denormalised cache — kept in sync by `Crit.Accounts.apply_role_for_email/1`
  on every login, registration, and app boot reconciliation.

  `can?/2,3` and `admin?/1` accept a `%Scope{}`. Templates pass
  `@current_scope` directly — no need to dig out `.user`.
  """

  alias Crit.Accounts.Scope

  @doc "True if the scope's user has the instance admin role."
  defdelegate admin?(scope), to: Scope

  @doc """
  Permission check. `action` is one of:

    * `:delete_review`   — admin or review owner
    * `:delete_comment`  — admin or comment author
    * `:manage_users`    — admin
    * `:edit_settings`   — admin
    * `:delete_user`     — admin
  """
  def can?(scope, action, resource \\ nil)

  def can?(%Scope{} = scope, :manage_users, _), do: admin?(scope)
  def can?(%Scope{} = scope, :edit_settings, _), do: admin?(scope)

  def can?(%Scope{user: %{id: user_id}} = scope, :delete_review, %{user_id: owner_id}) do
    admin?(scope) or user_id == owner_id
  end

  def can?(%Scope{} = scope, :delete_review, _), do: admin?(scope)

  def can?(%Scope{user: %{id: user_id}} = scope, :delete_comment, %{user_id: author_id}) do
    admin?(scope) or user_id == author_id
  end

  def can?(%Scope{} = scope, :delete_comment, _), do: admin?(scope)

  def can?(%Scope{} = scope, :delete_user, %Crit.User{}), do: admin?(scope)

  def can?(_, _, _), do: false
end
