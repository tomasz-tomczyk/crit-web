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

    test "does not broadcast to PubSub when display name is set", %{conn: conn, review: review} do
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      Phoenix.PubSub.subscribe(Crit.PubSub, "review:#{review.token}")

      view
      |> element("#document-renderer")
      |> render_hook("set_display_name", %{"name" => "Alice"})

      refute_receive {:comments_updated, _}, 100
      refute_receive {:display_name_changed, _}, 100
    end

    test "pushes display_name_updated to sender only", %{conn: conn, review: review} do
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      view
      |> element("#document-renderer")
      |> render_hook("set_display_name", %{"name" => "Alice"})

      assert_push_event view, "display_name_updated", %{display_name: "Alice"}
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

  describe "PubSub handle_info forwarding" do
    test "comments_full_sync pushes comments_full_sync event", %{conn: conn, review: review} do
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      comments = Reviews.list_comments(review) |> Enum.map(&Reviews.serialize_comment/1)

      Phoenix.PubSub.broadcast(
        Crit.PubSub,
        "review:#{review.token}",
        {:comments_full_sync, comments}
      )

      assert_push_event view, "comments_full_sync", %{comments: _comments}
    end

    test "comment_added pushes comment_added event", %{conn: conn, review: review} do
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      payload = %{comment: %{id: Ecto.UUID.generate(), body: "test", author_identity: "someone"}}

      Phoenix.PubSub.broadcast(
        Crit.PubSub,
        "review:#{review.token}",
        {:comment_added, payload}
      )

      assert_push_event view, "comment_added", %{comment: %{body: "test"}}
    end

    test "comment_updated pushes comment_updated event", %{conn: conn, review: review} do
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      id = Ecto.UUID.generate()

      Phoenix.PubSub.broadcast(
        Crit.PubSub,
        "review:#{review.token}",
        {:comment_updated,
         %{id: id, body: "updated", updated_at: DateTime.to_iso8601(DateTime.utc_now())}}
      )

      assert_push_event view, "comment_updated", %{id: ^id, body: "updated"}
    end

    test "comment_deleted pushes comment_deleted event", %{conn: conn, review: review} do
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      id = Ecto.UUID.generate()

      Phoenix.PubSub.broadcast(
        Crit.PubSub,
        "review:#{review.token}",
        {:comment_deleted, %{id: id}}
      )

      assert_push_event view, "comment_deleted", %{id: ^id}
    end

    test "comment_resolved pushes comment_resolved event", %{conn: conn, review: review} do
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      id = Ecto.UUID.generate()

      Phoenix.PubSub.broadcast(
        Crit.PubSub,
        "review:#{review.token}",
        {:comment_resolved, %{id: id, resolved: true}}
      )

      assert_push_event view, "comment_resolved", %{id: ^id, resolved: true}
    end

    test "reply_added pushes reply_added event", %{conn: conn, review: review} do
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      parent_id = Ecto.UUID.generate()

      payload = %{
        parent_id: parent_id,
        reply: %{id: Ecto.UUID.generate(), body: "reply", author_identity: "someone"}
      }

      Phoenix.PubSub.broadcast(
        Crit.PubSub,
        "review:#{review.token}",
        {:reply_added, payload}
      )

      assert_push_event view, "reply_added", %{parent_id: ^parent_id, reply: %{body: "reply"}}
    end

    test "reply_updated pushes reply_updated event", %{conn: conn, review: review} do
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      id = Ecto.UUID.generate()
      parent_id = Ecto.UUID.generate()

      Phoenix.PubSub.broadcast(
        Crit.PubSub,
        "review:#{review.token}",
        {:reply_updated, %{parent_id: parent_id, id: id, body: "edited reply"}}
      )

      assert_push_event view, "reply_updated", %{
        parent_id: ^parent_id,
        id: ^id,
        body: "edited reply"
      }
    end

    test "reply_deleted pushes reply_deleted event", %{conn: conn, review: review} do
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      id = Ecto.UUID.generate()
      parent_id = Ecto.UUID.generate()

      Phoenix.PubSub.broadcast(
        Crit.PubSub,
        "review:#{review.token}",
        {:reply_deleted, %{parent_id: parent_id, id: id}}
      )

      assert_push_event view, "reply_deleted", %{parent_id: ^parent_id, id: ^id}
    end

    test "display_name_changed pushes display_name_changed event", %{conn: conn, review: review} do
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      identity = Ecto.UUID.generate()

      Phoenix.PubSub.broadcast(
        Crit.PubSub,
        "review:#{review.token}",
        {:display_name_changed, %{identity: identity, name: "New Name"}}
      )

      assert_push_event view, "display_name_changed", %{identity: ^identity, name: "New Name"}
    end
  end

  describe "delta broadcasts from mutations" do
    test "add_comment pushes comment_added to sender", %{conn: conn, review: review} do
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      view
      |> element("#document-renderer")
      |> render_hook("add_comment", %{
        "start_line" => 1,
        "end_line" => 2,
        "body" => "Delta test"
      })

      assert_push_event view, "comment_added", %{comment: comment}
      assert comment.body == "Delta test"
      assert comment.start_line == 1
      assert comment.end_line == 2
      assert is_binary(comment.id)
      assert is_binary(comment.created_at)
      assert is_binary(comment.updated_at)
    end

    test "add_comment broadcasts comment_added to other viewers", %{conn: conn, review: review} do
      Phoenix.PubSub.subscribe(Crit.PubSub, "review:#{review.token}")

      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      view
      |> element("#document-renderer")
      |> render_hook("add_comment", %{
        "start_line" => 1,
        "end_line" => 1,
        "body" => "Broadcast test"
      })

      assert_receive {:comment_added, %{comment: comment}}, 500
      assert comment.body == "Broadcast test"
    end

    test "add_comment payload matches serialize_comment/1 shape", %{conn: conn, review: review} do
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      view
      |> element("#document-renderer")
      |> render_hook("add_comment", %{
        "start_line" => 1,
        "end_line" => 1,
        "body" => "Shape test"
      })

      assert_push_event view, "comment_added", %{comment: comment}

      expected_keys =
        MapSet.new([
          :id,
          :start_line,
          :end_line,
          :body,
          :quote,
          :scope,
          :author_identity,
          :author_display_name,
          :review_round,
          :file_path,
          :resolved,
          :external_id,
          :created_at,
          :updated_at,
          :replies
        ])

      assert MapSet.new(Map.keys(comment)) == expected_keys
      assert comment.replies == []
    end

    test "edit_comment pushes comment_updated with id, body, updated_at", %{
      conn: conn,
      review: review
    } do
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      view
      |> element("#document-renderer")
      |> render_hook("add_comment", %{
        "start_line" => 1,
        "end_line" => 1,
        "body" => "Original"
      })

      [comment] = Reviews.list_comments(review)

      view
      |> element("#document-renderer")
      |> render_hook("edit_comment", %{"id" => comment.id, "body" => "Edited"})

      assert_push_event view, "comment_updated", %{id: id, body: "Edited", updated_at: updated_at}
      assert id == comment.id
      assert is_binary(updated_at)
    end

    test "edit_comment broadcasts comment_updated to other viewers", %{
      conn: conn,
      review: review
    } do
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      view
      |> element("#document-renderer")
      |> render_hook("add_comment", %{
        "start_line" => 1,
        "end_line" => 1,
        "body" => "Original"
      })

      [comment] = Reviews.list_comments(review)

      Phoenix.PubSub.subscribe(Crit.PubSub, "review:#{review.token}")

      view
      |> element("#document-renderer")
      |> render_hook("edit_comment", %{"id" => comment.id, "body" => "Edited"})

      assert_receive {:comment_updated, %{id: _, body: "Edited", updated_at: _}}, 500
    end

    test "delete_comment pushes comment_deleted with id", %{conn: conn, review: review} do
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      view
      |> element("#document-renderer")
      |> render_hook("add_comment", %{
        "start_line" => 1,
        "end_line" => 1,
        "body" => "To delete"
      })

      [comment] = Reviews.list_comments(review)

      view
      |> element("#document-renderer")
      |> render_hook("delete_comment", %{"id" => comment.id})

      assert_push_event view, "comment_deleted", %{id: id}
      assert id == comment.id
    end

    test "delete_comment broadcasts comment_deleted to other viewers", %{
      conn: conn,
      review: review
    } do
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      view
      |> element("#document-renderer")
      |> render_hook("add_comment", %{
        "start_line" => 1,
        "end_line" => 1,
        "body" => "To delete"
      })

      [comment] = Reviews.list_comments(review)

      Phoenix.PubSub.subscribe(Crit.PubSub, "review:#{review.token}")

      view
      |> element("#document-renderer")
      |> render_hook("delete_comment", %{"id" => comment.id})

      assert_receive {:comment_deleted, %{id: _}}, 500
    end

    test "resolve_comment pushes comment_resolved with id and resolved flag", %{
      conn: conn,
      review: review
    } do
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      view
      |> element("#document-renderer")
      |> render_hook("add_comment", %{
        "start_line" => 1,
        "end_line" => 1,
        "body" => "Resolve me"
      })

      [comment] = Reviews.list_comments(review)

      view
      |> element("#document-renderer")
      |> render_hook("resolve_comment", %{"id" => comment.id, "resolved" => true})

      assert_push_event view, "comment_resolved", %{id: id, resolved: true}
      assert id == comment.id
    end

    test "resolve_comment broadcasts comment_resolved to other viewers", %{
      conn: conn,
      review: review
    } do
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      view
      |> element("#document-renderer")
      |> render_hook("add_comment", %{
        "start_line" => 1,
        "end_line" => 1,
        "body" => "Resolve me"
      })

      [comment] = Reviews.list_comments(review)

      Phoenix.PubSub.subscribe(Crit.PubSub, "review:#{review.token}")

      view
      |> element("#document-renderer")
      |> render_hook("resolve_comment", %{"id" => comment.id, "resolved" => true})

      assert_receive {:comment_resolved, %{id: _, resolved: true}}, 500
    end

    test "add_reply pushes reply_added with parent_id and serialized reply", %{
      conn: conn,
      review: review
    } do
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      view
      |> element("#document-renderer")
      |> render_hook("add_comment", %{
        "start_line" => 1,
        "end_line" => 1,
        "body" => "Parent"
      })

      [comment] = Reviews.list_comments(review)

      view
      |> element("#document-renderer")
      |> render_hook("add_reply", %{"comment_id" => comment.id, "body" => "My reply"})

      assert_push_event view, "reply_added", %{parent_id: parent_id, reply: reply}
      assert parent_id == comment.id
      assert reply.body == "My reply"
      assert is_binary(reply.id)
      assert is_binary(reply.created_at)
      assert Map.has_key?(reply, :author_identity)
      assert Map.has_key?(reply, :author_display_name)
    end

    test "add_reply broadcasts reply_added to other viewers", %{conn: conn, review: review} do
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      view
      |> element("#document-renderer")
      |> render_hook("add_comment", %{
        "start_line" => 1,
        "end_line" => 1,
        "body" => "Parent"
      })

      [comment] = Reviews.list_comments(review)

      Phoenix.PubSub.subscribe(Crit.PubSub, "review:#{review.token}")

      view
      |> element("#document-renderer")
      |> render_hook("add_reply", %{"comment_id" => comment.id, "body" => "Broadcast reply"})

      assert_receive {:reply_added, %{parent_id: _, reply: %{body: "Broadcast reply"}}}, 500
    end

    test "edit_reply pushes reply_updated with parent_id, id, body", %{
      conn: conn,
      review: review
    } do
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      view
      |> element("#document-renderer")
      |> render_hook("add_comment", %{
        "start_line" => 1,
        "end_line" => 1,
        "body" => "Parent"
      })

      [comment] = Reviews.list_comments(review)

      view
      |> element("#document-renderer")
      |> render_hook("add_reply", %{"comment_id" => comment.id, "body" => "Original reply"})

      [updated_comment] = Reviews.list_comments(review)
      [reply] = updated_comment.replies

      view
      |> element("#document-renderer")
      |> render_hook("edit_reply", %{"id" => reply.id, "body" => "Edited reply"})

      assert_push_event view, "reply_updated", %{
        parent_id: parent_id,
        id: reply_id,
        body: "Edited reply"
      }

      assert parent_id == comment.id
      assert reply_id == reply.id
    end

    test "delete_reply pushes reply_deleted with parent_id and id", %{
      conn: conn,
      review: review
    } do
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      view
      |> element("#document-renderer")
      |> render_hook("add_comment", %{
        "start_line" => 1,
        "end_line" => 1,
        "body" => "Parent"
      })

      [comment] = Reviews.list_comments(review)

      view
      |> element("#document-renderer")
      |> render_hook("add_reply", %{"comment_id" => comment.id, "body" => "To delete"})

      [updated_comment] = Reviews.list_comments(review)
      [reply] = updated_comment.replies

      view
      |> element("#document-renderer")
      |> render_hook("delete_reply", %{"id" => reply.id})

      assert_push_event view, "reply_deleted", %{parent_id: parent_id, id: reply_id}
      assert parent_id == comment.id
      assert reply_id == reply.id
    end

    test "unauthorized edit does not broadcast", %{conn: conn, review: review} do
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

      Phoenix.PubSub.subscribe(Crit.PubSub, "review:#{review.token}")

      view
      |> element("#document-renderer")
      |> render_hook("edit_comment", %{"id" => comment.id, "body" => "Hacked"})

      refute_receive {:comment_updated, _}, 100
    end

    test "unauthorized delete does not broadcast", %{conn: conn, review: review} do
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

      Phoenix.PubSub.subscribe(Crit.PubSub, "review:#{review.token}")

      view
      |> element("#document-renderer")
      |> render_hook("delete_comment", %{"id" => comment.id})

      refute_receive {:comment_deleted, _}, 100
    end

    test "noop_refresh broadcasts comments_full_sync with all comments", %{
      conn: conn,
      review: review
    } do
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      view
      |> element("#document-renderer")
      |> render_hook("add_comment", %{
        "start_line" => 1,
        "end_line" => 1,
        "body" => "Sync test"
      })

      # noop_refresh uses broadcast (not broadcast_from), so all subscribers get it
      Phoenix.PubSub.subscribe(Crit.PubSub, "review:#{review.token}")

      view
      |> element("#document-renderer")
      |> render_hook("noop_refresh", %{})

      assert_receive {:comments_full_sync, comments}, 500
      assert length(comments) == 1
      assert hd(comments).body == "Sync test"
    end
  end

  describe "demo mode filtering in handle_info" do
    setup %{conn: conn} do
      Application.put_env(:crit, :demo_review_token, "demo-token-123")

      {:ok, review} =
        Reviews.create_review(
          [%{"path" => "demo.md", "content" => "# Demo"}],
          0,
          []
        )

      # Override the review token to match the demo config
      review
      |> Ecto.Changeset.change(token: "demo-token-123")
      |> Crit.Repo.update!()

      review = Reviews.get_by_token("demo-token-123")

      on_exit(fn -> Application.delete_env(:crit, :demo_review_token) end)

      %{conn: conn, demo_review: review}
    end

    test "drops comment_added from foreign identity in demo mode", %{
      conn: conn,
      demo_review: review
    } do
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      foreign_identity = Ecto.UUID.generate()

      payload = %{
        comment: %{
          id: Ecto.UUID.generate(),
          body: "foreign",
          author_identity: foreign_identity
        }
      }

      Phoenix.PubSub.broadcast(
        Crit.PubSub,
        "review:#{review.token}",
        {:comment_added, payload}
      )

      refute_push_event view, "comment_added", %{}
    end

    test "passes comment_added for imported identity in demo mode", %{
      conn: conn,
      demo_review: review
    } do
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      payload = %{
        comment: %{
          id: Ecto.UUID.generate(),
          body: "imported comment",
          author_identity: "imported"
        }
      }

      Phoenix.PubSub.broadcast(
        Crit.PubSub,
        "review:#{review.token}",
        {:comment_added, payload}
      )

      assert_push_event view, "comment_added", %{comment: %{author_identity: "imported"}}
    end

    test "passes comment_updated even without author_identity in demo mode", %{
      conn: conn,
      demo_review: review
    } do
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      Phoenix.PubSub.broadcast(
        Crit.PubSub,
        "review:#{review.token}",
        {:comment_updated,
         %{
           id: Ecto.UUID.generate(),
           body: "updated body",
           updated_at: DateTime.to_iso8601(DateTime.utc_now())
         }}
      )

      assert_push_event view, "comment_updated", %{body: "updated body"}
    end

    test "drops reply_added from foreign identity in demo mode", %{
      conn: conn,
      demo_review: review
    } do
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      foreign_identity = Ecto.UUID.generate()

      payload = %{
        parent_id: Ecto.UUID.generate(),
        reply: %{
          id: Ecto.UUID.generate(),
          body: "foreign reply",
          author_identity: foreign_identity
        }
      }

      Phoenix.PubSub.broadcast(
        Crit.PubSub,
        "review:#{review.token}",
        {:reply_added, payload}
      )

      refute_push_event view, "reply_added", %{}
    end

    test "passes reply_added for own identity in demo mode", %{
      conn: conn,
      demo_review: review
    } do
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

      # Get the identity assigned during mount
      own_identity = :sys.get_state(view.pid).socket.assigns.identity

      payload = %{
        parent_id: Ecto.UUID.generate(),
        reply: %{
          id: Ecto.UUID.generate(),
          body: "own reply",
          author_identity: own_identity
        }
      }

      Phoenix.PubSub.broadcast(
        Crit.PubSub,
        "review:#{review.token}",
        {:reply_added, payload}
      )

      assert_push_event view, "reply_added", %{reply: %{body: "own reply"}}
    end
  end
end
