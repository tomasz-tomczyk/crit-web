defmodule Crit.Authorization do
  @moduledoc """
  Authorization for instance-role actions.

  `ADMIN_EMAILS` (parsed in `config/runtime.exs` into `:crit, :admin_emails`)
  is the single source of truth for who is an admin. The `users.role` column
  is a denormalised cache — kept in sync by `Crit.Accounts.apply_role_for_email/1`
  on every login, registration, and app boot reconciliation.

  All callers should use `can?/2,3` rather than reading `user.role` directly.
  """

  alias Crit.User

  @doc "True if the user has the instance admin role."
  def admin?(%User{role: :admin}), do: true
  def admin?(_), do: false

  @doc """
  Permission check. `action` is one of:

    * `:delete_review`   — admin or review owner
    * `:delete_comment`  — admin or comment author
    * `:manage_users`    — admin
    * `:edit_settings`   — admin
    * `:delete_user`     — admin
  """
  def can?(user, action, resource \\ nil)

  def can?(%User{} = user, :manage_users, _), do: admin?(user)
  def can?(%User{} = user, :edit_settings, _), do: admin?(user)

  def can?(%User{} = user, :delete_review, %{user_id: owner_id}) do
    admin?(user) or user.id == owner_id
  end

  def can?(%User{} = user, :delete_review, _), do: admin?(user)

  def can?(%User{} = user, :delete_comment, %{user_id: author_id}) do
    admin?(user) or user.id == author_id
  end

  def can?(%User{} = user, :delete_comment, _), do: admin?(user)

  def can?(%User{} = user, :delete_user, %User{}), do: admin?(user)

  def can?(_, _, _), do: false
end
