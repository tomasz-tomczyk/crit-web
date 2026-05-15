defmodule CritWeb.ReviewLiveOrgAccessTest do
  use CritWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Crit.OrganizationsFixtures

  alias Crit.{Repo, Reviews}
  alias Crit.Accounts.Scope

  defp insert_user!(attrs \\ %{}) do
    base = %{
      provider: "test",
      provider_uid: "uid-#{System.unique_integer([:positive])}",
      email: "u-#{System.unique_integer([:positive])}@example.com",
      name: "OrgAccessUser"
    }

    %Crit.User{}
    |> Crit.User.oauth_changeset(Map.merge(base, attrs))
    |> Repo.insert!()
  end

  defp create_org_review(user, org) do
    scope = Scope.for_user(user)

    {:ok, review} =
      Reviews.create_review(
        scope,
        [%{"path" => "test.md", "content" => "# Org Review"}],
        0,
        [],
        [],
        org: org.slug
      )

    review
  end

  setup do
    admin = insert_user!()
    member = insert_user!()
    outsider = insert_user!()

    org = organization_fixture(admin)
    _membership = membership_fixture(org, member, "member")

    review = create_org_review(member, org)

    %{admin: admin, member: member, outsider: outsider, org: org, review: review}
  end

  defp create_unlisted_org_review(user, org) do
    scope = Scope.for_user(user)

    {:ok, review} =
      Reviews.create_review(
        scope,
        [%{"path" => "unlisted.md", "content" => "# Unlisted Org Review"}],
        0,
        [],
        [],
        org: org.slug,
        visibility: :unlisted
      )

    review
  end

  defp create_public_org_review(user, org) do
    scope = Scope.for_user(user)

    {:ok, review} =
      Reviews.create_review(
        scope,
        [%{"path" => "public.md", "content" => "# Public Org Review"}],
        0,
        [],
        [],
        org: org.slug,
        visibility: :public
      )

    review
  end

  describe "org-visibility review access" do
    test "org member can view the review", %{conn: conn, member: member, review: review} do
      conn = init_test_session(conn, %{user_id: member.id})
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")
      assert has_element?(view, "#document-renderer")
    end

    test "org admin can view the review", %{conn: conn, admin: admin, review: review} do
      conn = init_test_session(conn, %{user_id: admin.id})
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")
      assert has_element?(view, "#document-renderer")
    end

    test "non-member authenticated user gets not-found error", %{
      conn: conn,
      outsider: outsider,
      review: review
    } do
      conn = init_test_session(conn, %{user_id: outsider.id})

      assert_raise CritWeb.NotFoundError, fn ->
        live(conn, ~p"/r/#{review.token}")
      end
    end

    test "unauthenticated user is redirected to login", %{conn: conn, review: review} do
      assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/r/#{review.token}")
      assert to =~ "/auth/login"
      assert to =~ "return_to="
      assert to =~ URI.encode_www_form("/r/#{review.token}")
    end
  end

  describe "unlisted org review access" do
    test "org member can view unlisted org review", %{conn: conn, member: member, org: org} do
      review = create_unlisted_org_review(member, org)
      conn = init_test_session(conn, %{user_id: member.id})
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")
      assert has_element?(view, "#document-renderer")
    end

    test "non-member cannot view unlisted org review", %{
      conn: conn,
      outsider: outsider,
      member: member,
      org: org
    } do
      review = create_unlisted_org_review(member, org)
      conn = init_test_session(conn, %{user_id: outsider.id})

      assert_raise CritWeb.NotFoundError, fn ->
        live(conn, ~p"/r/#{review.token}")
      end
    end

    test "unauthenticated user is redirected for unlisted org review", %{
      conn: conn,
      member: member,
      org: org
    } do
      review = create_unlisted_org_review(member, org)
      assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/r/#{review.token}")
      assert to =~ "/auth/login"
    end
  end

  describe "public org review access" do
    test "non-member can view public org review", %{
      conn: conn,
      outsider: outsider,
      member: member,
      org: org
    } do
      review = create_public_org_review(member, org)
      conn = init_test_session(conn, %{user_id: outsider.id})
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")
      assert has_element?(view, "#document-renderer")
    end

    test "unauthenticated user can view public org review", %{
      conn: conn,
      member: member,
      org: org
    } do
      review = create_public_org_review(member, org)
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")
      assert has_element?(view, "#document-renderer")
    end
  end
end
