defmodule CritWeb.ReviewControllerTest do
  use CritWeb.ConnCase, async: true

  import Crit.ReviewsFixtures

  alias Crit.Reviews

  describe "POST /set-name" do
    test "updates display name on existing comments", %{conn: conn} do
      review = review_fixture()
      identity = Ecto.UUID.generate()

      {:ok, _} =
        Reviews.create_comment(
          review,
          %{"start_line" => 1, "end_line" => 1, "body" => "Old name comment"},
          identity,
          "OldName"
        )

      conn =
        conn
        |> init_test_session(%{"identity" => identity})
        |> post(~p"/set-name", %{"name" => "NewName"})

      assert json_response(conn, 200)["ok"] == true

      [comment] = Reviews.list_comments(review)
      assert comment.author_display_name == "NewName"
    end

    test "updates comments across multiple reviews", %{conn: conn} do
      review1 = review_fixture()
      review2 = review_fixture(%{files: [%{"path" => "b.md", "content" => "# B"}]})
      identity = Ecto.UUID.generate()

      {:ok, _} =
        Reviews.create_comment(
          review1,
          %{"start_line" => 1, "end_line" => 1, "body" => "R1"},
          identity,
          "Old"
        )

      {:ok, _} =
        Reviews.create_comment(
          review2,
          %{"start_line" => 1, "end_line" => 1, "body" => "R2"},
          identity,
          "Old"
        )

      conn
      |> init_test_session(%{"identity" => identity})
      |> post(~p"/set-name", %{"name" => "New"})

      assert hd(Reviews.list_comments(review1)).author_display_name == "New"
      assert hd(Reviews.list_comments(review2)).author_display_name == "New"
    end

    test "does not update other users' comments", %{conn: conn} do
      review = review_fixture()
      my_identity = Ecto.UUID.generate()
      other_identity = Ecto.UUID.generate()

      {:ok, _} =
        Reviews.create_comment(
          review,
          %{"start_line" => 1, "end_line" => 1, "body" => "Mine"},
          my_identity,
          "OldMe"
        )

      {:ok, _} =
        Reviews.create_comment(
          review,
          %{"start_line" => 2, "end_line" => 2, "body" => "Theirs"},
          other_identity,
          "Other"
        )

      conn
      |> init_test_session(%{"identity" => my_identity})
      |> post(~p"/set-name", %{"name" => "NewMe"})

      comments = Reviews.list_comments(review)
      mine = Enum.find(comments, &(&1.author_identity == my_identity))
      theirs = Enum.find(comments, &(&1.author_identity == other_identity))

      assert mine.author_display_name == "NewMe"
      assert theirs.author_display_name == "Other"
    end

    test "returns 422 for blank name", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{"identity" => Ecto.UUID.generate()})
        |> post(~p"/set-name", %{"name" => "   "})

      assert json_response(conn, 422)["error"] =~ "blank"
    end

    test "returns 422 when name param is missing", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{"identity" => Ecto.UUID.generate()})
        |> post(~p"/set-name", %{})

      assert json_response(conn, 422)["error"] =~ "required"
    end

    test "broadcasts display_name_changed, not comments_updated", %{conn: conn} do
      review = review_fixture()
      identity = Ecto.UUID.generate()

      {:ok, _} =
        Reviews.create_comment(
          review,
          %{"start_line" => 1, "end_line" => 1, "body" => "test"},
          identity,
          "OldName"
        )

      Phoenix.PubSub.subscribe(Crit.PubSub, "review:#{review.token}")

      conn
      |> init_test_session(%{"identity" => identity})
      |> post(~p"/set-name", %{"name" => "NewName"})

      assert_receive {:display_name_changed, %{identity: ^identity, name: "NewName"}}, 500
      refute_receive {:comments_updated, _}, 100
    end

    test "broadcasts to all affected review topics", %{conn: conn} do
      review1 = review_fixture()
      review2 = review_fixture(%{files: [%{"path" => "b.md", "content" => "# B"}]})
      identity = Ecto.UUID.generate()

      {:ok, _} =
        Reviews.create_comment(
          review1,
          %{"start_line" => 1, "end_line" => 1, "body" => "R1"},
          identity,
          "Old"
        )

      {:ok, _} =
        Reviews.create_comment(
          review2,
          %{"start_line" => 1, "end_line" => 1, "body" => "R2"},
          identity,
          "Old"
        )

      Phoenix.PubSub.subscribe(Crit.PubSub, "review:#{review1.token}")
      Phoenix.PubSub.subscribe(Crit.PubSub, "review:#{review2.token}")

      conn
      |> init_test_session(%{"identity" => identity})
      |> post(~p"/set-name", %{"name" => "BothReviews"})

      assert_receive {:display_name_changed, %{identity: ^identity, name: "BothReviews"}}, 500
      assert_receive {:display_name_changed, %{identity: ^identity, name: "BothReviews"}}, 500
    end

    test "display_name_changed payload contains identity and name", %{conn: conn} do
      review = review_fixture()
      identity = Ecto.UUID.generate()

      {:ok, _} =
        Reviews.create_comment(
          review,
          %{"start_line" => 1, "end_line" => 1, "body" => "test"},
          identity,
          "Old"
        )

      Phoenix.PubSub.subscribe(Crit.PubSub, "review:#{review.token}")

      conn
      |> init_test_session(%{"identity" => identity})
      |> post(~p"/set-name", %{"name" => "PayloadCheck"})

      assert_receive {:display_name_changed, payload}, 500
      assert payload == %{identity: identity, name: "PayloadCheck"}
    end
  end
end
