defmodule CritWeb.ReviewsApiAccessMatrixTest do
  @moduledoc """
  Checks GET /api/reviews against an access rule written out here, over every
  combination of author, org and visibility, for every caller.
  """
  use CritWeb.ConnCase, async: true

  import Crit.AccountsFixtures
  import Crit.OrganizationsFixtures
  import Crit.ReviewsFixtures

  alias Crit.{Accounts, Repo}

  @visibilities [:unlisted, :organization, :public]

  setup do
    [alice, bob, carol, dave, eve] = for _ <- 1..5, do: oauth_user_fixture()

    # org1: alice (owner), bob. dave was a member and left.
    # org2: carol (owner). eve is in no org.
    org1 = organization_fixture(alice)
    membership_fixture(org1, bob)
    dave_membership = membership_fixture(org1, dave)
    org2 = organization_fixture(carol)

    # Every author (including anonymous) x org x visibility, whether or not the
    # app would normally create it, so the filters see the worst case.
    reviews =
      for author <- [alice, bob, carol, dave, eve, nil],
          org <- [nil, org1, org2],
          visibility <- @visibilities do
        attrs = if author, do: %{user_id: author.id}, else: %{}

        review =
          attrs
          |> review_fixture()
          |> Ecto.Changeset.change(
            organization_id: org && org.id,
            visibility: visibility
          )
          |> Repo.update!()

        %{
          token: review.token,
          author_id: author && author.id,
          org_id: org && org.id,
          visibility: visibility
        }
      end

    Repo.delete!(dave_membership)

    members = %{
      org1.id => MapSet.new([alice.id, bob.id]),
      org2.id => MapSet.new([carol.id])
    }

    %{
      users: [alice, bob, carol, dave, eve],
      orgs: [org1, org2],
      reviews: reviews,
      members: members
    }
  end

  defp token_for(user) do
    {:ok, {plaintext, _}} = Accounts.create_token(user, "matrix")
    plaintext
  end

  defp member?(members, org_id, user_id),
    do: org_id != nil and MapSet.member?(Map.fetch!(members, org_id), user_id)

  defp expected_personal(reviews, members, user) do
    for r <- reviews,
        r.author_id == user.id,
        r.org_id == nil or member?(members, r.org_id, user.id),
        into: MapSet.new(),
        do: r.token
  end

  defp expected_org(reviews, org, user) do
    for r <- reviews,
        r.org_id == org.id,
        r.visibility in [:organization, :public] or r.author_id == user.id,
        into: MapSet.new(),
        do: r.token
  end

  # Walks every page at a small limit so the cursor path is exercised.
  defp fetch_all(token, params) do
    Stream.unfold(params, fn
      :done ->
        nil

      params ->
        body =
          build_conn()
          |> put_req_header("authorization", "Bearer #{token}")
          |> get("/api/reviews", params)
          |> json_response(200)

        next =
          if body["next_cursor"], do: Map.put(params, "after", body["next_cursor"]), else: :done

        {body["reviews"], next}
    end)
    |> Enum.concat()
  end

  test "each caller sees exactly their own reviews in orgs they belong to", ctx do
    for user <- ctx.users do
      tokens = token_for(user) |> fetch_all(%{"limit" => "3"}) |> Enum.map(& &1["token"])

      assert length(tokens) == length(Enum.uniq(tokens))
      assert MapSet.new(tokens) == expected_personal(ctx.reviews, ctx.members, user)
    end
  end

  test "?org= shows members the shared reviews plus their own, and refuses everyone else",
       ctx do
    for user <- ctx.users, org <- ctx.orgs do
      token = token_for(user)

      if member?(ctx.members, org.id, user.id) do
        tokens =
          token |> fetch_all(%{"limit" => "3", "org" => org.slug}) |> Enum.map(& &1["token"])

        assert length(tokens) == length(Enum.uniq(tokens))
        assert MapSet.new(tokens) == expected_org(ctx.reviews, org, user)
      else
        conn =
          build_conn()
          |> put_req_header("authorization", "Bearer #{token}")
          |> get("/api/reviews", %{"org" => org.slug})

        assert json_response(conn, 403)["error"] =~ "not a member"
      end
    end
  end

  test "nothing returned is another user's private review or from another org", ctx do
    by_token = Map.new(ctx.reviews, &{&1.token, &1})

    for user <- ctx.users,
        params <- [%{} | Enum.map(ctx.orgs, &%{"org" => &1.slug})],
        member_or_personal?(ctx.members, params, ctx.orgs, user) do
      for row <- fetch_all(token_for(user), Map.put(params, "limit", "3")) do
        r = Map.fetch!(by_token, row["token"])

        assert r.author_id == user.id or
                 (member?(ctx.members, r.org_id, user.id) and
                    r.visibility in [:organization, :public])
      end
    end
  end

  test "a cursor from one caller's listing does not widen another caller's", ctx do
    [alice | _] = ctx.users
    eve = List.last(ctx.users)

    alice_page =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token_for(alice)}")
      |> get("/api/reviews", %{"limit" => "1"})
      |> json_response(200)

    eve_tokens =
      token_for(eve)
      |> fetch_all(%{"limit" => "3", "after" => alice_page["next_cursor"]})
      |> Enum.map(& &1["token"])
      |> MapSet.new()

    assert MapSet.subset?(eve_tokens, expected_personal(ctx.reviews, ctx.members, eve))
  end

  defp member_or_personal?(_members, params, _orgs, _user) when map_size(params) == 0, do: true

  defp member_or_personal?(members, %{"org" => slug}, orgs, user) do
    org = Enum.find(orgs, &(&1.slug == slug))
    member?(members, org.id, user.id)
  end
end
