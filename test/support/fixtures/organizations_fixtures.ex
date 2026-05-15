defmodule Crit.OrganizationsFixtures do
  @moduledoc """
  Test helpers for creating organization-related entities.
  """

  alias Crit.Repo
  alias Crit.Organizations
  alias Crit.Organizations.OrganizationMembership
  alias Crit.Accounts.Scope

  def unique_org_name, do: "Org #{System.unique_integer([:positive])}"
  def unique_org_slug, do: "org-#{System.unique_integer([:positive])}"

  @doc """
  Creates an organization with the given user as admin.
  Returns the organization.
  """
  def organization_fixture(user, attrs \\ %{}) do
    scope = Scope.for_user(user)

    attrs =
      Enum.into(attrs, %{
        "name" => unique_org_name(),
        "slug" => unique_org_slug()
      })

    {:ok, org} = Organizations.create_organization(scope, attrs)
    org
  end

  @doc """
  Adds a user to an organization with the given role.
  Returns the membership.
  """
  def membership_fixture(org, user, role \\ :member) do
    {:ok, membership} =
      %OrganizationMembership{}
      |> OrganizationMembership.changeset(%{
        organization_id: org.id,
        user_id: user.id,
        role: role
      })
      |> Repo.insert()

    membership
  end

  @doc """
  Creates an invite for the given org and email.
  Returns `{raw_token, invite}`.
  """
  def invite_fixture(scope, org, email, role \\ :member) do
    {:ok, {raw_token, invite}} =
      Organizations.create_invite(scope, org, %{"email" => email, "role" => role})

    {raw_token, invite}
  end

  @doc """
  Returns a `%Scope{}` with the org and membership attached.
  """
  def org_scope(user, org) do
    scope = Scope.for_user(user)
    {:ok, membership} = Organizations.get_membership_for_user(org.id, user.id)
    Scope.put_organization(scope, org, membership)
  end
end
