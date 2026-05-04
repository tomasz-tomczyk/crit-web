defmodule CritWeb.PageControllerSeoTest do
  use CritWeb.ConnCase, async: false
  import Crit.ReviewsFixtures
  import Ecto.Query

  alias Crit.Accounts.Scope
  alias Crit.Reviews

  defp user_fixture do
    {:ok, user} =
      Crit.Accounts.find_or_create_from_oauth("github", %{
        "sub" => "seo-#{System.unique_integer([:positive])}",
        "email" => "seo-#{System.unique_integer([:positive])}@example.com",
        "name" => "SEO"
      })

    user
  end

  setup do
    Application.put_env(:crit, :selfhosted, false)
    on_exit(fn -> Application.delete_env(:crit, :selfhosted) end)
    :ok
  end

  describe "GET /robots.txt" do
    test "allows /r/ and points to the dynamic sitemap", %{conn: conn} do
      conn = get(conn, ~p"/robots.txt")
      assert ["text/plain" <> _] = get_resp_header(conn, "content-type")
      body = response(conn, 200)
      refute body =~ "Disallow: /r/"
      assert body =~ "Disallow: /api/"
      assert body =~ "Disallow: /dashboard"
      assert body =~ "Sitemap: " <> CritWeb.Endpoint.url() <> "/sitemap.xml"
    end

    test "selfhosted instances disallow everything and omit Sitemap", %{conn: conn} do
      Application.put_env(:crit, :selfhosted, true)
      body = conn |> get(~p"/robots.txt") |> response(200)
      refute body =~ "Sitemap:"
      assert body =~ "Disallow: /"
    end
  end

  describe "GET /sitemap.xml" do
    test "lists static marketing pages", %{conn: conn} do
      conn = get(conn, ~p"/sitemap.xml")
      assert ["application/xml" <> _] = get_resp_header(conn, "content-type")
      body = response(conn, 200)
      base = CritWeb.Endpoint.url()
      assert body =~ "<loc>#{base}/</loc>"
      assert body =~ "<loc>#{base}/features</loc>"
      assert body =~ "<loc>#{base}/changelog</loc>"
    end

    test "includes public reviews and excludes unlisted", %{conn: conn} do
      user = user_fixture()
      public_review = review_fixture(user_id: user.id)
      unlisted_review = review_fixture(user_id: user.id)

      {:ok, _} = Reviews.make_public(Scope.for_user(user), public_review.id)

      body = conn |> get(~p"/sitemap.xml") |> response(200)
      assert body =~ "/r/#{public_review.token}"
      refute body =~ "/r/#{unlisted_review.token}"
    end

    test "is well-formed XML when no public reviews exist", %{conn: conn} do
      body = conn |> get(~p"/sitemap.xml") |> response(200)
      assert body =~ ~s(<?xml version="1.0" encoding="UTF-8"?>)
      assert body =~ "<urlset"
      assert body =~ "</urlset>"
      {doc, _rest} = :xmerl_scan.string(String.to_charlist(body))
      assert is_tuple(doc) and elem(doc, 0) == :xmlElement
    end

    test "orders public reviews by recency (most recent first)", %{conn: conn} do
      user = user_fixture()
      older = review_fixture(user_id: user.id)
      newer = review_fixture(user_id: user.id)

      {:ok, _} = Reviews.make_public(Scope.for_user(user), older.id)
      {:ok, _} = Reviews.make_public(Scope.for_user(user), newer.id)

      Crit.Repo.update_all(
        from(r in Crit.Review, where: r.id == ^older.id),
        set: [last_activity_at: ~U[2020-01-01 00:00:00Z]]
      )

      body = conn |> get(~p"/sitemap.xml") |> response(200)
      newer_idx = :binary.match(body, "/r/#{newer.token}") |> elem(0)
      older_idx = :binary.match(body, "/r/#{older.token}") |> elem(0)
      assert newer_idx < older_idx
    end
  end
end
