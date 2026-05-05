defmodule CritWeb.RawControllerTest do
  use CritWeb.ConnCase, async: true

  import Crit.ReviewsFixtures

  defp file(path, content, extra \\ %{}) do
    Map.merge(%{"path" => path, "content" => content}, extra)
  end

  describe "GET /r/:token/raw/*file_path" do
    test "returns the file content as text/plain with utf-8", %{conn: conn} do
      review = review_fixture(%{files: [file("lib/foo.ex", "defmodule Foo, do: :ok\n")]})

      conn = get(conn, ~p"/r/#{review.token}/raw/lib/foo.ex")

      assert response(conn, 200) == "defmodule Foo, do: :ok\n"
      assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
    end

    test "sets inline content-disposition with the basename", %{conn: conn} do
      review = review_fixture(%{files: [file("deep/nested/dir/file.txt", "hi")]})

      conn = get(conn, ~p"/r/#{review.token}/raw/deep/nested/dir/file.txt")

      assert get_resp_header(conn, "content-disposition") ==
               [~s(inline; filename="file.txt")]
    end

    test "sets x-robots-tag noindex", %{conn: conn} do
      review = review_fixture(%{files: [file("a.md", "# hi")]})

      conn = get(conn, ~p"/r/#{review.token}/raw/a.md")

      assert get_resp_header(conn, "x-robots-tag") == ["noindex"]
    end

    test "supports file paths with multiple slashes (glob)", %{conn: conn} do
      review =
        review_fixture(%{
          files: [file("src/app/components/Button.tsx", "export const x = 1")]
        })

      conn = get(conn, ~p"/r/#{review.token}/raw/src/app/components/Button.tsx")

      assert response(conn, 200) == "export const x = 1"
    end

    test "404s when the review token is unknown", %{conn: conn} do
      conn = get(conn, ~p"/r/does-not-exist/raw/foo.txt")

      assert response(conn, 404)
    end

    test "404s when the file_path is not in the review", %{conn: conn} do
      review = review_fixture(%{files: [file("real.txt", "x")]})

      conn = get(conn, ~p"/r/#{review.token}/raw/missing.txt")

      assert response(conn, 404)
    end

    test "serves removed/orphaned file content (still part of the review)", %{conn: conn} do
      review =
        review_fixture(%{
          files: [file("removed.ex", "old", %{"status" => "removed"})]
        })

      conn = get(conn, ~p"/r/#{review.token}/raw/removed.ex")

      assert response(conn, 200) == "old"
    end

    test "404s when filename contains non-ASCII characters", %{conn: conn} do
      review = review_fixture(%{files: [file("héllo.txt", "x")]})

      conn = get(conn, "/r/" <> review.token <> "/raw/" <> "héllo.txt")

      assert response(conn, 404)
    end
  end
end
