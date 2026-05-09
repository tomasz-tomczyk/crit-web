defmodule Crit.Authorization do
  @moduledoc """
  Authorization for instance-role actions.

  `ADMIN_EMAILS` (parsed in `config/runtime.exs` into `:crit, :admin_emails`)
  is the single source of truth for who is an admin. The `users.role` column
  is a denormalised cache — kept in sync by `Crit.Accounts.apply_role_for_email/1`
  on every login, registration, and app boot reconciliation.

  All callers should use `can?/2,3` rather than reading `user.role` directly,
  so the env-pinned protection on `:delete_user` is enforced uniformly.
  """

  alias Crit.User

  @doc "True if the user has the instance admin role."
  def admin?(%User{role: :admin}), do: true
  def admin?(_), do: false

  @doc """
  True if the user's email is pinned in `ADMIN_EMAILS`. Pinned admins cannot
  be deleted via the admin UI — deleting them would just have them re-promoted
  on next login or boot reconciliation.
  """
  def env_pinned?(%User{email: email}) when is_binary(email) do
    String.downcase(email) in admin_emails()
  end

  def env_pinned?(_), do: false

  @doc """
  Permission check. `action` is one of:

    * `:delete_review`   — admin or review owner
    * `:delete_comment`  — admin or comment author
    * `:manage_users`    — admin
    * `:edit_settings`   — admin
    * `:delete_user`     — admin AND target's email is not pinned in ADMIN_EMAILS
  """
  def can?(user, action, resource \\ nil)

  def can?(%User{} = user, :manage_users, _), do: admin?(user)
  def can?(%User{} = user, :edit_settings, _), do: admin?(user)

  def can?(%User{} = user, :delete_review, %{user_id: owner_id}) do
    admin?(user) or (is_binary(user.id) and user.id == owner_id)
  end

  def can?(%User{} = user, :delete_review, _), do: admin?(user)

  def can?(%User{} = user, :delete_comment, %{user_id: author_id}) do
    admin?(user) or (is_binary(user.id) and user.id == author_id)
  end

  def can?(%User{} = user, :delete_comment, _), do: admin?(user)

  def can?(%User{} = user, :delete_user, %User{} = target) do
    admin?(user) and not env_pinned?(target)
  end

  def can?(_, _, _), do: false

  defp admin_emails do
    Application.get_env(:crit, :admin_emails, [])
  end
end
