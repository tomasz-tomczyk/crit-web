defmodule Crit.OrganizationsTest do
  use Crit.DataCase, async: true

  alias Crit.Organizations
  alias Crit.Organizations.{Organization, OrganizationMembership, OrganizationInvite}
  alias Crit.Accounts.Scope

  import Crit.AccountsFixtures
  import Crit.OrganizationsFixtures

  defp admin_scope(user, org) do
    org_scope(user, org)
  end

  defp member_scope(user, org) do
    org_scope(user, org)
  end

  # ---------------------------------------------------------------------------
  # Organization CRUD
  # ---------------------------------------------------------------------------

  describe "create_organization/2" do
    test "creates org and admin membership" do
      user = oauth_user_fixture()
      scope = Scope.for_user(user)

      assert {:ok, %Organization{} = org} =
               Organizations.create_organization(scope, %{"name" => "Acme", "slug" => "acme"})

      assert org.name == "Acme"
      assert org.slug == "acme"

      # User should be admin member
      assert {:ok, membership} = Organizations.get_membership_for_user(org.id, user.id)
      assert membership.role == :admin
    end

    test "returns error changeset for invalid name" do
      user = oauth_user_fixture()
      scope = Scope.for_user(user)

      assert {:error, %Ecto.Changeset{}} =
               Organizations.create_organization(scope, %{"name" => "", "slug" => "acme"})
    end

    test "returns error for duplicate slug" do
      user = oauth_user_fixture()
      scope = Scope.for_user(user)

      {:ok, _} = Organizations.create_organization(scope, %{"name" => "First", "slug" => "acme"})

      assert {:error, %Ecto.Changeset{} = cs} =
               Organizations.create_organization(scope, %{"name" => "Second", "slug" => "acme"})

      assert %{slug: [_]} = errors_on(cs)
    end
  end

  describe "update_organization/3" do
    test "admin can update org name" do
      user = oauth_user_fixture()
      org = organization_fixture(user)
      scope = admin_scope(user, org)

      assert {:ok, updated} =
               Organizations.update_organization(scope, org, %{"name" => "New Name"})

      assert updated.name == "New Name"
    end

    test "member cannot update org" do
      admin = oauth_user_fixture()
      member = oauth_user_fixture()
      org = organization_fixture(admin)
      _membership = membership_fixture(org, member, "member")
      scope = member_scope(member, org)

      assert {:error, :unauthorized} =
               Organizations.update_organization(scope, org, %{"name" => "Hacked"})
    end
  end

  describe "delete_organization/2" do
    test "admin can delete org" do
      user = oauth_user_fixture()
      org = organization_fixture(user)
      scope = admin_scope(user, org)

      assert {:ok, %Organization{}} = Organizations.delete_organization(scope, org)
      assert {:error, :not_found} = Organizations.get_organization(org.id)
    end

    test "member cannot delete org" do
      admin = oauth_user_fixture()
      member = oauth_user_fixture()
      org = organization_fixture(admin)
      _membership = membership_fixture(org, member, "member")
      scope = member_scope(member, org)

      assert {:error, :unauthorized} = Organizations.delete_organization(scope, org)
    end
  end

  describe "change_organization/2" do
    test "returns a changeset" do
      user = oauth_user_fixture()
      org = organization_fixture(user)

      assert %Ecto.Changeset{} = Organizations.change_organization(org)
    end

    test "applies attrs to changeset" do
      user = oauth_user_fixture()
      org = organization_fixture(user)

      cs = Organizations.change_organization(org, %{"name" => "Updated"})
      assert Ecto.Changeset.get_change(cs, :name) == "Updated"
    end
  end

  # ---------------------------------------------------------------------------
  # Memberships
  # ---------------------------------------------------------------------------

  describe "list_user_organizations/1" do
    test "returns orgs with virtual fields" do
      user = oauth_user_fixture()
      org = organization_fixture(user)

      scope = Scope.for_user(user)
      orgs = Organizations.list_user_organizations(scope)

      assert [%Organization{} = listed] = orgs
      assert listed.id == org.id
      assert listed.member_count == 1
      assert listed.role == :admin
    end

    test "returns empty list for user with no orgs" do
      user = oauth_user_fixture()
      scope = Scope.for_user(user)

      assert [] = Organizations.list_user_organizations(scope)
    end
  end

  describe "list_members/2" do
    test "returns memberships with preloaded users" do
      admin = oauth_user_fixture()
      member = oauth_user_fixture()
      org = organization_fixture(admin)
      _membership = membership_fixture(org, member, "member")

      scope = admin_scope(admin, org)
      members = Organizations.list_members(scope, org)

      assert length(members) == 2
      assert Enum.all?(members, fn m -> m.user != nil end)
    end
  end

  describe "update_membership_role/3" do
    test "admin can change member to admin" do
      admin = oauth_user_fixture()
      member = oauth_user_fixture()
      org = organization_fixture(admin)
      membership = membership_fixture(org, member, "member")
      scope = admin_scope(admin, org)

      assert {:ok, updated} = Organizations.update_membership_role(scope, membership, "admin")
      assert updated.role == :admin
    end

    test "cannot demote last admin" do
      admin = oauth_user_fixture()
      org = organization_fixture(admin)
      {:ok, membership} = Organizations.get_membership_for_user(org.id, admin.id)
      scope = admin_scope(admin, org)

      assert {:error, :last_admin} =
               Organizations.update_membership_role(scope, membership, "member")
    end

    test "member cannot change roles" do
      admin = oauth_user_fixture()
      member = oauth_user_fixture()
      org = organization_fixture(admin)
      target_membership = membership_fixture(org, member, "member")
      scope = member_scope(member, org)

      assert {:error, :unauthorized} =
               Organizations.update_membership_role(scope, target_membership, "admin")
    end
  end

  describe "remove_member/3" do
    test "admin can remove member" do
      admin = oauth_user_fixture()
      member = oauth_user_fixture()
      org = organization_fixture(admin)
      _membership = membership_fixture(org, member, "member")
      scope = admin_scope(admin, org)

      assert {:ok, %OrganizationMembership{}} =
               Organizations.remove_member(scope, org, member)

      assert {:error, :not_found} =
               Organizations.get_membership_for_user(org.id, member.id)
    end

    test "cannot remove last admin" do
      admin = oauth_user_fixture()
      org = organization_fixture(admin)
      scope = admin_scope(admin, org)

      assert {:error, :last_admin} = Organizations.remove_member(scope, org, admin)
    end
  end

  describe "leave_organization/2" do
    test "member can leave" do
      admin = oauth_user_fixture()
      member = oauth_user_fixture()
      org = organization_fixture(admin)
      _membership = membership_fixture(org, member, "member")
      scope = member_scope(member, org)

      assert {:ok, _scope} = Organizations.leave_organization(scope, org)
      assert {:error, :not_found} = Organizations.get_membership_for_user(org.id, member.id)
    end

    test "last admin cannot leave" do
      admin = oauth_user_fixture()
      org = organization_fixture(admin)
      scope = admin_scope(admin, org)

      assert {:error, :last_admin} = Organizations.leave_organization(scope, org)
    end
  end

  # ---------------------------------------------------------------------------
  # Invites
  # ---------------------------------------------------------------------------

  describe "create_invite/3" do
    test "admin can create invite" do
      admin = oauth_user_fixture()
      org = organization_fixture(admin)
      scope = admin_scope(admin, org)

      assert {:ok, {raw_token, %OrganizationInvite{} = invite}} =
               Organizations.create_invite(scope, org, %{
                 "email" => "new@example.com",
                 "role" => "member"
               })

      assert is_binary(raw_token)
      assert invite.email == "new@example.com"
      assert invite.role == :member
    end

    test "returns error changeset for blank email" do
      admin = oauth_user_fixture()
      org = organization_fixture(admin)
      scope = admin_scope(admin, org)

      assert {:error, %Ecto.Changeset{} = cs} =
               Organizations.create_invite(scope, org, %{"email" => "", "role" => "member"})

      assert %{email: ["can't be blank"]} = errors_on(cs)
    end

    test "returns error when user is already a member" do
      admin = oauth_user_fixture()
      org = organization_fixture(admin)
      scope = admin_scope(admin, org)

      assert {:error, :already_member} =
               Organizations.create_invite(scope, org, %{
                 "email" => admin.email,
                 "role" => "member"
               })
    end

    test "returns error when invite already exists" do
      admin = oauth_user_fixture()
      org = organization_fixture(admin)
      scope = admin_scope(admin, org)

      {:ok, _} =
        Organizations.create_invite(scope, org, %{
          "email" => "new@example.com",
          "role" => "member"
        })

      assert {:error, :invite_exists} =
               Organizations.create_invite(scope, org, %{
                 "email" => "new@example.com",
                 "role" => "member"
               })
    end

    test "member cannot create invite" do
      admin = oauth_user_fixture()
      member = oauth_user_fixture()
      org = organization_fixture(admin)
      _membership = membership_fixture(org, member, "member")
      scope = member_scope(member, org)

      assert {:error, :unauthorized} =
               Organizations.create_invite(scope, org, %{
                 "email" => "new@example.com",
                 "role" => "member"
               })
    end
  end

  describe "accept_invite/2" do
    test "creates membership and deletes invite" do
      admin = oauth_user_fixture()
      invitee = oauth_user_fixture()
      org = organization_fixture(admin)
      scope = admin_scope(admin, org)

      {raw_token, _invite} = invite_fixture(scope, org, invitee.email)

      invitee_scope = Scope.for_user(invitee)

      assert {:ok, {%Organization{}, %OrganizationMembership{}}} =
               Organizations.accept_invite(invitee_scope, raw_token)

      # Membership exists
      assert {:ok, membership} = Organizations.get_membership_for_user(org.id, invitee.id)
      assert membership.role == :member

      # Invite was deleted
      invites = Organizations.list_pending_invites(scope, org)
      assert invites == []
    end

    test "returns error for invalid token" do
      user = oauth_user_fixture()
      scope = Scope.for_user(user)

      assert {:error, :invalid_token} = Organizations.accept_invite(scope, "bogus!!!")
    end

    test "returns error for email mismatch" do
      admin = oauth_user_fixture()
      other = oauth_user_fixture()
      org = organization_fixture(admin)
      scope = admin_scope(admin, org)

      {raw_token, _invite} = invite_fixture(scope, org, "someone-else@example.com")

      other_scope = Scope.for_user(other)

      assert {:error, :email_mismatch} = Organizations.accept_invite(other_scope, raw_token)
    end

    test "returns error when already a member" do
      admin = oauth_user_fixture()
      org = organization_fixture(admin)

      # Create an invite for admin's email by building directly (bypassing the
      # already-member check at creation time)
      {raw_token, invite_struct} =
        OrganizationInvite.build(org.id, admin.email, admin.id, :member)

      invite_struct
      |> Ecto.Changeset.change(%{})
      |> Repo.insert!()

      admin_scope_bare = Scope.for_user(admin)
      assert {:error, :already_member} = Organizations.accept_invite(admin_scope_bare, raw_token)
    end

    test "returns error for expired invite" do
      admin = oauth_user_fixture()
      invitee = oauth_user_fixture()
      org = organization_fixture(admin)
      scope = admin_scope(admin, org)

      {raw_token, invite} = invite_fixture(scope, org, invitee.email)

      # Manually expire the invite
      expired_at =
        DateTime.utc_now()
        |> DateTime.add(-8, :day)
        |> DateTime.truncate(:second)

      invite
      |> Ecto.Changeset.change(%{inserted_at: expired_at})
      |> Repo.update!()

      invitee_scope = Scope.for_user(invitee)
      assert {:error, :expired} = Organizations.accept_invite(invitee_scope, raw_token)
    end

    test "returns error for unauthenticated scope" do
      assert {:error, :unauthenticated} = Organizations.accept_invite(%Scope{}, "some-token")
    end
  end

  describe "accept_invite_by_id/2" do
    test "creates membership and deletes invite" do
      admin = oauth_user_fixture()
      invitee = oauth_user_fixture()
      org = organization_fixture(admin)
      scope = admin_scope(admin, org)

      {_raw_token, invite} = invite_fixture(scope, org, invitee.email)

      invitee_scope = Scope.for_user(invitee)

      assert {:ok, {%Organization{}, %OrganizationMembership{}}} =
               Organizations.accept_invite_by_id(invitee_scope, invite.id)
    end

    test "returns error for non-existent invite" do
      user = oauth_user_fixture()
      scope = Scope.for_user(user)

      assert {:error, :not_found} =
               Organizations.accept_invite_by_id(scope, Ecto.UUID.generate())
    end

    test "returns error for unauthenticated scope" do
      assert {:error, :unauthenticated} =
               Organizations.accept_invite_by_id(%Scope{}, Ecto.UUID.generate())
    end
  end

  describe "revoke_invite/2" do
    test "admin can revoke invite" do
      admin = oauth_user_fixture()
      org = organization_fixture(admin)
      scope = admin_scope(admin, org)

      {_raw_token, invite} = invite_fixture(scope, org, "new@example.com")

      assert {:ok, %OrganizationInvite{}} = Organizations.revoke_invite(scope, invite)
      assert Organizations.list_pending_invites(scope, org) == []
    end

    test "returns error for invite in different org" do
      admin1 = oauth_user_fixture()
      admin2 = oauth_user_fixture()
      org1 = organization_fixture(admin1)
      org2 = organization_fixture(admin2)
      scope1 = admin_scope(admin1, org1)
      scope2 = admin_scope(admin2, org2)

      {_raw_token, invite} = invite_fixture(scope2, org2, "new@example.com")

      assert {:error, :unauthorized} = Organizations.revoke_invite(scope1, invite)
    end
  end

  describe "resend_invite/2" do
    test "creates new invite with new token and deletes old" do
      admin = oauth_user_fixture()
      org = organization_fixture(admin)
      scope = admin_scope(admin, org)

      {_raw_token, old_invite} = invite_fixture(scope, org, "new@example.com")

      assert {:ok, {new_raw_token, new_invite}} =
               Organizations.resend_invite(scope, old_invite)

      assert is_binary(new_raw_token)
      assert new_invite.email == old_invite.email
      assert new_invite.id != old_invite.id
    end
  end

  describe "list_pending_invites/2" do
    test "lists org's invites" do
      admin = oauth_user_fixture()
      org = organization_fixture(admin)
      scope = admin_scope(admin, org)

      {_raw_token, _invite} = invite_fixture(scope, org, "a@example.com")
      {_raw_token, _invite} = invite_fixture(scope, org, "b@example.com")

      invites = Organizations.list_pending_invites(scope, org)
      assert length(invites) == 2
      assert Enum.all?(invites, fn i -> i.invited_by != nil end)
    end
  end

  # ---------------------------------------------------------------------------
  # Cross-tenant isolation
  # ---------------------------------------------------------------------------

  describe "cross-tenant guards" do
    setup do
      user_a = oauth_user_fixture()
      user_b = oauth_user_fixture()
      org_a = organization_fixture(user_a)
      org_b = organization_fixture(user_b)
      scope_a = admin_scope(user_a, org_a)
      scope_b = admin_scope(user_b, org_b)

      %{
        user_a: user_a,
        user_b: user_b,
        org_a: org_a,
        org_b: org_b,
        scope_a: scope_a,
        scope_b: scope_b
      }
    end

    test "update_organization rejects cross-tenant access", ctx do
      assert {:error, :unauthorized} =
               Organizations.update_organization(ctx.scope_a, ctx.org_b, %{"name" => "hacked"})
    end

    test "delete_organization rejects cross-tenant access", ctx do
      assert {:error, :unauthorized} =
               Organizations.delete_organization(ctx.scope_a, ctx.org_b)
    end

    test "create_invite rejects cross-tenant access", ctx do
      assert {:error, :unauthorized} =
               Organizations.create_invite(ctx.scope_a, ctx.org_b, %{"email" => "x@x.com"})
    end

    test "remove_member rejects cross-tenant access", ctx do
      assert {:error, :unauthorized} =
               Organizations.remove_member(ctx.scope_a, ctx.org_b, ctx.user_b)
    end
  end

  describe "list_pending_invites_for_email/1" do
    test "lists invites matching user's email" do
      admin = oauth_user_fixture()
      invitee = oauth_user_fixture()
      org = organization_fixture(admin)
      scope = admin_scope(admin, org)

      {_raw_token, _invite} = invite_fixture(scope, org, invitee.email)

      invitee_scope = Scope.for_user(invitee)
      invites = Organizations.list_pending_invites_for_email(invitee_scope)

      assert length(invites) == 1
      assert hd(invites).organization != nil
    end

    test "returns empty list for no matching invites" do
      user = oauth_user_fixture()
      scope = Scope.for_user(user)

      assert [] = Organizations.list_pending_invites_for_email(scope)
    end
  end
end
