defmodule CritWeb.ApiSubThreadsTest do
  use CritWeb.ConnCase

  @plan "# Plan\n\nStep 1\n\nStep 2\n"

  # Writes are rate-limited per IP: give each request its own.
  defp unique_ip(conn) do
    n = System.unique_integer([:positive])
    %{conn | remote_ip: {10, rem(n, 250), rem(div(n, 250), 250), rem(div(n, 62_500), 250)}}
  end

  # The payload crit sends: roots in `comments`, sub-threads under
  # `sub_threads`, anchored by the crit id of the message they comment on.
  defp share_payload do
    %{
      files: [%{path: "plan.md", content: @plan}],
      review_round: 1,
      comments: [
        %{
          file: "plan.md",
          start_line: 3,
          end_line: 3,
          scope: "line",
          body: "Expand this",
          external_id: "c_root",
          replies: [%{body: "Done", external_id: "rp_done"}]
        }
      ],
      sub_threads: [
        %{
          external_id: "c_sub",
          parent_external_id: "rp_done",
          body: "Done how?",
          quote: "Done",
          quote_offset: 0,
          author_display_name: "Alice",
          resolved: false,
          review_round: 1,
          replies: [%{body: "Like this", external_id: "rp_sub"}]
        },
        %{external_id: "c_deeper", parent_external_id: "rp_sub", body: "Sure?", quote: "this"}
      ]
    }
  end

  defp share!(conn, payload) do
    conn = conn |> unique_ip() |> post(~p"/api/reviews", payload)
    assert %{"url" => url, "delete_token" => delete_token} = json_response(conn, 201)
    {url |> String.split("/r/") |> List.last(), delete_token}
  end

  defp fetch_comments(token) do
    build_conn() |> get(~p"/api/reviews/#{token}/comments") |> json_response(200)
  end

  defp assert_fetched_tree(token) do
    assert [thread] = fetch_comments(token)
    assert thread["external_id"] == "c_root"
    assert thread["sub_threads"] == []

    assert [reply] = thread["replies"]
    assert reply["external_id"] == "rp_done"
    assert [sub_thread] = reply["sub_threads"]
    assert sub_thread["external_id"] == "c_sub"
    assert sub_thread["anchor_comment_id"] == reply["id"]
    assert sub_thread["quote"] == "Done"
    assert sub_thread["quote_offset"] == 0
    assert sub_thread["author_display_name"] == "Alice"
    assert sub_thread["scope"] == "line"
    assert sub_thread["file_path"] == "plan.md"
    assert is_nil(sub_thread["start_line"])

    assert [sub_reply] = sub_thread["replies"]
    assert sub_reply["external_id"] == "rp_sub"
    assert [%{"external_id" => "c_deeper", "body" => "Sure?"}] = sub_reply["sub_threads"]
  end

  describe "POST and GET with sub_threads" do
    test "a shared sub-thread comes back nested under its message, never at the top level",
         %{conn: conn} do
      {token, _} = share!(conn, share_payload())
      assert_fetched_tree(token)
    end

    test "sub-threads count toward the comment limit", %{conn: conn} do
      max = Crit.Settings.get().max_comments_per_review
      sub_threads = for i <- 1..max, do: %{external_id: "s#{i}", parent_external_id: "c_root"}

      conn =
        conn
        |> unique_ip()
        |> post(~p"/api/reviews", %{share_payload() | sub_threads: sub_threads})

      assert %{"error" => "Too many comments" <> _} = json_response(conn, 422)
    end

    test "a share from a client without sub_threads is unchanged", %{conn: conn} do
      {token, _} = share!(conn, Map.delete(share_payload(), :sub_threads))

      assert [%{"external_id" => "c_root", "sub_threads" => [], "replies" => [reply]}] =
               fetch_comments(token)

      assert reply["sub_threads"] == []
    end
  end

  describe "PUT /api/reviews/:token with sub_threads" do
    test "repeated re-shares keep the sub-threads on their anchors", %{conn: conn} do
      {token, delete_token} = share!(conn, share_payload())

      for _ <- 1..2 do
        conn =
          build_conn()
          |> unique_ip()
          |> put_req_header("content-type", "application/json")
          |> put("/api/reviews/#{token}", Map.put(share_payload(), :delete_token, delete_token))

        assert %{"changed" => false} = json_response(conn, 200)
        assert_fetched_tree(token)
      end
    end
  end

  describe "PUT /api/reviews/:token with an invalid message" do
    test "answers 422 and keeps the stored review", %{conn: conn} do
      {token, delete_token} = share!(conn, share_payload())
      long_name = String.duplicate("n", 41)

      invalid_sub_threads = [
        [%{external_id: "c_bad", parent_external_id: "c_root", body: ""}],
        [
          %{
            external_id: "c_bad",
            parent_external_id: "c_root",
            body: "ok",
            author_display_name: long_name
          }
        ]
      ]

      for sub_threads <- invalid_sub_threads do
        payload =
          share_payload()
          |> Map.put(:sub_threads, sub_threads)
          |> Map.put(:delete_token, delete_token)

        conn =
          build_conn()
          |> unique_ip()
          |> put_req_header("content-type", "application/json")
          |> put("/api/reviews/#{token}", payload)

        assert %{"error" => "Validation failed", "details" => %{}} = json_response(conn, 422)
        assert_fetched_tree(token)
      end
    end
  end

  describe "GET /api/export/:token/comments" do
    test "lists a sub-thread in its file with parent_id", %{conn: conn} do
      {token, _} = share!(conn, share_payload())

      %{"files" => %{"plan.md" => %{"comments" => comments}}} =
        build_conn() |> get(~p"/api/export/#{token}/comments") |> json_response(200)

      root = Enum.find(comments, &(&1["external_id"] == "c_root"))
      sub_thread = Enum.find(comments, &(&1["external_id"] == "c_sub"))
      refute Map.has_key?(root, "parent_id")
      assert sub_thread["parent_id"] == hd(root["replies"])["id"]
    end
  end
end
