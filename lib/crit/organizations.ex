defmodule Crit.Organizations do
  @moduledoc """
  The Organizations context — manages multi-tenant orgs, memberships, and invites.
  """

  import Ecto.Query

  alias Crit.Repo
  alias Crit.Accounts.Scope
  alias Crit.Organizations.{Organization, OrganizationMembership, OrganizationInvite}
  alias Crit.User

  # ---------------------------------------------------------------------------
  # Orgs
  # ---------------------------------------------------------------------------

  def create_organization(%Scope{user: %User{} = user}, attrs) do
    Repo.transaction(fn ->
      org_cs = Organization.create_changeset(%Organization{}, attrs)

      case Repo.insert(org_cs) do
        {:ok, org} ->
          membership_cs =
            OrganizationMembership.changeset(%OrganizationMembership{}, %{
              organization_id: org.id,
              user_id: user.id,
              role: :admin
            })

          case Repo.insert(membership_cs) do
            {:ok, _membership} -> org
            {:error, cs} -> Repo.rollback(cs)
          end

        {:error, cs} ->
          Repo.rollback(cs)
      end
    end)
  end

  def update_organization(%Scope{} = scope, %Organization{} = org, attrs) do
    with :ok <- check_org_admin(scope),
         :ok <- check_org_matches_scope(scope, org) do
      org
      |> Organization.changeset(attrs)
      |> Repo.update()
    end
  end

  def get_organization(id) do
    case Repo.get(Organization, id) do
      nil -> {:error, :not_found}
      org -> {:ok, org}
    end
  end

  def get_organization_by_slug(slug) do
    case Repo.get_by(Organization, slug: slug) do
      nil -> {:error, :not_found}
      org -> {:ok, org}
    end
  end

  def delete_organization(%Scope{} = scope, %Organization{} = org) do
    with :ok <- check_org_admin(scope),
         :ok <- check_org_matches_scope(scope, org) do
      Repo.delete(org)
    end
  end

  def change_organization(%Organization{} = org, attrs \\ %{}) do
    Organization.changeset(org, attrs)
  end

  @doc """
  List reviews belonging to an organization, with comment/file counts.
  Requires the scope to have the organization attached (i.e., user is a member).
  """
  def list_org_reviews(%Scope{} = scope, %Organization{} = org) do
    if Scope.org_id(scope) == org.id do
      Crit.Reviews.list_org_reviews_with_counts(org.id)
    else
      []
    end
  end

  @doc """
  Paginated variant of `list_org_reviews/2`. Returns `{reviews, total_count}`.
  """
  def list_org_reviews_paginated(%Scope{} = scope, %Organization{} = org, opts) do
    if Scope.org_id(scope) == org.id do
      Crit.Reviews.list_org_reviews_paginated(org.id, opts)
    else
      {[], 0}
    end
  end

  # ---------------------------------------------------------------------------
  # Membership
  # ---------------------------------------------------------------------------

  def list_user_organizations(%Scope{user: %User{} = user}) do
    review_count_subquery =
      from(r in Crit.Review,
        where:
          r.organization_id == parent_as(:org).id and r.visibility in [:organization, :public],
        select: count(r.id)
      )

    from(m in OrganizationMembership,
      where: m.user_id == ^user.id,
      join: o in assoc(m, :organization),
      as: :org,
      left_join: m2 in OrganizationMembership,
      on: m2.organization_id == o.id,
      left_join: u2 in assoc(m2, :user),
      group_by: [o.id, m.id],
      select: %{
        membership: m,
        organization: o,
        member_count: count(m2.id),
        member_names: fragment("array_agg(? ORDER BY ? ASC NULLS LAST)", u2.name, u2.name),
        review_count: subquery(review_count_subquery)
      },
      order_by: [asc: o.name]
    )
    |> Repo.all()
    # Populate virtual fields on Organization — Ecto can't select into virtuals
    # directly, so we map over the joined result and set them from the membership.
    |> Enum.map(fn %{
                     membership: m,
                     organization: org,
                     member_count: count,
                     member_names: names,
                     review_count: rc
                   } ->
      initials =
        (names || [])
        |> Enum.reject(&is_nil/1)
        |> Enum.map(&String.first/1)
        |> Enum.uniq()

      %{org | member_count: count, review_count: rc, role: m.role, member_initials: initials}
    end)
  end

  def list_user_organizations(_scope), do: []

  def list_members(%Scope{} = scope, %Organization{} = org) do
    if Scope.org_id(scope) != org.id, do: raise(ArgumentError, "scope/org mismatch")

    from(m in OrganizationMembership,
      where: m.organization_id == ^org.id,
      join: u in assoc(m, :user),
      preload: [user: u],
      order_by: [asc: u.name, asc: u.email]
    )
    |> Repo.all()
  end

  def get_membership(%Scope{} = _scope, %Organization{} = org, %User{} = user) do
    get_membership_for_user(org.id, user.id)
  end

  def get_membership_for_user(org_id, user_id) do
    case Repo.get_by(OrganizationMembership, organization_id: org_id, user_id: user_id) do
      nil -> {:error, :not_found}
      m -> {:ok, m}
    end
  end

  def update_membership_role(%Scope{} = scope, %OrganizationMembership{} = membership, role) do
    role = to_role_atom(role)

    with :ok <- check_org_admin(scope),
         :ok <- check_membership_in_scope(scope, membership),
         :ok <- check_demote_last_admin(membership, role) do
      membership
      |> OrganizationMembership.changeset(%{role: role})
      |> Repo.update()
    end
  end

  defp check_demote_last_admin(%{role: :admin} = membership, role) when role != :admin do
    count =
      from(m in OrganizationMembership,
        where: m.organization_id == ^membership.organization_id and m.role == :admin
      )
      |> Repo.aggregate(:count)

    if count <= 1, do: {:error, :last_admin}, else: :ok
  end

  defp check_demote_last_admin(_, _), do: :ok

  def remove_member(%Scope{} = scope, %Organization{} = org, %User{} = user) do
    with :ok <- check_org_admin(scope),
         :ok <- check_org_matches_scope(scope, org),
         :ok <- check_not_last_admin(org, user),
         {:ok, membership} <- get_membership_for_user(org.id, user.id) do
      Repo.delete(membership)
    end
  end

  def leave_organization(%Scope{user: %User{} = current_user} = scope, %Organization{} = org) do
    with :ok <- check_not_last_admin(org, current_user),
         {:ok, membership} <- get_membership_for_user(org.id, current_user.id) do
      {:ok, _} = Repo.delete(membership)
      {:ok, scope}
    end
  end

  defp check_not_last_admin(org, user) do
    admin_count =
      from(m in OrganizationMembership,
        where: m.organization_id == ^org.id and m.role == :admin
      )
      |> Repo.aggregate(:count)

    cond do
      admin_count > 1 ->
        :ok

      admin_count == 1 ->
        case Repo.get_by(OrganizationMembership,
               organization_id: org.id,
               user_id: user.id,
               role: :admin
             ) do
          nil -> :ok
          _ -> {:error, :last_admin}
        end

      true ->
        {:error, :last_admin}
    end
  end

  defp check_org_admin(scope) do
    if Scope.org_admin?(scope), do: :ok, else: {:error, :unauthorized}
  end

  defp check_org_matches_scope(%Scope{} = scope, %Organization{id: id}) do
    if Scope.org_id(scope) == id, do: :ok, else: {:error, :unauthorized}
  end

  defp check_membership_in_scope(%Scope{} = scope, %OrganizationMembership{} = m) do
    if m.organization_id == Scope.org_id(scope), do: :ok, else: {:error, :unauthorized}
  end

  # ---------------------------------------------------------------------------
  # Invites
  # ---------------------------------------------------------------------------

  def create_invite(%Scope{user: %User{} = inviter} = scope, %Organization{} = org, attrs) do
    with :ok <- check_org_admin(scope),
         :ok <- check_org_matches_scope(scope, org) do
      email = String.downcase(Map.get(attrs, "email") || Map.get(attrs, :email) || "")
      role = to_role_atom(Map.get(attrs, "role") || Map.get(attrs, :role))

      cond do
        email == "" ->
          {:error, invite_changeset_error(:email, "can't be blank")}

        true ->
          with :ok <- check_not_already_member(org, email),
               :ok <- check_no_pending_invite(org, email) do
            {raw_token, invite_struct} = OrganizationInvite.build(org.id, email, inviter.id, role)

            changeset =
              invite_struct
              |> Ecto.Changeset.change(%{})
              |> Ecto.Changeset.validate_inclusion(:role, ~w(admin member))
              |> Ecto.Changeset.validate_format(:email, ~r/^[^\s]+@[^\s]+$/,
                message: "must be a valid email"
              )
              |> Ecto.Changeset.unique_constraint([:organization_id, :email],
                name: :organization_invites_org_email_unique,
                message: "has already been invited"
              )

            case Repo.insert(changeset) do
              {:ok, invite} -> {:ok, {raw_token, invite}}
              {:error, cs} -> {:error, cs}
            end
          end
      end
    end
  end

  defp invite_changeset_error(field, msg) do
    %OrganizationInvite{}
    |> Ecto.Changeset.change(%{})
    |> Ecto.Changeset.add_error(field, msg)
    |> Map.put(:action, :insert)
  end

  defp check_not_already_member(org, email) do
    user = Repo.get_by(User, email: String.downcase(email))

    if user do
      case Repo.get_by(OrganizationMembership, organization_id: org.id, user_id: user.id) do
        nil -> :ok
        _ -> {:error, :already_member}
      end
    else
      :ok
    end
  end

  defp check_no_pending_invite(org, email) do
    lower_email = String.downcase(email)

    existing =
      from(i in OrganizationInvite,
        where: i.organization_id == ^org.id and fragment("lower(?)", i.email) == ^lower_email
      )
      |> Repo.one()

    if existing, do: {:error, :invite_exists}, else: :ok
  end

  def list_pending_invites(%Scope{} = scope, %Organization{} = org) do
    if Scope.org_id(scope) != org.id, do: raise(ArgumentError, "scope/org mismatch")

    from(i in OrganizationInvite,
      where: i.organization_id == ^org.id,
      join: u in assoc(i, :invited_by),
      preload: [invited_by: u],
      order_by: [asc: i.inserted_at]
    )
    |> Repo.all()
  end

  def list_pending_invites_for_email(%Scope{user: %User{} = user}) do
    lower_email = String.downcase(user.email || "")

    from(i in OrganizationInvite,
      where: fragment("lower(?)", i.email) == ^lower_email,
      join: o in assoc(i, :organization),
      join: u in assoc(i, :invited_by),
      preload: [organization: o, invited_by: u],
      order_by: [asc: i.inserted_at]
    )
    |> Repo.all()
  end

  def list_pending_invites_for_email(_scope), do: []

  def accept_invite(%Scope{user: %User{} = user}, raw_token) do
    with {:ok, token_hash} <- OrganizationInvite.verify_token(raw_token),
         {:ok, invite} <- find_invite_by_token(token_hash),
         :ok <- check_email_match(invite, user),
         :ok <- check_not_expired(invite),
         :ok <- check_not_already_member_by_user(invite.organization_id, user.id) do
      do_accept_invite(invite, user)
    else
      :error -> {:error, :invalid_token}
      other -> other
    end
  end

  def accept_invite(_scope, _token), do: {:error, :unauthenticated}

  defp do_accept_invite(invite, user) do
    Repo.transaction(fn ->
      membership_cs =
        OrganizationMembership.changeset(%OrganizationMembership{}, %{
          organization_id: invite.organization_id,
          user_id: user.id,
          role: invite.role
        })

      case Repo.insert(membership_cs) do
        {:ok, membership} ->
          {:ok, _} = Repo.delete(invite)
          org = invite.organization
          {org, membership}

        {:error, cs} ->
          Repo.rollback(cs)
      end
    end)
  end

  defp find_invite_by_token(token_hash) do
    case Repo.get_by(OrganizationInvite, token: token_hash) do
      nil -> {:error, :invalid_token}
      invite -> {:ok, Repo.preload(invite, :organization)}
    end
  end

  defp check_email_match(invite, user) do
    if String.downcase(invite.email) == String.downcase(user.email || "") do
      :ok
    else
      {:error, :email_mismatch}
    end
  end

  defp check_not_expired(invite) do
    if OrganizationInvite.expired?(invite), do: {:error, :expired}, else: :ok
  end

  defp check_not_already_member_by_user(org_id, user_id) do
    case Repo.get_by(OrganizationMembership, organization_id: org_id, user_id: user_id) do
      nil -> :ok
      _ -> {:error, :already_member}
    end
  end

  def get_invite(%Scope{} = scope, invite_id) do
    case Repo.get(OrganizationInvite, invite_id) do
      nil ->
        {:error, :not_found}

      invite ->
        if invite.organization_id == Scope.org_id(scope) do
          {:ok, invite}
        else
          {:error, :unauthorized}
        end
    end
  end

  def revoke_invite(%Scope{} = scope, %OrganizationInvite{} = invite) do
    with :ok <- check_org_admin(scope),
         :ok <- check_invite_in_scope(scope, invite) do
      Repo.delete(invite)
    end
  end

  def resend_invite(%Scope{user: %User{} = inviter} = scope, %OrganizationInvite{} = invite) do
    with :ok <- check_org_admin(scope),
         :ok <- check_invite_in_scope(scope, invite) do
      {:ok, org} = get_organization(invite.organization_id)

      Repo.transaction(fn ->
        {:ok, _} = Repo.delete(invite)

        {raw_token, new_invite} =
          OrganizationInvite.build(org.id, invite.email, inviter.id, invite.role)

        changeset =
          new_invite
          |> Ecto.Changeset.change(%{})
          |> Ecto.Changeset.unique_constraint([:organization_id, :email],
            name: :organization_invites_org_email_unique,
            message: "has already been invited"
          )

        case Repo.insert(changeset) do
          {:ok, saved} -> {raw_token, saved}
          {:error, cs} -> Repo.rollback(cs)
        end
      end)
    end
  end

  defp check_invite_in_scope(scope, invite) do
    if invite.organization_id == Scope.org_id(scope) do
      :ok
    else
      {:error, :unauthorized}
    end
  end

  def accept_invite_by_id(%Scope{user: %User{} = user}, invite_id) do
    case Repo.get(OrganizationInvite, invite_id) do
      nil ->
        {:error, :not_found}

      invite ->
        invite = Repo.preload(invite, :organization)

        with :ok <- check_email_match(invite, user),
             :ok <- check_not_expired(invite),
             :ok <- check_not_already_member_by_user(invite.organization_id, user.id) do
          do_accept_invite(invite, user)
        end
    end
  end

  def accept_invite_by_id(_scope, _id), do: {:error, :unauthenticated}

  def get_invite_by_raw_token(raw_token) do
    with {:ok, token_hash} <- OrganizationInvite.verify_token(raw_token) do
      case Repo.get_by(OrganizationInvite, token: token_hash) do
        nil -> {:error, :not_found}
        invite -> {:ok, Repo.preload(invite, [:organization, :invited_by])}
      end
    else
      :error -> {:error, :invalid_token}
    end
  end

  defp to_role_atom(role) when role in [:admin, :member], do: role
  defp to_role_atom("admin"), do: :admin
  defp to_role_atom("member"), do: :member
  defp to_role_atom(_), do: :member
end
