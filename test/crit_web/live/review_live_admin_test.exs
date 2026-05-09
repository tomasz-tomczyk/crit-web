defmodule CritWeb.ReviewLiveAdminTest do
  use CritWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Crit.ReviewsFixtures

  alias Crit.Accounts.Scope
  alias Crit.AccountsFixtures
  alias Crit.Repo
  alias Crit.Reviews

  defp create_admin!(email \\ "admin@example.com") do
    user = AccountsFixtures.user_fixture(%{email: email})
    {:ok, user} = user |> Crit.User.role_changeset(%{role: :admin}) |> Repo.update()
    user
  end

  defp login(conn, user), do: init_test_session(conn, %{user_id: user.id})

  setup do
    Application.put_env(:crit, :selfhosted, false)
    on_exit(fn -> Application.delete_env(:crit, :selfhosted) end)
    :ok
  end

  describe "admin moderation via Reviews context" do
    test "Reviews.delete_review/2 admits an admin scope on someone else's review" do
      owner = AccountsFixtures.user_fixture(%{email: "owner@example.com"})
      review = review_fixture(user_id: owner.id)

      admin = create_admin!()
      assert :ok = Reviews.delete_review(Scope.for_user(admin), review.id)
      refute Repo.get(Crit.Review, review.id)
    end

    test "Reviews.delete_comment/2 admits an admin scope on someone else's comment" do
      review = review_fixture()
      comment = comment_fixture(review)

      admin = create_admin!()
      assert {:ok, _} = Reviews.delete_comment(Scope.for_user(admin), comment.id)
      refute Repo.get(Crit.Comment, comment.id)
    end

    test "Reviews.delete_review/2 still rejects unauthorized non-admin user" do
      owner = AccountsFixtures.user_fixture(%{email: "o@example.com"})
      review = review_fixture(user_id: owner.id)

      stranger = AccountsFixtures.user_fixture(%{email: "s@example.com"})
      assert {:error, :unauthorized} = Reviews.delete_review(Scope.for_user(stranger), review.id)
      assert Repo.get(Crit.Review, review.id)
    end
  end

  describe "review LiveView delete-review button" do
    test "admin sees the delete button on someone else's review", %{conn: conn} do
      owner = AccountsFixtures.user_fixture(%{email: "owner@example.com"})
      review = review_fixture(user_id: owner.id)

      admin = create_admin!()
      conn = login(conn, admin)

      {:ok, _view, html} = live(conn, ~p"/r/#{review.token}")
      assert html =~ "Delete"
    end

    test "non-admin stranger does not see the delete button", %{conn: conn} do
      owner = AccountsFixtures.user_fixture(%{email: "owner@example.com"})
      review = review_fixture(user_id: owner.id)

      stranger = AccountsFixtures.user_fixture(%{email: "s@example.com"})
      conn = login(conn, stranger)

      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")
      refute view |> element("button[phx-click='delete_review']") |> has_element?()
    end

    test "admin clicking delete removes the review", %{conn: conn} do
      owner = AccountsFixtures.user_fixture(%{email: "owner@example.com"})
      review = review_fixture(user_id: owner.id)

      admin = create_admin!()
      conn = login(conn, admin)

      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      view
      |> element("button[phx-click='delete_review']")
      |> render_click()

      refute Repo.get(Crit.Review, review.id)
    end
  end
end
