defmodule CritWeb.ApiControllerTest do
  use CritWeb.ConnCase

  alias Crit.Reviews

  defp create_review do
    {:ok, review} =
      Reviews.create_review([%{"path" => "test.md", "content" => "# Hello\n\nworld"}], 0, [])

    review
  end

  defp review_token(review) do
    review.token
  end

  describe "POST /api/reviews" do
    test "creates a review and returns url + delete_token", %{conn: conn} do
      body = %{content: "# Hello", filename: "test.md", comments: []}
      conn = post(conn, ~p"/api/reviews", body)
      assert %{"url" => url, "delete_token" => token} = json_response(conn, 201)
      assert String.contains?(url, "/r/")
      assert String.length(token) == 21
    end
  end

  describe "POST /api/reviews with comments" do
    test "creates a review with seed comments", %{conn: conn} do
      comments = [
        %{start_line: 1, end_line: 1, body: "Nice heading", author_identity: "reviewer1"},
        %{start_line: 3, end_line: 3, body: "Good content", author_identity: "reviewer2"}
      ]

      body = %{content: "# Hello\n\nworld", filename: "test.md", comments: comments}
      conn = post(conn, ~p"/api/reviews", body)
      assert %{"url" => url} = json_response(conn, 201)

      token = url |> String.split("/r/") |> List.last()
      list_conn = get(build_conn(), ~p"/api/reviews/#{token}/comments")
      result = json_response(list_conn, 200)
      assert length(result) == 2
    end

    test "rejects more than 500 comments", %{conn: conn} do
      comments =
        for i <- 1..501, do: %{start_line: i, end_line: i, body: "c", author_identity: "a"}

      body = %{content: "# Hello", filename: "test.md", comments: comments}
      conn = post(conn, ~p"/api/reviews", body)
      assert %{"error" => error} = json_response(conn, 422)
      assert error =~ "Too many comments"
    end

    test "rejects empty content", %{conn: conn} do
      body = %{content: "", filename: "test.md", comments: []}
      conn = post(conn, ~p"/api/reviews", body)
      assert %{"error" => _} = json_response(conn, 422)
    end

    test "rejects missing content", %{conn: conn} do
      body = %{filename: "test.md"}
      conn = post(conn, ~p"/api/reviews", body)
      assert %{"error" => error} = json_response(conn, 422)
      assert error =~ "content is required"
    end
  end

  describe "GET /api/reviews/:token/document" do
    test "returns JSON with files for valid token", %{conn: conn} do
      review = create_review()
      token = review_token(review)
      conn = get(conn, ~p"/api/reviews/#{token}/document")
      result = json_response(conn, 200)
      assert length(result["files"]) == 1
      assert hd(result["files"])["path"] == "test.md"
    end

    test "returns JSON with files for multi-file review", %{conn: conn} do
      {:ok, review} =
        Reviews.create_review(
          [%{"path" => "a.go", "content" => "pkg a"}, %{"path" => "b.go", "content" => "pkg b"}],
          0,
          []
        )

      conn = get(conn, ~p"/api/reviews/#{review.token}/document")
      result = json_response(conn, 200)
      assert length(result["files"]) == 2
      paths = Enum.map(result["files"], & &1["path"])
      assert "a.go" in paths
      assert "b.go" in paths
    end

    test "returns 404 for unknown token", %{conn: conn} do
      conn = get(conn, ~p"/api/reviews/nonexistent_token/document")
      assert json_response(conn, 404)
    end
  end

  describe "GET /api/reviews/:token/comments" do
    test "returns empty list when no comments", %{conn: conn} do
      review = create_review()
      token = review_token(review)
      conn = get(conn, ~p"/api/reviews/#{token}/comments")
      assert json_response(conn, 200) == []
    end

    test "returns 404 for unknown token", %{conn: conn} do
      conn = get(conn, ~p"/api/reviews/nonexistent_token/comments")
      assert json_response(conn, 404)
    end
  end

  describe "GET /api/export/:token/review" do
    test "returns markdown export for valid token", %{conn: conn} do
      review = create_review()
      token = review_token(review)
      conn = get(conn, ~p"/api/export/#{token}/review")
      assert response(conn, 200)
      assert response_content_type(conn, :markdown)
      assert get_resp_header(conn, "content-disposition") |> List.first() =~ "review.md"
    end

    test "returns file headers for multi-file review", %{conn: conn} do
      {:ok, review} =
        Reviews.create_review(
          [%{"path" => "x.go", "content" => "pkg x"}, %{"path" => "y.go", "content" => "pkg y"}],
          0,
          []
        )

      conn = get(conn, ~p"/api/export/#{review.token}/review")
      body = response(conn, 200)
      assert body =~ "## x.go"
      assert body =~ "## y.go"
    end

    test "returns 404 for unknown token", %{conn: conn} do
      conn = get(conn, ~p"/api/export/nonexistent_token/review")
      assert json_response(conn, 404)
    end
  end

  describe "GET /api/export/:token/comments" do
    test "returns .crit.json compatible shape with top-level fields", %{conn: conn} do
      {:ok, review} =
        Reviews.create_review(
          [%{"path" => "plan.md", "content" => "# Plan"}],
          1,
          [
            %{
              "file" => "plan.md",
              "start_line" => 1,
              "end_line" => 1,
              "body" => "fix this",
              "external_id" => "c1"
            }
          ],
          []
        )

      conn = get(conn, ~p"/api/export/#{review.token}/comments")
      body = json_response(conn, 200)

      # Top-level .crit.json fields
      assert body["review_round"] == 1
      assert body["share_url"] =~ review.token
      assert body["delete_token"] == review.delete_token
      assert body["updated_at"]

      # Comment shape uses "author" not "author_display_name"
      [comment] = body["files"]["plan.md"]["comments"]
      assert comment["id"]
      assert comment["body"] == "fix this"
      assert comment["external_id"] == "c1"
      assert comment["start_line"] == 1
      assert comment["end_line"] == 1
      assert comment["created_at"]
      assert comment["updated_at"]
      assert Map.has_key?(comment, "author")
      refute Map.has_key?(comment, "author_display_name")
      refute Map.has_key?(comment, "author_identity")
      refute Map.has_key?(comment, "file_path")
    end

    test "returns 404 for unknown token", %{conn: conn} do
      conn = get(conn, ~p"/api/export/nonexistent_token/comments")
      assert json_response(conn, 404)
    end

    test "includes replies, author, and resolved status", %{conn: conn} do
      # Create a review with a resolved comment that has replies and author info
      payload = %{
        "files" => [
          %{"path" => "main.go", "content" => "package main\n\nfunc main() {}"}
        ],
        "comments" => [
          %{
            "file" => "main.go",
            "start_line" => 1,
            "end_line" => 1,
            "body" => "add copyright header",
            "author_display_name" => "Alice",
            "author_identity" => "alice-123",
            "resolved" => true,
            "replies" => [
              %{
                "body" => "done, added MIT license",
                "author_display_name" => "Bob",
                "author_identity" => "bob-456"
              },
              %{
                "body" => "looks good now",
                "author_display_name" => "Alice",
                "author_identity" => "alice-123"
              }
            ]
          },
          %{
            "file" => "main.go",
            "start_line" => 3,
            "end_line" => 3,
            "body" => "needs error handling",
            "author_display_name" => "Alice",
            "author_identity" => "alice-123",
            "resolved" => false
          }
        ]
      }

      conn = post(conn, ~p"/api/reviews", payload)
      assert %{"url" => url} = json_response(conn, 201)
      token = url |> String.split("/") |> List.last()

      export_conn = get(build_conn(), ~p"/api/export/#{token}/comments")
      result = json_response(export_conn, 200)

      # Top-level fields present
      assert result["review_round"]
      assert result["share_url"] =~ token
      assert result["delete_token"]

      assert Map.has_key?(result["files"], "main.go")
      comments = result["files"]["main.go"]["comments"]
      assert length(comments) == 2

      # First comment: resolved with replies and author (export uses "author" key)
      resolved_comment = Enum.find(comments, &(&1["body"] == "add copyright header"))
      assert resolved_comment["resolved"] == true
      assert resolved_comment["author"] == "Alice"
      assert resolved_comment["start_line"] == 1
      assert resolved_comment["end_line"] == 1
      refute Map.has_key?(resolved_comment, "author_display_name")
      refute Map.has_key?(resolved_comment, "author_identity")

      # Replies use "author" key
      replies = resolved_comment["replies"]
      assert length(replies) == 2
      assert Enum.at(replies, 0)["body"] == "done, added MIT license"
      assert Enum.at(replies, 0)["author"] == "Bob"
      assert Enum.at(replies, 1)["body"] == "looks good now"
      assert Enum.at(replies, 1)["author"] == "Alice"
      refute Map.has_key?(Enum.at(replies, 0), "author_display_name")

      # Second comment: unresolved, no replies
      unresolved_comment = Enum.find(comments, &(&1["body"] == "needs error handling"))
      assert unresolved_comment["resolved"] == false
      assert unresolved_comment["author"] == "Alice"
      assert unresolved_comment["replies"] == []
    end
  end

  describe "POST /api/reviews multi-file" do
    test "creates a multi-file review", %{conn: conn} do
      payload = %{
        "files" => [
          %{"path" => "main.go", "content" => "package main"},
          %{"path" => "util.go", "content" => "package util"}
        ],
        "review_round" => 1,
        "comments" => [
          %{"file" => "main.go", "start_line" => 1, "end_line" => 1, "body" => "fix this"}
        ]
      }

      conn = post(conn, ~p"/api/reviews", payload)
      assert %{"url" => url, "delete_token" => _} = json_response(conn, 201)
      assert url =~ "/r/"
    end

    test "rejects files with no content", %{conn: conn} do
      payload = %{
        "files" => [%{"path" => "main.go"}]
      }

      conn = post(conn, ~p"/api/reviews", payload)
      assert json_response(conn, 422)
    end

    test "rejects empty files array", %{conn: conn} do
      payload = %{"files" => []}

      conn = post(conn, ~p"/api/reviews", payload)
      assert json_response(conn, 422)
    end

    test "single-file content path still works (backward compat)", %{conn: conn} do
      payload = %{
        "content" => "# Hello",
        "filename" => "test.md",
        "comments" => []
      }

      conn = post(conn, ~p"/api/reviews", payload)
      assert %{"url" => url} = json_response(conn, 201)
      assert url =~ "/r/"
    end

    test "rejects more than 200 files", %{conn: conn} do
      files = for i <- 1..201, do: %{"path" => "file_#{i}.go", "content" => "pkg"}

      payload = %{"files" => files}
      conn = post(conn, ~p"/api/reviews", payload)
      assert %{"error" => error} = json_response(conn, 422)
      assert error =~ "Too many files"
    end

    test "returns 422 when total file size exceeds 10 MB", %{conn: conn} do
      big = String.duplicate("x", 5_500_000)

      payload = %{
        "files" => [
          %{"path" => "a.go", "content" => big},
          %{"path" => "b.go", "content" => big}
        ]
      }

      conn = post(conn, ~p"/api/reviews", payload)
      assert %{"error" => error} = json_response(conn, 422)
      assert error =~ "10 MB"
    end

    test "creates multi-file review with comments that have file paths", %{conn: conn} do
      payload = %{
        "files" => [
          %{"path" => "main.go", "content" => "package main"},
          %{"path" => "util.go", "content" => "package util"}
        ],
        "comments" => [
          %{"file" => "main.go", "start_line" => 1, "end_line" => 1, "body" => "fix"},
          %{"file" => "util.go", "start_line" => 1, "end_line" => 1, "body" => "ok"}
        ]
      }

      conn = post(conn, ~p"/api/reviews", payload)
      assert %{"url" => url} = json_response(conn, 201)
      token = url |> String.split("/") |> List.last()

      # Verify comments are created via the export endpoint which groups by file
      export_conn = get(build_conn(), ~p"/api/export/#{token}/comments")
      result = json_response(export_conn, 200)
      assert Map.has_key?(result["files"], "main.go")
      assert Map.has_key?(result["files"], "util.go")
      assert length(result["files"]["main.go"]["comments"]) == 1
      assert length(result["files"]["util.go"]["comments"]) == 1
    end
  end

  describe "multi-file review lifecycle" do
    test "create, export comments, export review, document, delete", %{conn: conn} do
      # Create
      payload = %{
        "files" => [
          %{"path" => "main.go", "content" => "package main\n\nfunc main() {}"},
          %{"path" => "util.go", "content" => "package util\n\nfunc Helper() {}"}
        ],
        "review_round" => 1,
        "comments" => [
          %{"file" => "main.go", "start_line" => 1, "end_line" => 1, "body" => "add copyright"}
        ]
      }

      conn = post(conn, ~p"/api/reviews", payload)
      assert %{"url" => url, "delete_token" => dt} = json_response(conn, 201)
      token = url |> String.split("/") |> List.last()

      # Export comments — grouped by file
      conn = get(build_conn(), ~p"/api/export/#{token}/comments")
      result = json_response(conn, 200)
      assert Map.has_key?(result["files"], "main.go")
      assert Map.has_key?(result["files"], "util.go")
      assert length(result["files"]["main.go"]["comments"]) == 1
      assert result["files"]["util.go"]["comments"] == []

      # Export review — markdown with file headers
      conn = get(build_conn(), ~p"/api/export/#{token}/review")
      body = response(conn, 200)
      assert body =~ "## main.go"
      assert body =~ "## util.go"
      assert body =~ "REVIEW COMMENT"

      # Document endpoint — returns files JSON
      conn = get(build_conn(), ~p"/api/reviews/#{token}/document")
      result = json_response(conn, 200)
      assert length(result["files"]) == 2

      # Delete
      conn = delete(build_conn(), ~p"/api/reviews", %{"delete_token" => dt})
      assert response(conn, 204)
    end

    test "creates a review with removed (orphaned) files", %{conn: conn} do
      payload = %{
        "files" => [
          %{"path" => "active.go", "content" => "package main"},
          %{
            "path" => "removed.md",
            "content" => "",
            "status" => "removed"
          }
        ],
        "review_round" => 2,
        "comments" => [
          %{
            "file" => "removed.md",
            "start_line" => 1,
            "end_line" => 1,
            "body" => "this was here before"
          }
        ]
      }

      conn = post(conn, ~p"/api/reviews", payload)
      assert %{"url" => url} = json_response(conn, 201)
      token = url |> String.split("/") |> List.last()

      # Document endpoint includes status for all files
      conn = get(build_conn(), ~p"/api/reviews/#{token}/document")
      result = json_response(conn, 200)
      assert length(result["files"]) == 2

      removed_file = Enum.find(result["files"], &(&1["path"] == "removed.md"))
      active_file = Enum.find(result["files"], &(&1["path"] == "active.go"))

      assert removed_file["status"] == "removed"
      assert removed_file["content"] == ""

      assert active_file["status"] == "modified"
    end

  end

  describe "PUT /api/reviews/:token" do
    test "updates review content and returns new round", %{conn: conn} do
      {:ok, review} =
        Crit.Reviews.create_review(
          [%{"path" => "plan.md", "content" => "# v1"}],
          1,
          [],
          []
        )

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put("/api/reviews/#{review.token}", %{
          delete_token: review.delete_token,
          files: [%{path: "plan.md", content: "# v2"}],
          comments: [],
          review_round: 1
        })

      assert %{"changed" => true, "review_round" => round, "url" => url} =
               json_response(conn, 200)

      assert round == review.review_round + 1
      assert url =~ review.token
    end

    test "returns changed: false when content is identical", %{conn: conn} do
      {:ok, review} =
        Crit.Reviews.create_review(
          [%{"path" => "plan.md", "content" => "same"}],
          1,
          [],
          []
        )

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put("/api/reviews/#{review.token}", %{
          delete_token: review.delete_token,
          files: [%{path: "plan.md", content: "same"}],
          comments: [],
          review_round: 1
        })

      assert %{"changed" => false} = json_response(conn, 200)
    end

    test "returns 401 with wrong delete_token", %{conn: conn} do
      {:ok, review} =
        Crit.Reviews.create_review(
          [%{"path" => "plan.md", "content" => "# v1"}],
          1,
          [],
          []
        )

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put("/api/reviews/#{review.token}", %{
          delete_token: "wrong",
          files: [],
          comments: [],
          review_round: 1
        })

      assert conn.status == 401
    end

    test "returns 404 for unknown token", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put("/api/reviews/doesnotexist", %{
          delete_token: "tok",
          files: [],
          comments: [],
          review_round: 1
        })

      assert conn.status == 404
    end
  end

  describe "DELETE /api/reviews" do
    test "deletes review with valid delete_token", %{conn: conn} do
      review = create_review()
      conn = delete(conn, ~p"/api/reviews", %{delete_token: review.delete_token})
      assert response(conn, 204) == ""
    end

    test "returns 404 for unknown delete_token", %{conn: conn} do
      conn = delete(conn, ~p"/api/reviews", %{delete_token: "unknowntoken1234567890x"})
      assert json_response(conn, 404)
    end

    test "returns 400 for missing delete_token", %{conn: conn} do
      conn = delete(conn, ~p"/api/reviews", %{})
      assert json_response(conn, 400)
    end
  end
end
