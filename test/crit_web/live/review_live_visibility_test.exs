defmodule CritWeb.ReviewLiveVisibilityTest do
  use CritWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Crit.ReviewsFixtures

  alias Crit.Accounts.Scope
  alias Crit.Reviews

  defp owner_fixture do
    {:ok, user} =
      Crit.Accounts.find_or_create_from_oauth("github", %{
        "sub" => "vis-#{System.unique_integer([:positive])}",
        "email" => "vis-#{System.unique_integer([:positive])}@example.com",
        "name" => "Owner"
      })

    user
  end

  defp log_in(conn, user), do: init_test_session(conn, %{user_id: user.id})

  setup do
    Application.put_env(:crit, :selfhosted, false)
    on_exit(fn -> Application.delete_env(:crit, :selfhosted) end)
    :ok
  end

  test "owner of an unlisted review sees the Unlisted dropdown and can promote to Public", %{
    conn: conn
  } do
    user = owner_fixture()
    review = review_fixture(user_id: user.id)
    conn = log_in(conn, user)

    {:ok, view, html} = live(conn, ~p"/r/#{review.token}")
    assert html =~ "Unlisted"
    assert has_element?(view, "[data-test=visibility-menu]")
    assert has_element?(view, "[data-test=make-public][data-confirm]")

    rendered = view |> element("[data-test=make-public]") |> render_click()

    assert Reviews.get_by_token(review.token).visibility == :public
    assert rendered =~ "Review is now public"
    assert rendered =~ "Search engines may index it"
    refute rendered =~ "Unlisted"
    assert rendered =~ "Public"
  end

  test "owner of an already-public review sees the Public status pill and no menu", %{
    conn: conn
  } do
    user = owner_fixture()
    review = review_fixture(user_id: user.id)
    {:ok, _} = Reviews.make_public(Scope.for_user(user), review.id)
    conn = log_in(conn, user)

    {:ok, view, html} = live(conn, ~p"/r/#{review.token}")
    refute has_element?(view, "[data-test=visibility-menu]")
    refute has_element?(view, "[data-test=make-public]")
    assert html =~ "Public"
    assert html =~ "To remove access, delete the review"
  end

  test "non-owner sees a read-only Unlisted badge but no menu or make-public button", %{
    conn: conn
  } do
    owner = owner_fixture()
    other = owner_fixture()
    review = review_fixture(user_id: owner.id)
    conn = log_in(conn, other)

    {:ok, view, html} = live(conn, ~p"/r/#{review.token}")
    refute has_element?(view, "[data-test=visibility-menu]")
    refute has_element?(view, "[data-test=make-public]")
    assert html =~ "Unlisted"
  end

  test "anonymous visitor sees a read-only Unlisted badge", %{conn: conn} do
    owner = owner_fixture()
    review = review_fixture(user_id: owner.id)

    {:ok, view, html} = live(conn, ~p"/r/#{review.token}")
    refute has_element?(view, "[data-test=visibility-menu]")
    refute has_element?(view, "[data-test=make-public]")
    assert html =~ "Unlisted"
  end

  test "non-owner viewing a public review sees a read-only Public badge", %{conn: conn} do
    owner = owner_fixture()
    other = owner_fixture()
    review = review_fixture(user_id: owner.id)
    {:ok, _} = Reviews.make_public(Scope.for_user(owner), review.id)
    conn = log_in(conn, other)

    {:ok, view, html} = live(conn, ~p"/r/#{review.token}")
    refute has_element?(view, "[data-test=visibility-menu]")
    refute has_element?(view, "[data-test=make-public]")
    assert html =~ "Public"
    assert html =~ "indexed by search engines"
  end

  test "public review renders without noindex meta and with canonical link", %{conn: conn} do
    user = owner_fixture()
    review = review_fixture(user_id: user.id)
    {:ok, _} = Reviews.make_public(Scope.for_user(user), review.id)

    {:ok, _view, html} = live(conn, ~p"/r/#{review.token}")
    refute html =~ ~s(name="robots" content="noindex, nofollow")
    assert html =~ ~s(rel="canonical")
  end
end
