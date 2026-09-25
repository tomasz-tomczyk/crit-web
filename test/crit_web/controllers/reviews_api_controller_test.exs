defmodule CritWeb.ReviewsApiControllerTest do
  use CritWeb.ConnCase, async: true

  import Ecto.Query
  import Crit.AccountsFixtures
  import Crit.OrganizationsFixtures
  import Crit.ReviewsFixtures

  alias Crit.{Accounts, Repo, Review}

  defp create_user_and_token do
    user = oauth_user_fixture()
    {:ok, {plaintext, _token}} = Accounts.create_token(user, "test token")
    {user, plaintext}
  end

  defp auth_conn(conn, token), do: put_req_header(conn, "authorization", "Bearer #{token}")

  defp list(conn, token, params \\ %{}) do
    conn |> auth_conn(token) |> get("/api/reviews", params)
  end

  defp put_inserted_at(%Review{id: id} = review, %DateTime{} = at) do
    Repo.update_all(from(r in Review, where: r.id == ^id), set: [inserted_at: at])
    review
  end

  defp put_org(%Review{} = review, org, visibility) do
    review
    |> Ecto.Changeset.change(organization_id: org.id, visibility: visibility)
    |> Repo.update!()
  end

  # Creates `count` reviews for the user, one second apart, oldest first.
  defp create_reviews(user, count) do
    base = ~U[2026-01-01 00:00:00Z]

    for i <- 1..count do
      [user_id: user.id]
      |> Map.new()
      |> review_fixture()
      |> put_inserted_at(DateTime.add(base, i, :second))
    end
  end

  # Follows next_cursor until the last page; returns every page's body.
  defp walk_pages(conn, token, params, acc \\ []) do
    body = conn |> list(token, params) |> json_response(200)
    acc = [body | acc]

    case body["next_cursor"] do
      nil -> Enum.reverse(acc)
      cursor -> walk_pages(build_conn(), token, Map.put(params, "after", cursor), acc)
    end
  end

  describe "authentication" do
    test "returns 401 without a Bearer token", %{conn: conn} do
      conn = get(conn, "/api/reviews")
      assert %{"error" => "authentication required"} = json_response(conn, 401)
    end

    test "returns 401 with an invalid token", %{conn: conn} do
      conn = list(conn, "crit_invalid_token")
      assert %{"error" => "invalid token"} = json_response(conn, 401)
    end
  end

  describe "GET /api/reviews" do
    test "returns only the caller's reviews", %{conn: conn} do
      {user, token} = create_user_and_token()
      other = oauth_user_fixture()
      mine = review_fixture(%{user_id: user.id})
      _theirs = review_fixture(%{user_id: other.id})
      _anonymous = review_fixture()

      body = conn |> list(token) |> json_response(200)

      assert [%{"token" => token_value}] = body["reviews"]
      assert token_value == mine.token
      assert body["has_more"] == false
      assert body["next_cursor"] == nil
    end

    test "returns the documented fields and nothing sensitive", %{conn: conn} do
      {user, token} = create_user_and_token()
      review = review_fixture(%{user_id: user.id})

      body = conn |> list(token) |> json_response(200)
      [item] = body["reviews"]

      assert item |> Map.keys() |> Enum.sort() ==
               Enum.sort(~w(token url title review_type visibility org comment_count
                   file_count first_file_path inserted_at last_activity_at))

      assert item["token"] == review.token
      assert item["url"] == CritWeb.Endpoint.url() <> "/r/#{review.token}"
      assert item["review_type"] == "files"
      assert item["visibility"] == "unlisted"
      assert item["org"] == nil
      assert item["file_count"] == 1
      assert item["comment_count"] == 0
      assert item["first_file_path"] == "test.md"
      assert {:ok, _, _} = DateTime.from_iso8601(item["inserted_at"])

      for key <- ~w(delete_token first_file_content author_email user_id id) do
        refute Map.has_key?(item, key)
      end
    end

    test "excludes the caller's reviews in an org they have left", %{conn: conn} do
      {user, token} = create_user_and_token()
      owner = oauth_user_fixture()
      org = organization_fixture(owner)
      review_fixture(%{user_id: user.id}) |> put_org(org, :organization)

      assert %{"reviews" => []} = conn |> list(token) |> json_response(200)
    end

    test "walks all pages newest first with no duplicates", %{conn: conn} do
      {user, token} = create_user_and_token()
      reviews = create_reviews(user, 5)

      pages = walk_pages(conn, token, %{"limit" => "2"})

      assert Enum.map(pages, &length(&1["reviews"])) == [2, 2, 1]
      assert Enum.map(pages, & &1["has_more"]) == [true, true, false]
      assert List.last(pages)["next_cursor"] == nil

      tokens = Enum.flat_map(pages, fn page -> Enum.map(page["reviews"], & &1["token"]) end)
      assert tokens == reviews |> Enum.reverse() |> Enum.map(& &1.token)
    end

    test "returns reviews with the same inserted_at across a page boundary", %{conn: conn} do
      {user, token} = create_user_and_token()
      at = ~U[2026-02-01 12:00:00Z]

      reviews =
        for _ <- 1..3 do
          review_fixture(%{user_id: user.id}) |> put_inserted_at(at)
        end

      pages = walk_pages(conn, token, %{"limit" => "1"})
      tokens = Enum.flat_map(pages, fn page -> Enum.map(page["reviews"], & &1["token"]) end)

      assert length(tokens) == 3
      assert Enum.sort(tokens) == reviews |> Enum.map(& &1.token) |> Enum.sort()
    end

    test "applies a default limit of 50", %{conn: conn} do
      {user, token} = create_user_and_token()
      create_reviews(user, 51)

      body = conn |> list(token) |> json_response(200)

      assert length(body["reviews"]) == 50
      assert body["has_more"] == true
      assert is_binary(body["next_cursor"])
    end

    test "accepts a limit of 500", %{conn: conn} do
      {_user, token} = create_user_and_token()
      assert %{"reviews" => []} = conn |> list(token, %{"limit" => "500"}) |> json_response(200)
    end

    test "returns 400 for a limit above 500", %{conn: conn} do
      {_user, token} = create_user_and_token()

      assert %{"error" => "limit must be less than or equal to 500"} =
               conn |> list(token, %{"limit" => "501"}) |> json_response(400)
    end

    test "returns 400 for a limit below 1", %{conn: conn} do
      {_user, token} = create_user_and_token()

      assert %{"error" => "limit must be greater than 0"} =
               conn |> list(token, %{"limit" => "0"}) |> json_response(400)
    end

    test "returns 400 for a non-integer limit", %{conn: conn} do
      {_user, token} = create_user_and_token()

      assert %{"error" => "limit is invalid"} =
               conn |> list(token, %{"limit" => "ten"}) |> json_response(400)
    end

    test "returns 400 for a garbage cursor", %{conn: conn} do
      {_user, token} = create_user_and_token()

      assert %{"error" => "after is invalid"} =
               conn |> list(token, %{"after" => "not-a-cursor"}) |> json_response(400)
    end

    test "returns 400 for a well-formed cursor with the wrong fields", %{conn: conn} do
      {_user, token} = create_user_and_token()
      cursor = Flop.Cursor.encode(%{name: "x"})

      assert %{"error" => "after does not match order fields"} =
               conn |> list(token, %{"after" => cursor}) |> json_response(400)
    end

    test "returns 400 for a cursor with values of the wrong type", %{conn: conn} do
      {_user, token} = create_user_and_token()
      cursor = Flop.Cursor.encode(%{inserted_at: "yesterday", id: 42})

      assert %{"error" => "after " <> _} =
               conn |> list(token, %{"after" => cursor}) |> json_response(400)
    end

    test "ignores client-supplied ordering params", %{conn: conn} do
      {user, token} = create_user_and_token()
      reviews = create_reviews(user, 3)

      body =
        conn
        |> list(token, %{"order_by" => ["inserted_at"], "order_directions" => ["asc"]})
        |> json_response(200)

      assert Enum.map(body["reviews"], & &1["token"]) ==
               reviews |> Enum.reverse() |> Enum.map(& &1.token)
    end
  end

  describe "GET /api/reviews?org=<slug>" do
    setup do
      {user, token} = create_user_and_token()
      owner = oauth_user_fixture()
      org = organization_fixture(owner)
      %{user: user, token: token, owner: owner, org: org}
    end

    test "returns the org's shared reviews and the caller's own unlisted ones",
         %{conn: conn, user: user, token: token, owner: owner, org: org} do
      membership_fixture(org, user)

      shared = review_fixture(%{user_id: owner.id}) |> put_org(org, :organization)
      public = review_fixture(%{user_id: owner.id}) |> put_org(org, :public)
      own_unlisted = review_fixture(%{user_id: user.id}) |> put_org(org, :unlisted)
      _other_unlisted = review_fixture(%{user_id: owner.id}) |> put_org(org, :unlisted)
      _personal = review_fixture(%{user_id: user.id})

      body = conn |> list(token, %{"org" => org.slug}) |> json_response(200)
      tokens = body["reviews"] |> Enum.map(& &1["token"]) |> Enum.sort()

      assert tokens == Enum.sort([shared.token, public.token, own_unlisted.token])

      assert Enum.all?(body["reviews"], &(&1["org"] == %{"slug" => org.slug, "name" => org.name}))
    end

    test "returns 403 when the caller is not a member", %{conn: conn, token: token, org: org} do
      assert %{"error" => "You are not a member of this organization"} =
               conn |> list(token, %{"org" => org.slug}) |> json_response(403)
    end

    test "returns 404 for an unknown slug", %{conn: conn, token: token} do
      assert %{"error" => "Organization not found"} =
               conn |> list(token, %{"org" => "no-such-org"}) |> json_response(404)
    end
  end
end
