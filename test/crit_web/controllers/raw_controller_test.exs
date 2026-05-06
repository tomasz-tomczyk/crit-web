defmodule CritWeb.RawControllerTest do
  use CritWeb.ConnCase, async: false

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

  describe "auth gate for selfhosted with OAuth" do
    setup do
      original_selfhosted = Application.get_env(:crit, :selfhosted)
      original_oauth = Application.get_env(:crit, :oauth_provider)

      Application.put_env(:crit, :selfhosted, true)
      Application.put_env(:crit, :oauth_provider, :github)

      on_exit(fn ->
        if is_nil(original_selfhosted),
          do: Application.delete_env(:crit, :selfhosted),
          else: Application.put_env(:crit, :selfhosted, original_selfhosted)

        if is_nil(original_oauth),
          do: Application.delete_env(:crit, :oauth_provider),
          else: Application.put_env(:crit, :oauth_provider, original_oauth)
      end)

      :ok
    end

    test "redirects unauthenticated visitor to /auth/login with return_to", %{conn: conn} do
      review = review_fixture(%{files: [file("lib/foo.ex", "secret")]})

      conn = get(conn, ~p"/r/#{review.token}/raw/lib/foo.ex")

      assert redirected_to(conn) =~ "/auth/login"
      assert redirected_to(conn) =~ "return_to="
      assert redirected_to(conn) =~ URI.encode_www_form("/r/#{review.token}/raw/lib/foo.ex")
      # Body must not include the file content.
      refute response(conn, 302) =~ "secret"
    end

    test "serves file content when an authenticated user is in the session", %{conn: conn} do
      review = review_fixture(%{files: [file("lib/foo.ex", "defmodule Foo, do: :ok\n")]})

      {:ok, user} =
        Crit.Accounts.find_or_create_from_oauth("github", %{
          "sub" => "raw_uid_#{System.unique_integer()}",
          "email" => "raw@example.com",
          "name" => "Raw User"
        })

      conn =
        conn
        |> Plug.Test.init_test_session(%{user_id: user.id})
        |> get(~p"/r/#{review.token}/raw/lib/foo.ex")

      assert response(conn, 200) == "defmodule Foo, do: :ok\n"
    end
  end

  describe "without selfhosted+OAuth (public/hosted mode)" do
    setup do
      original_selfhosted = Application.get_env(:crit, :selfhosted)
      original_oauth = Application.get_env(:crit, :oauth_provider)

      Application.put_env(:crit, :selfhosted, false)
      Application.delete_env(:crit, :oauth_provider)

      on_exit(fn ->
        if is_nil(original_selfhosted),
          do: Application.delete_env(:crit, :selfhosted),
          else: Application.put_env(:crit, :selfhosted, original_selfhosted)

        if is_nil(original_oauth),
          do: Application.delete_env(:crit, :oauth_provider),
          else: Application.put_env(:crit, :oauth_provider, original_oauth)
      end)

      :ok
    end

    test "raw URL is reachable without auth", %{conn: conn} do
      review = review_fixture(%{files: [file("lib/foo.ex", "defmodule Foo, do: :ok\n")]})

      conn = get(conn, ~p"/r/#{review.token}/raw/lib/foo.ex")

      assert response(conn, 200) == "defmodule Foo, do: :ok\n"
    end
  end
end
