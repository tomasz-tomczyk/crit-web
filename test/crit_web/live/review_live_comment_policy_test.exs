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

    assert has_element?(
             view,
             "#comment-policy-menu-trigger[aria-controls=comment-policy-menu-panel]"
           )

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

    {:ok, _} =
      Reviews.update_review(Scope.for_user(owner), review.id, %{comment_policy: :disallowed})

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

  test "anonymous viewer in :logged_in_only mode sees the sign-in banner", %{conn: conn} do
    owner = owner_fixture()
    review = review_fixture(user_id: owner.id)

    {:ok, _} =
      Reviews.update_review(Scope.for_user(owner), review.id, %{comment_policy: :logged_in_only})

    {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")
    assert has_element?(view, ".crit-signin-banner")
    assert has_element?(view, ".crit-signin-banner a", "Sign in")
  end

  test "authenticated viewer in :logged_in_only mode does NOT see the banner", %{conn: conn} do
    owner = owner_fixture()
    review = review_fixture(user_id: owner.id)

    {:ok, _} =
      Reviews.update_review(Scope.for_user(owner), review.id, %{comment_policy: :logged_in_only})

    conn = log_in(conn, owner_fixture())

    {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")
    refute has_element?(view, ".crit-signin-banner")
  end

  test ":disallowed does NOT show a body banner (header pill carries the signal)",
       %{conn: conn} do
    owner = owner_fixture()
    review = review_fixture(user_id: owner.id)

    {:ok, _} =
      Reviews.update_review(Scope.for_user(owner), review.id, %{comment_policy: :disallowed})

    {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")
    refute has_element?(view, ".crit-signin-banner")
  end

  test ":open never shows the banner", %{conn: conn} do
    owner = owner_fixture()
    review = review_fixture(user_id: owner.id)
    {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")
    refute has_element?(view, ".crit-signin-banner")
  end

  describe "cross-tab :policy_changed broadcast" do
    test "anonymous viewer's open tab updates when owner flips policy elsewhere", %{conn: conn} do
      owner = owner_fixture()
      review = review_fixture(user_id: owner.id)

      {:ok, view, html} = live(conn, ~p"/r/#{review.token}")
      refute html =~ "Sign in to comment"

      {:ok, _} =
        Reviews.update_review(Scope.for_user(owner), review.id, %{comment_policy: :logged_in_only})

      _ = render(view)
      rendered = render(view)

      assert rendered =~ "Login required" or
               has_element?(view, "[data-test=comment-policy-badge]")

      refute rendered =~ "Only signed-in users can comment now."
    end

    test "owner's other tab updates without flash when same owner flips policy in tab A",
         %{conn: conn} do
      owner = owner_fixture()
      review = review_fixture(user_id: owner.id)
      conn = log_in(conn, owner)

      {:ok, view_b, _html} = live(conn, ~p"/r/#{review.token}")

      {:ok, _} =
        Reviews.update_review(Scope.for_user(owner), review.id, %{comment_policy: :disallowed})

      _ = render(view_b)
      rendered = render(view_b)

      assert rendered =~ "Disabled"
      refute rendered =~ "turned off for this review"
    end

    test "add_comment is rejected when comment_policy is :disallowed", %{conn: conn} do
      owner = owner_fixture()
      review = review_fixture(user_id: owner.id)
      conn = log_in(conn, owner)

      {:ok, _} =
        Reviews.update_review(Scope.for_user(owner), review.id, %{comment_policy: :disallowed})

      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      view
      |> render_hook("add_comment", %{
        "body" => "nope",
        "start_line" => 1,
        "end_line" => 1,
        "scope" => "line"
      })

      assert Reviews.list_comments(review.id) == []
    end

    test "add_reply is rejected when comment_policy is :logged_in_only and viewer is anonymous",
         %{conn: conn} do
      owner = owner_fixture()
      review = review_fixture(user_id: owner.id)

      {:ok, _} =
        Reviews.update_review(Scope.for_user(owner), review.id, %{comment_policy: :logged_in_only})

      parent =
        Crit.Repo.insert!(%Crit.Comment{
          review_id: review.id,
          start_line: 1,
          end_line: 1,
          body: "p",
          scope: "line"
        })

      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      view
      |> render_hook("add_reply", %{"comment_id" => parent.id, "body" => "no"})

      assert [seen] = Reviews.list_comments(review.id)
      assert seen.id == parent.id
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

  # The review-conversation, file tree, and comments panel are all populated by
  # document-renderer.js (a phx-hook) inside `#crit-main-layout`. Only
  # `#document-renderer` reads dynamic Elixir attrs and is itself
  # phx-update="ignore" — the rest of the subtree must also be marked ignored,
  # otherwise any LV diff (e.g. flipping comment_policy) would morphdom-patch
  # the JS-rendered children back to the empty template and existing comments
  # would visually disappear. Regression for the bug where switching policy
  # wiped the review-level comments section.
  describe "JS-rendered comment surfaces survive LV patches" do
    test "main layout is phx-update=\"ignore\" so renderer-managed children persist",
         %{conn: conn} do
      owner = owner_fixture()
      review = review_fixture(user_id: owner.id)

      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")
      assert has_element?(view, "#crit-main-layout[phx-update=\"ignore\"]")
      assert has_element?(view, "#reviewConversation")
      assert has_element?(view, "#document-renderer[phx-update=\"ignore\"]")
    end

    test "owner flipping policy to :disallowed does not remove existing comments", %{conn: conn} do
      owner = owner_fixture()
      review = review_fixture(user_id: owner.id)
      _review_comment = comment_fixture(review, %{"scope" => "review", "body" => "review-level"})
      _line_comment = comment_fixture(review, %{"scope" => "line", "body" => "line-level"})

      conn = log_in(conn, owner)
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      view |> element("[data-test=comment-policy-set-disallowed]") |> render_click()

      # JS-rendered comment surfaces stay structurally present.
      assert has_element?(view, "#crit-main-layout[phx-update=\"ignore\"]")
      assert has_element?(view, "#reviewConversation")

      # Existing comments are not destroyed by a policy flip.
      assert length(Reviews.list_comments(review.id)) == 2
    end

    test "anonymous viewer of :logged_in_only review still sees existing comments",
         %{conn: conn} do
      owner = owner_fixture()
      review = review_fixture(user_id: owner.id)
      _review_comment = comment_fixture(review, %{"scope" => "review", "body" => "review-level"})
      _line_comment = comment_fixture(review, %{"scope" => "line", "body" => "line-level"})

      {:ok, _} =
        Reviews.update_review(Scope.for_user(owner), review.id, %{comment_policy: :logged_in_only})

      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      assert has_element?(view, "#crit-main-layout[phx-update=\"ignore\"]")
      assert has_element?(view, "#reviewConversation")
      assert length(Reviews.list_comments(review.id)) == 2
    end

    test "anonymous viewer of :disallowed review still sees existing comments", %{conn: conn} do
      owner = owner_fixture()
      review = review_fixture(user_id: owner.id)
      _review_comment = comment_fixture(review, %{"scope" => "review", "body" => "review-level"})
      _line_comment = comment_fixture(review, %{"scope" => "line", "body" => "line-level"})

      {:ok, _} =
        Reviews.update_review(Scope.for_user(owner), review.id, %{comment_policy: :disallowed})

      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      assert has_element?(view, "#crit-main-layout[phx-update=\"ignore\"]")
      assert has_element?(view, "#reviewConversation")
      assert length(Reviews.list_comments(review.id)) == 2
    end
  end

  # The CSS class `.crit-no-comments` on `.crit-page` hides the gutter "+" and
  # any new-comment composers (CSS in app.css). It MUST be rendered server-side
  # from @can_comment? — earlier iterations toggled it from JS in response to a
  # `policy_changed` push_event, which raced with morphdom and left a stale "+"
  # visible on the gutter when an owner flipped policy to :disallowed. The
  # class is the only thing keeping a viewer from clicking "+" on a disallowed
  # review (the create gates in Reviews still reject the write, but the UI
  # would visually invite the action).
  describe "server-rendered .crit-no-comments class" do
    test ":open viewer (anonymous) does NOT get crit-no-comments", %{conn: conn} do
      owner = owner_fixture()
      review = review_fixture(user_id: owner.id)

      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")
      refute has_element?(view, ".crit-page.crit-no-comments")
    end

    test ":disallowed viewer (anonymous) gets crit-no-comments", %{conn: conn} do
      owner = owner_fixture()
      review = review_fixture(user_id: owner.id)

      {:ok, _} =
        Reviews.update_review(Scope.for_user(owner), review.id, %{comment_policy: :disallowed})

      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")
      assert has_element?(view, ".crit-page.crit-no-comments")
    end

    test ":disallowed owner gets crit-no-comments (creation gated for everyone)",
         %{conn: conn} do
      owner = owner_fixture()
      review = review_fixture(user_id: owner.id)

      {:ok, _} =
        Reviews.update_review(Scope.for_user(owner), review.id, %{comment_policy: :disallowed})

      conn = log_in(conn, owner)
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")
      assert has_element?(view, ".crit-page.crit-no-comments")
    end

    test ":logged_in_only anonymous viewer gets crit-no-comments", %{conn: conn} do
      owner = owner_fixture()
      review = review_fixture(user_id: owner.id)

      {:ok, _} =
        Reviews.update_review(Scope.for_user(owner), review.id, %{comment_policy: :logged_in_only})

      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")
      assert has_element?(view, ".crit-page.crit-no-comments")
    end

    test ":logged_in_only authed viewer does NOT get crit-no-comments", %{conn: conn} do
      owner = owner_fixture()
      other = owner_fixture()
      review = review_fixture(user_id: owner.id)

      {:ok, _} =
        Reviews.update_review(Scope.for_user(owner), review.id, %{comment_policy: :logged_in_only})

      conn = log_in(conn, other)
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")
      refute has_element?(view, ".crit-page.crit-no-comments")
    end

    test "owner flipping :open → :disallowed adds the class without a reload",
         %{conn: conn} do
      owner = owner_fixture()
      review = review_fixture(user_id: owner.id)
      conn = log_in(conn, owner)

      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")
      refute has_element?(view, ".crit-page.crit-no-comments")

      view |> element("[data-test=comment-policy-set-disallowed]") |> render_click()

      assert has_element?(view, ".crit-page.crit-no-comments")
    end
  end
end
