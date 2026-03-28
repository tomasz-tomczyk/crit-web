defmodule CritWeb.ReviewLiveTest do
  use CritWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Crit.ReviewsFixtures

  alias Crit.Reviews

  setup do
    Application.put_env(:crit, :selfhosted, false)
    on_exit(fn -> Application.delete_env(:crit, :selfhosted) end)
    review = review_fixture()
    %{review: review}
  end

  describe "mount" do
    test "renders review page with file path", %{conn: conn, review: review} do
      {:ok, _view, html} = live(conn, ~p"/r/#{review.token}")
      assert html =~ hd(review.files).file_path
    end

    test "redirects to home for invalid token", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/r/nonexistent-token")
    end

    test "sets page title to first file path", %{conn: conn, review: review} do
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")
      assert page_title(view) =~ hd(review.files).file_path
    end
  end

  describe "mount with multi-file review" do
    test "sets page title to first file path", %{conn: conn} do
      {:ok, review} =
        Reviews.create_review(
          [
            %{"path" => "main.go", "content" => "pkg main"},
            %{"path" => "util.go", "content" => "pkg util"}
          ],
          0,
          []
        )

      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")
      assert page_title(view) =~ "main.go"
    end
  end

  describe "add_comment with file_path" do
    test "creates comment with file_path param", %{conn: conn} do
      {:ok, review} =
        Reviews.create_review(
          [%{"path" => "main.go", "content" => "pkg main"}],
          0,
          []
        )

      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      view
      |> element("#document-renderer")
      |> render_hook("add_comment", %{
        "start_line" => 1,
        "end_line" => 1,
        "body" => "Fix this",
        "file_path" => "main.go"
      })

      comments = Reviews.list_comments(review)
      assert length(comments) == 1
      assert hd(comments).file_path == "main.go"
    end
  end

  describe "add_comment" do
    test "creates a comment", %{conn: conn, review: review} do
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      view
      |> element("#document-renderer")
      |> render_hook("add_comment", %{
        "start_line" => 1,
        "end_line" => 2,
        "body" => "Great work!"
      })

      comments = Reviews.list_comments(review)
      assert length(comments) == 1
      assert hd(comments).body == "Great work!"
      assert hd(comments).start_line == 1
      assert hd(comments).end_line == 2
    end
  end

  describe "edit_comment" do
    test "updates own comment", %{conn: conn, review: review} do
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      view
      |> element("#document-renderer")
      |> render_hook("add_comment", %{
        "start_line" => 1,
        "end_line" => 1,
        "body" => "Original body"
      })

      [comment] = Reviews.list_comments(review)

      view
      |> element("#document-renderer")
      |> render_hook("edit_comment", %{
        "id" => comment.id,
        "body" => "Updated body"
      })

      [updated] = Reviews.list_comments(review)
      assert updated.body == "Updated body"
    end

    test "cannot edit another user's comment", %{conn: conn, review: review} do
      other_identity = Ecto.UUID.generate()

      {:ok, _other_comment} =
        Reviews.create_comment(
          review,
          %{"start_line" => 1, "end_line" => 1, "body" => "Other's comment"},
          other_identity,
          nil
        )

      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      [comment] = Reviews.list_comments(review)

      view
      |> element("#document-renderer")
      |> render_hook("edit_comment", %{
        "id" => comment.id,
        "body" => "Hacked body"
      })

      [unchanged] = Reviews.list_comments(review)
      assert unchanged.body == "Other's comment"
    end
  end

  describe "delete_comment" do
    test "removes own comment", %{conn: conn, review: review} do
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      view
      |> element("#document-renderer")
      |> render_hook("add_comment", %{
        "start_line" => 1,
        "end_line" => 1,
        "body" => "To be deleted"
      })

      [comment] = Reviews.list_comments(review)

      view
      |> element("#document-renderer")
      |> render_hook("delete_comment", %{"id" => comment.id})

      assert Reviews.list_comments(review) == []
    end

    test "cannot delete another user's comment", %{conn: conn, review: review} do
      other_identity = Ecto.UUID.generate()

      {:ok, _other_comment} =
        Reviews.create_comment(
          review,
          %{"start_line" => 1, "end_line" => 1, "body" => "Other's comment"},
          other_identity,
          nil
        )

      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      [comment] = Reviews.list_comments(review)

      view
      |> element("#document-renderer")
      |> render_hook("delete_comment", %{"id" => comment.id})

      assert length(Reviews.list_comments(review)) == 1
    end
  end

  describe "set_display_name" do
    test "updates assign and reflects in new comments", %{conn: conn, review: review} do
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      view
      |> element("#document-renderer")
      |> render_hook("set_display_name", %{"name" => "Alice"})

      view
      |> element("#document-renderer")
      |> render_hook("add_comment", %{
        "start_line" => 1,
        "end_line" => 1,
        "body" => "Named comment"
      })

      [comment] = Reviews.list_comments(review)
      assert comment.author_display_name == "Alice"
    end

    test "broadcasts comments when display name is set", %{conn: conn, review: review} do
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      # Subscribe to verify broadcast fires
      Phoenix.PubSub.subscribe(Crit.PubSub, "review:#{review.token}")

      view
      |> element("#document-renderer")
      |> render_hook("set_display_name", %{"name" => "Alice"})

      assert_receive {:comments_updated, _comments}, 500
    end

    test "ignores blank names", %{conn: conn, review: review} do
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      view
      |> element("#document-renderer")
      |> render_hook("set_display_name", %{"name" => "Bob"})

      view
      |> element("#document-renderer")
      |> render_hook("set_display_name", %{"name" => "   "})

      view
      |> element("#document-renderer")
      |> render_hook("add_comment", %{
        "start_line" => 1,
        "end_line" => 1,
        "body" => "Still Bob"
      })

      [comment] = Reviews.list_comments(review)
      assert comment.author_display_name == "Bob"
    end
  end

  describe "prompt mode" do
    test "renders split button with dropdown", %{conn: conn, review: review} do
      {:ok, _view, html} = live(conn, ~p"/r/#{review.token}")
      assert html =~ "Get prompt"
      assert html =~ "crit-split-btn"
      assert html =~ "Act on comments"
      assert html =~ "Full plan + comments"
    end

    test "defaults to local prompt mode", %{conn: conn, review: review} do
      {:ok, _view, html} = live(conn, ~p"/r/#{review.token}")
      assert html =~ "Act on comments"
      assert html =~ "crit fetch"
      assert html =~ "crit share"
    end

    test "switches to full_export mode", %{conn: conn, review: review} do
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      html =
        view
        |> element("#crit-prompt-panel")
        |> render()

      assert html =~ "crit fetch"

      render_click(view, "set_prompt_mode", %{"mode" => "full_export"})

      html =
        view
        |> element("#crit-prompt-panel")
        |> render()

      assert html =~ "/api/export/#{review.token}/review"
      assert html =~ "Full plan + comments"
    end

    test "switches back to local mode", %{conn: conn, review: review} do
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      render_click(view, "set_prompt_mode", %{"mode" => "full_export"})
      render_click(view, "set_prompt_mode", %{"mode" => "local"})

      html =
        view
        |> element("#crit-prompt-panel")
        |> render()

      assert html =~ "crit fetch"
      assert html =~ "Act on comments"
    end
  end

  describe "PubSub" do
    test "receiving comments_updated broadcast does not crash", %{conn: conn, review: review} do
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      comments = Reviews.list_comments(review)

      Phoenix.PubSub.broadcast(
        Crit.PubSub,
        "review:#{review.token}",
        {:comments_updated, comments}
      )

      Process.sleep(50)

      assert render(view) =~ hd(review.files).file_path
    end
  end
end
