defmodule CritWeb.ReviewLiveCommentPolicyTest do
  use CritWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Crit.ReviewsFixtures

  alias Crit.Accounts.Scope
  alias Crit.Reviews

  defp owner_fixture do
    {:ok, user} =
      Crit.Accounts.find_or_create_from_oauth("github", %{
        "sub" => "cp-#{System.unique_integer([:positive])}",
        "email" => "cp-#{System.unique_integer([:positive])}@example.com",
        "name" => "Owner"
      })

    user
  end

  defp log_in(conn, user), do: init_test_session(conn, %{user_id: user.id})

  test "owner sees the comment-policy popover trigger", %{conn: conn} do
    user = owner_fixture()
    review = review_fixture(user_id: user.id)
    conn = log_in(conn, user)

    {:ok, view, html} = live(conn, ~p"/r/#{review.token}")
    assert has_element?(view, "[data-test=comment-policy-menu]")
    assert has_element?(view, "#comment-policy-menu-panel[role=dialog]")
    assert has_element?(view, "#comment-policy-menu-trigger[aria-controls=comment-policy-menu-panel]")
    assert has_element?(view, "[data-test=comment-policy-set-disallowed]")
    assert html =~ "Open"
  end

  test "owner can switch to :logged_in_only and the page re-renders without losing preloads",
       %{conn: conn} do
    user = owner_fixture()
    review = review_fixture(user_id: user.id)
    conn = log_in(conn, user)
    file_path = hd(review.files).file_path

    {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")
    rendered = view |> element("[data-test=comment-policy-set-logged_in_only]") |> render_click()

    assert Reviews.get_by_token(review.token).comment_policy == :logged_in_only
    assert rendered =~ "signed-in users can comment"
    assert rendered =~ file_path
  end

  test "non-owner authenticated user sees no menu, no badge on :open", %{conn: conn} do
    owner = owner_fixture()
    other = owner_fixture()
    review = review_fixture(user_id: owner.id)
    conn = log_in(conn, other)

    {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")
    refute has_element?(view, "[data-test=comment-policy-menu]")
    refute has_element?(view, "[data-test=comment-policy-badge]")
  end

  test "non-owner sees a muted badge when policy is :disallowed", %{conn: conn} do
    owner = owner_fixture()
    other = owner_fixture()
    review = review_fixture(user_id: owner.id)
    {:ok, _} = Reviews.update_review(Scope.for_user(owner), review.id, %{comment_policy: :disallowed})
    conn = log_in(conn, other)

    {:ok, view, html} = live(conn, ~p"/r/#{review.token}")
    refute has_element?(view, "[data-test=comment-policy-menu]")
    assert has_element?(view, "[data-test=comment-policy-badge]")
    assert html =~ "Disabled"
  end

  test "anonymous viewer sees no menu", %{conn: conn} do
    owner = owner_fixture()
    review = review_fixture(user_id: owner.id)

    {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")
    refute has_element?(view, "[data-test=comment-policy-menu]")
  end

  describe "cross-tab :policy_changed broadcast" do
    test "anonymous viewer's open tab updates when owner flips policy elsewhere", %{conn: conn} do
      owner = owner_fixture()
      review = review_fixture(user_id: owner.id)

      {:ok, view, html} = live(conn, ~p"/r/#{review.token}")
      refute html =~ "Sign in to comment"

      {:ok, _} = Reviews.update_review(Scope.for_user(owner), review.id, %{comment_policy: :logged_in_only})

      _ = render(view)
      rendered = render(view)

      assert rendered =~ "Login required" or has_element?(view, "[data-test=comment-policy-badge]")
      refute rendered =~ "Only signed-in users can comment now."
    end

    test "owner's other tab updates without flash when same owner flips policy in tab A",
         %{conn: conn} do
      owner = owner_fixture()
      review = review_fixture(user_id: owner.id)
      conn = log_in(conn, owner)

      {:ok, view_b, _html} = live(conn, ~p"/r/#{review.token}")

      {:ok, _} = Reviews.update_review(Scope.for_user(owner), review.id, %{comment_policy: :disallowed})

      _ = render(view_b)
      rendered = render(view_b)

      assert rendered =~ "Disabled"
      refute rendered =~ "turned off for this review"
    end

    test "no-op update (same policy) does not push a stale render or flash", %{conn: conn} do
      owner = owner_fixture()
      review = review_fixture(user_id: owner.id)
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")
      before = render(view)

      {:ok, _} = Reviews.update_review(Scope.for_user(owner), review.id, %{comment_policy: :open})

      _ = render(view)
      assert render(view) == before
    end
  end
end
