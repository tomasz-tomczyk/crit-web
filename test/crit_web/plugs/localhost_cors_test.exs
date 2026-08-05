defmodule CritWeb.Plugs.LocalhostCorsTest do
  # async: false — mutates Application.put_env(:crit, :selfhosted), which is global.
  use CritWeb.ConnCase, async: false

  alias Crit.Accounts.Scope
  alias Crit.Reviews

  @origin "http://localhost:54358"

  defp with_enforcement(fun) do
    orig_selfhosted = Application.get_env(:crit, :selfhosted)
    orig_provider = Application.get_env(:crit, :oauth_provider)

    Application.put_env(:crit, :selfhosted, true)
    Application.put_env(:crit, :oauth_provider, "github")

    try do
      fun.()
    after
      if is_nil(orig_selfhosted),
        do: Application.delete_env(:crit, :selfhosted),
        else: Application.put_env(:crit, :selfhosted, orig_selfhosted)

      if is_nil(orig_provider),
        do: Application.delete_env(:crit, :oauth_provider),
        else: Application.put_env(:crit, :oauth_provider, orig_provider)
    end
  end

  defp create_review do
    {:ok, review} =
      Reviews.create_review(
        Scope.for_visitor("cors-test-#{System.unique_integer([:positive])}"),
        [%{"path" => "test.md", "content" => "# Hello"}],
        0,
        []
      )

    review
  end

  describe "preflight on an instance that enforces auth" do
    test "OPTIONS /api/reviews (unpublish preflight) still reflects CORS headers", %{conn: conn} do
      with_enforcement(fn ->
        conn =
          conn
          |> put_req_header("origin", @origin)
          |> put_req_header("access-control-request-method", "DELETE")
          |> put_req_header("access-control-request-headers", "content-type")
          |> options("/api/reviews")

        assert conn.status == 204
        assert get_resp_header(conn, "access-control-allow-origin") == [@origin]
        assert get_resp_header(conn, "access-control-allow-methods") |> List.first() =~ "DELETE"
      end)
    end

    test "OPTIONS /api/reviews/:token (re-share preflight) still reflects CORS headers", %{
      conn: conn
    } do
      review = create_review()

      with_enforcement(fn ->
        conn =
          conn
          |> put_req_header("origin", @origin)
          |> put_req_header("access-control-request-method", "PUT")
          |> options("/api/reviews/#{review.token}")

        assert conn.status == 204
        assert get_resp_header(conn, "access-control-allow-origin") == [@origin]
      end)
    end
  end

  describe "error responses on cross-origin requests" do
    test "401 from ApiAuth still carries CORS headers so the browser sees the status", %{
      conn: conn
    } do
      with_enforcement(fn ->
        conn =
          conn
          |> put_req_header("origin", @origin)
          |> delete("/api/reviews", %{delete_token: "does-not-matter"})

        assert conn.status == 401
        assert get_resp_header(conn, "access-control-allow-origin") == [@origin]
      end)
    end
  end
end
