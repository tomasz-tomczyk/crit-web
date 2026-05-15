defmodule Crit.ReviewsOrgTest do
  use Crit.DataCase, async: true

  alias Crit.{Repo, Review, Reviews}
  alias Crit.Accounts.Scope
  alias Crit.Organizations

  import Crit.OrganizationsFixtures

  defp insert_user!(attrs \\ %{}) do
    base = %{
      provider: "test",
      provider_uid: "uid-#{System.unique_integer([:positive])}",
      email: "u-#{System.unique_integer([:positive])}@example.com",
      name: "Alex"
    }

    %Crit.User{}
    |> Crit.User.oauth_changeset(Map.merge(base, attrs))
    |> Repo.insert!()
  end

  defp default_files, do: [%{"path" => "test.md", "content" => "# Hello"}]

  describe "create_review with org" do
    setup do
      admin = insert_user!()
      member = insert_user!()
      outsider = insert_user!()

      org = organization_fixture(admin)
      _membership = membership_fixture(org, member, "member")

      %{admin: admin, member: member, outsider: outsider, org: org}
    end

    test "with org slug sets organization_id and defaults visibility to :organization", ctx do
      scope = Scope.for_user(ctx.member)

      assert {:ok, review} =
               Reviews.create_review(scope, default_files(), 0, [], [], org: ctx.org.slug)

      assert review.organization_id == ctx.org.id
      assert review.visibility == :organization
    end

    test "with org slug and explicit visibility overrides the default", ctx do
      scope = Scope.for_user(ctx.member)

      assert {:ok, review} =
               Reviews.create_review(scope, default_files(), 0, [], [],
                 org: ctx.org.slug,
                 visibility: :unlisted
               )

      assert review.organization_id == ctx.org.id
      assert review.visibility == :unlisted
    end

    test "non-member cannot create review in org", ctx do
      scope = Scope.for_user(ctx.outsider)

      assert {:error, :not_a_member} =
               Reviews.create_review(scope, default_files(), 0, [], [], org: ctx.org.slug)
    end

    test "anonymous user cannot create review in org", ctx do
      scope = Scope.for_visitor("anon-#{System.unique_integer([:positive])}")

      assert {:error, :not_a_member} =
               Reviews.create_review(scope, default_files(), 0, [], [], org: ctx.org.slug)
    end

    test "nonexistent org slug returns :org_not_found" do
      user = insert_user!()
      scope = Scope.for_user(user)

      assert {:error, :org_not_found} =
               Reviews.create_review(scope, default_files(), 0, [], [], org: "no-such-org")
    end

    test "without org slug, behavior is unchanged" do
      user = insert_user!()
      scope = Scope.for_user(user)

      assert {:ok, review} = Reviews.create_review(scope, default_files(), 0, [])
      assert review.organization_id == nil
      assert review.visibility == :unlisted
    end
  end

  describe "org admin deletion" do
    setup do
      admin = insert_user!()
      member = insert_user!()
      outsider = insert_user!()

      org = organization_fixture(admin)
      _membership = membership_fixture(org, member, "member")

      # Member creates a review in the org
      member_scope = Scope.for_user(member)

      {:ok, review} =
        Reviews.create_review(member_scope, default_files(), 0, [], [], org: org.slug)

      %{admin: admin, member: member, outsider: outsider, org: org, review: review}
    end

    test "org admin can delete any review in their org", ctx do
      admin_scope = Scope.for_user(ctx.admin)
      assert :ok = Reviews.delete_review(admin_scope, ctx.review.id)
      assert Repo.get(Review, ctx.review.id) == nil
    end

    test "non-admin org member cannot delete other's review", ctx do
      member_scope = Scope.for_user(ctx.member)

      # Member is the owner, so they can delete their own. Create a review by admin instead.
      admin_scope = Scope.for_user(ctx.admin)

      {:ok, admin_review} =
        Reviews.create_review(admin_scope, default_files(), 0, [], [], org: ctx.org.slug)

      assert {:error, :unauthorized} = Reviews.delete_review(member_scope, admin_review.id)
    end

    test "outsider cannot delete org review", ctx do
      outsider_scope = Scope.for_user(ctx.outsider)
      assert {:error, :unauthorized} = Reviews.delete_review(outsider_scope, ctx.review.id)
    end

    test "review owner can still delete their own org review", ctx do
      member_scope = Scope.for_user(ctx.member)
      assert :ok = Reviews.delete_review(member_scope, ctx.review.id)
    end
  end

  describe "list_org_reviews" do
    setup do
      admin = insert_user!()
      member = insert_user!()

      org = organization_fixture(admin)
      _membership = membership_fixture(org, member, "member")

      %{admin: admin, member: member, org: org}
    end

    test "returns reviews belonging to the org", ctx do
      member_scope = Scope.for_user(ctx.member)

      {:ok, review} =
        Reviews.create_review(member_scope, default_files(), 0, [], [], org: ctx.org.slug)

      admin_scope = org_scope(ctx.admin, ctx.org)
      reviews = Organizations.list_org_reviews(admin_scope, ctx.org)

      assert length(reviews) == 1
      assert hd(reviews).token == review.token
    end

    test "does not return reviews from other orgs", ctx do
      other_user = insert_user!()
      other_org = organization_fixture(other_user)

      other_scope = Scope.for_user(other_user)

      {:ok, _other_review} =
        Reviews.create_review(other_scope, default_files(), 0, [], [], org: other_org.slug)

      admin_scope = org_scope(ctx.admin, ctx.org)
      reviews = Organizations.list_org_reviews(admin_scope, ctx.org)

      assert reviews == []
    end

    test "returns empty list when scope org doesn't match", ctx do
      other_user = insert_user!()
      other_org = organization_fixture(other_user)
      other_scope = org_scope(other_user, other_org)

      reviews = Organizations.list_org_reviews(other_scope, ctx.org)
      assert reviews == []
    end

    test "does not return unlisted reviews in org listing", ctx do
      member_scope = Scope.for_user(ctx.member)

      {:ok, _} =
        Reviews.create_review(member_scope, default_files(), 0, [], [],
          org: ctx.org.slug,
          visibility: :unlisted
        )

      {:ok, _visible} =
        Reviews.create_review(member_scope, [%{"path" => "b.md", "content" => "b"}], 0, [], [],
          org: ctx.org.slug
        )

      admin_scope = org_scope(ctx.admin, ctx.org)
      reviews = Organizations.list_org_reviews(admin_scope, ctx.org)

      assert length(reviews) == 1
    end

    test "includes review counts in list_user_organizations", ctx do
      member_scope = Scope.for_user(ctx.member)

      {:ok, _} =
        Reviews.create_review(member_scope, default_files(), 0, [], [], org: ctx.org.slug)

      {:ok, _} =
        Reviews.create_review(member_scope, [%{"path" => "b.md", "content" => "b"}], 0, [], [],
          org: ctx.org.slug
        )

      orgs = Organizations.list_user_organizations(member_scope)
      org = Enum.find(orgs, &(&1.id == ctx.org.id))

      assert org.review_count == 2
    end

    test "review_count excludes unlisted reviews", ctx do
      member_scope = Scope.for_user(ctx.member)

      {:ok, _} =
        Reviews.create_review(member_scope, default_files(), 0, [], [], org: ctx.org.slug)

      {:ok, _} =
        Reviews.create_review(member_scope, [%{"path" => "b.md", "content" => "b"}], 0, [], [],
          org: ctx.org.slug,
          visibility: :unlisted
        )

      orgs = Organizations.list_user_organizations(member_scope)
      org = Enum.find(orgs, &(&1.id == ctx.org.id))

      assert org.review_count == 1
    end
  end

  describe "check_org_access" do
    setup do
      admin = insert_user!()
      member = insert_user!()
      outsider = insert_user!()

      org = organization_fixture(admin)
      _membership = membership_fixture(org, member, "member")

      %{admin: admin, member: member, outsider: outsider, org: org}
    end

    test "allows member to access :organization review", ctx do
      scope = Scope.for_user(ctx.member)
      {:ok, review} = Reviews.create_review(scope, default_files(), 0, [], [], org: ctx.org.slug)
      assert :ok = Reviews.check_org_access(review, Scope.for_user(ctx.member))
    end

    test "blocks non-member from :organization review", ctx do
      scope = Scope.for_user(ctx.member)
      {:ok, review} = Reviews.create_review(scope, default_files(), 0, [], [], org: ctx.org.slug)

      assert {:error, :unauthorized} =
               Reviews.check_org_access(review, Scope.for_user(ctx.outsider))
    end

    test "blocks non-member from :unlisted org review", ctx do
      scope = Scope.for_user(ctx.member)

      {:ok, review} =
        Reviews.create_review(scope, default_files(), 0, [], [],
          org: ctx.org.slug,
          visibility: :unlisted
        )

      assert {:error, :unauthorized} =
               Reviews.check_org_access(review, Scope.for_user(ctx.outsider))
    end

    test "allows anyone to access :public org review", ctx do
      scope = Scope.for_user(ctx.member)

      {:ok, review} =
        Reviews.create_review(scope, default_files(), 0, [], [],
          org: ctx.org.slug,
          visibility: :public
        )

      assert :ok = Reviews.check_org_access(review, Scope.for_user(ctx.outsider))
      assert :ok = Reviews.check_org_access(review, %Scope{})
    end

    test "blocks access to orphaned review with :organization visibility", ctx do
      scope = Scope.for_user(ctx.member)
      {:ok, review} = Reviews.create_review(scope, default_files(), 0, [], [], org: ctx.org.slug)

      # Simulate org deletion orphaning the review
      review = %{review | organization_id: nil}

      assert {:error, :unauthorized} =
               Reviews.check_org_access(review, Scope.for_user(ctx.member))
    end

    test "blocks anonymous scope from org review", ctx do
      scope = Scope.for_user(ctx.member)
      {:ok, review} = Reviews.create_review(scope, default_files(), 0, [], [], org: ctx.org.slug)
      assert {:error, :unauthorized} = Reviews.check_org_access(review, %Scope{})
    end

    test "admin of org A cannot access review in org B", ctx do
      other_admin = insert_user!()
      _other_org = organization_fixture(other_admin)

      scope = Scope.for_user(ctx.member)
      {:ok, review} = Reviews.create_review(scope, default_files(), 0, [], [], org: ctx.org.slug)

      assert {:error, :unauthorized} =
               Reviews.check_org_access(review, Scope.for_user(other_admin))
    end
  end

  describe "membership revocation and account deletion" do
    setup do
      admin = insert_user!()
      member = insert_user!()

      org = organization_fixture(admin)
      membership = membership_fixture(org, member, "member")

      member_scope = Scope.for_user(member)

      {:ok, org_review} =
        Reviews.create_review(member_scope, default_files(), 0, [], [], org: org.slug)

      {:ok, personal_review} =
        Reviews.create_review(member_scope, [%{"path" => "p.md", "content" => "p"}], 0, [])

      %{
        admin: admin,
        member: member,
        org: org,
        membership: membership,
        org_review: org_review,
        personal_review: personal_review
      }
    end

    test "revoked member loses access to org review", ctx do
      Repo.delete!(ctx.membership)
      scope = Scope.for_user(ctx.member)
      assert {:error, :unauthorized} = Reviews.check_org_access(ctx.org_review, scope)
    end

    test "org review survives when author deletes their account", ctx do
      Crit.Accounts.delete_user(ctx.member)
      review = Repo.get(Crit.Review, ctx.org_review.id)
      assert review != nil
      assert review.organization_id == ctx.org.id
      assert review.user_id == nil
    end

    test "personal review is deleted when author deletes their account", ctx do
      Crit.Accounts.delete_user(ctx.member)
      assert Repo.get(Crit.Review, ctx.personal_review.id) == nil
    end
  end

  describe "cross-org admin deletion" do
    test "admin of org A cannot delete review in org B" do
      admin_a = insert_user!()
      _org_a = organization_fixture(admin_a)
      admin_b = insert_user!()
      org_b = organization_fixture(admin_b)
      member_b = insert_user!()
      _membership = membership_fixture(org_b, member_b, "member")

      member_scope = Scope.for_user(member_b)

      {:ok, review} =
        Reviews.create_review(member_scope, default_files(), 0, [], [], org: org_b.slug)

      admin_a_scope = Scope.for_user(admin_a)
      assert {:error, :unauthorized} = Reviews.delete_review(admin_a_scope, review.id)
    end
  end
end
