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

  test "owner of an unlisted review sees Make public with confirm prompt and can promote", %{
    conn: conn
  } do
    user = owner_fixture()
    review = review_fixture(user_id: user.id)
    conn = log_in(conn, user)

    {:ok, view, html} = live(conn, ~p"/r/#{review.token}")
    assert html =~ "Make public"
    assert has_element?(view, "[data-test=make-public][data-confirm]")

    rendered = view |> element("[data-test=make-public]") |> render_click()

    assert Reviews.get_by_token(review.token).visibility == :public
    assert rendered =~ "search engines may index it"
    refute rendered =~ "Make public"
    assert rendered =~ "Public"
  end

  test "owner of an already-public review sees a Public badge with delete-to-unlist tooltip", %{
    conn: conn
  } do
    user = owner_fixture()
    review = review_fixture(user_id: user.id)
    {:ok, _} = Reviews.make_public(Scope.for_user(user), review.id)
    conn = log_in(conn, user)

    {:ok, _view, html} = live(conn, ~p"/r/#{review.token}")
    refute html =~ "Make public"
    assert html =~ "Public"
    assert html =~ "delete the review to unlist"
  end

  test "non-owner sees the Unlisted badge but no make-public button", %{conn: conn} do
    owner = owner_fixture()
    other = owner_fixture()
    review = review_fixture(user_id: owner.id)
    conn = log_in(conn, other)

    {:ok, _view, html} = live(conn, ~p"/r/#{review.token}")
    refute html =~ "Make public"
    assert html =~ "Unlisted"
  end

  test "anonymous visitor sees the Unlisted badge but no make-public button", %{conn: conn} do
    owner = owner_fixture()
    review = review_fixture(user_id: owner.id)

    {:ok, _view, html} = live(conn, ~p"/r/#{review.token}")
    refute html =~ "Make public"
    assert html =~ "Unlisted"
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
