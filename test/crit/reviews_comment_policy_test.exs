defmodule Crit.ReviewsCommentPolicyTest do
  use Crit.DataCase, async: true

  alias Crit.Accounts.Scope
  alias Crit.Reviews

  defp owner_user_fixture do
    {:ok, user} =
      Crit.Accounts.find_or_create_from_oauth("github", %{
        "sub" => "cp-#{System.unique_integer([:positive])}",
        "email" => "cp-#{System.unique_integer([:positive])}@example.com",
        "name" => "CP Owner"
      })

    user
  end

  defp create_review_for(user) do
    {:ok, review} =
      Reviews.create_review(
        Scope.for_user(user),
        [%{"path" => "a.md", "content" => "x"}],
        0,
        []
      )

    review
  end

  # Subscribe to the review topic from a separate process and forward all
  # messages back to the test pid. Needed because Reviews.update_review/3
  # uses broadcast_from(self(), ...) and would skip a same-process subscriber.
  defp subscribe_from_other_process(token) do
    test_pid = self()

    {:ok, _pid} =
      Task.start_link(fn ->
        Phoenix.PubSub.subscribe(Crit.PubSub, "review:#{token}")
        forward_loop(test_pid)
      end)

    # Give the Task a tick to register the subscription before the caller
    # triggers the broadcast.
    Process.sleep(20)
    :ok
  end

  defp forward_loop(test_pid) do
    receive do
      msg ->
        send(test_pid, msg)
        forward_loop(test_pid)
    end
  end

  describe "update_review/3 — comment_policy" do
    test "owner can change comment_policy through every value" do
      user = owner_user_fixture()
      scope = Scope.for_user(user)
      review = create_review_for(user)

      for policy <- [:logged_in_only, :disallowed, :open] do
        assert {:ok, updated} = Reviews.update_review(scope, review.id, %{comment_policy: policy})
        assert updated.comment_policy == policy
      end
    end

    test "non-owner authenticated user cannot change comment_policy" do
      owner = owner_user_fixture()
      other = owner_user_fixture()
      review = create_review_for(owner)

      assert {:error, :unauthorized} =
               Reviews.update_review(Scope.for_user(other), review.id, %{
                 comment_policy: :disallowed
               })
    end

    test "anonymous scope cannot change comment_policy" do
      owner = owner_user_fixture()
      review = create_review_for(owner)

      assert {:error, :unauthorized} =
               Reviews.update_review(Scope.for_visitor("ident"), review.id, %{
                 comment_policy: :disallowed
               })
    end

    test "anonymous-owned review cannot have comment_policy changed by an authed visitor" do
      other = owner_user_fixture()

      {:ok, review} =
        Reviews.create_review(
          Scope.for_visitor("anon-#{System.unique_integer([:positive])}"),
          [%{"path" => "a.md", "content" => "x"}],
          0,
          []
        )

      assert review.user_id == nil

      assert {:error, :unauthorized} =
               Reviews.update_review(Scope.for_user(other), review.id, %{
                 comment_policy: :disallowed
               })
    end

    test "missing review returns :not_found" do
      user = owner_user_fixture()

      assert {:error, :not_found} =
               Reviews.update_review(Scope.for_user(user), Ecto.UUID.generate(), %{
                 comment_policy: :disallowed
               })
    end

    test "non-UUID review_id returns :not_found instead of raising" do
      user = owner_user_fixture()

      assert {:error, :not_found} =
               Reviews.update_review(Scope.for_user(user), "not-a-uuid", %{
                 comment_policy: :disallowed
               })
    end

    test "invalid policy atom returns a changeset error" do
      user = owner_user_fixture()
      review = create_review_for(user)

      assert {:error, %Ecto.Changeset{}} =
               Reviews.update_review(Scope.for_user(user), review.id, %{comment_policy: :bogus})
    end

    test "unknown attrs keys are silently dropped by the changeset cast list" do
      user = owner_user_fixture()
      review = create_review_for(user)

      assert {:ok, updated} =
               Reviews.update_review(Scope.for_user(user), review.id, %{
                 comment_policy: :disallowed,
                 evil: 1
               })

      assert updated.comment_policy == :disallowed
    end

    test "setting comment_policy to its current value is a no-op success" do
      user = owner_user_fixture()
      scope = Scope.for_user(user)
      review = create_review_for(user)
      assert review.comment_policy == :open

      assert {:ok, updated} = Reviews.update_review(scope, review.id, %{comment_policy: :open})
      assert updated.comment_policy == :open
    end

    test "string-keyed attrs work too (API-style payloads)" do
      user = owner_user_fixture()
      scope = Scope.for_user(user)
      review = create_review_for(user)

      assert {:ok, updated} =
               Reviews.update_review(scope, review.id, %{"comment_policy" => "logged_in_only"})

      assert updated.comment_policy == :logged_in_only
    end

    test "broadcasts {:policy_changed, ...} on a real comment_policy change" do
      user = owner_user_fixture()
      scope = Scope.for_user(user)
      review = create_review_for(user)
      assert review.comment_policy == :open

      # Subscribe from a separate process so broadcast_from(self(), ...) in
      # update_review (which excludes the *caller* of update_review) still
      # delivers to this subscriber. Mirrors the production topology where
      # the originating LV calls update_review and other-tab LVs subscribe.
      subscribe_from_other_process(review.token)

      assert {:ok, _updated} =
               Reviews.update_review(scope, review.id, %{comment_policy: :disallowed})

      assert_receive {:policy_changed, review_id, %{comment_policy: :disallowed}}
      assert review_id == review.id
    end

    test "does NOT broadcast {:policy_changed, ...} when comment_policy is unchanged" do
      user = owner_user_fixture()
      scope = Scope.for_user(user)
      review = create_review_for(user)
      assert review.comment_policy == :open

      subscribe_from_other_process(review.token)

      assert {:ok, _updated} =
               Reviews.update_review(scope, review.id, %{comment_policy: :open})

      refute_receive {:policy_changed, _, _}, 100
    end
  end

  describe "create_comment/4 — comment_policy gate" do
    setup do
      user = owner_user_fixture()
      open_r = create_review_for(user)
      login_r = create_review_for(user)
      closed_r = create_review_for(user)

      {:ok, _} =
        Reviews.update_review(Scope.for_user(user), login_r.id, %{comment_policy: :logged_in_only})

      {:ok, _} =
        Reviews.update_review(Scope.for_user(user), closed_r.id, %{comment_policy: :disallowed})

      login_r = Reviews.get_by_token(login_r.token)
      closed_r = Reviews.get_by_token(closed_r.token)
      attrs = %{"start_line" => 1, "end_line" => 1, "body" => "hi"}
      %{user: user, open_r: open_r, login_r: login_r, closed_r: closed_r, attrs: attrs}
    end

    test "open: anonymous allowed", %{open_r: r, attrs: a} do
      scope = Scope.for_visitor("anon", "Anon")
      assert {:ok, _} = Reviews.create_comment(scope, r, a)
    end

    test "open: authenticated allowed", %{user: u, open_r: r, attrs: a} do
      assert {:ok, _} = Reviews.create_comment(Scope.for_user(u), r, a)
    end

    test "logged_in_only: anonymous rejected", %{login_r: r, attrs: a} do
      scope = Scope.for_visitor("anon", "Anon")
      assert {:error, :comments_require_login} = Reviews.create_comment(scope, r, a)
    end

    test "logged_in_only: authenticated allowed", %{user: u, login_r: r, attrs: a} do
      assert {:ok, _} = Reviews.create_comment(Scope.for_user(u), r, a)
    end

    test "disallowed: anonymous rejected", %{closed_r: r, attrs: a} do
      scope = Scope.for_visitor("anon", "Anon")
      assert {:error, :comments_disallowed} = Reviews.create_comment(scope, r, a)
    end

    test "disallowed: authenticated rejected", %{user: u, closed_r: r, attrs: a} do
      assert {:error, :comments_disallowed} = Reviews.create_comment(Scope.for_user(u), r, a)
    end
  end

  describe "create_reply/4 — comment_policy gate" do
    setup do
      user = owner_user_fixture()
      open_r = create_review_for(user)
      login_r = create_review_for(user)
      closed_r = create_review_for(user)

      {:ok, _} =
        Reviews.update_review(Scope.for_user(user), login_r.id, %{comment_policy: :logged_in_only})

      {:ok, _} =
        Reviews.update_review(Scope.for_user(user), closed_r.id, %{comment_policy: :disallowed})

      login_r = Reviews.get_by_token(login_r.token)
      closed_r = Reviews.get_by_token(closed_r.token)
      anon = Scope.for_visitor("anon", "Anon")

      open_parent = insert_top_level_comment!(open_r)
      login_parent = insert_top_level_comment!(login_r)
      closed_parent = insert_top_level_comment!(closed_r)

      %{
        user: user,
        anon: anon,
        open: {open_r, open_parent},
        login: {login_r, login_parent},
        closed: {closed_r, closed_parent}
      }
    end

    test "open: anonymous allowed", %{anon: anon, open: {r, p}} do
      assert {:ok, _} = Reviews.create_reply(anon, p.id, %{"body" => "r"}, r.id)
    end

    test "logged_in_only: anonymous rejected", %{anon: anon, login: {r, p}} do
      assert {:error, :comments_require_login} =
               Reviews.create_reply(anon, p.id, %{"body" => "r"}, r.id)
    end

    test "logged_in_only: authenticated allowed", %{user: u, login: {r, p}} do
      assert {:ok, _} =
               Reviews.create_reply(Scope.for_user(u), p.id, %{"body" => "r"}, r.id)
    end

    test "disallowed: anonymous rejected", %{anon: anon, closed: {r, p}} do
      assert {:error, :comments_disallowed} =
               Reviews.create_reply(anon, p.id, %{"body" => "r"}, r.id)
    end

    test "disallowed: authenticated rejected", %{user: u, closed: {r, p}} do
      assert {:error, :comments_disallowed} =
               Reviews.create_reply(Scope.for_user(u), p.id, %{"body" => "r"}, r.id)
    end
  end

  describe "upsert_review/4 with restrictive comment_policy" do
    test "bulk replace path still works regardless of policy" do
      owner = owner_user_fixture()
      review = create_review_for(owner)
      scope = Scope.for_user(owner)
      {:ok, _} = Reviews.update_review(scope, review.id, %{comment_policy: :disallowed})

      payload = %{
        "files" => [%{"path" => "a.md", "content" => "hello"}],
        "comments" => [
          %{
            "start_line" => 1,
            "end_line" => 1,
            "body" => "from cli upload",
            "scope" => "line",
            "external_id" => "cli_1"
          }
        ]
      }

      assert {:ok, _outcome, _updated} =
               Reviews.upsert_review(scope, review.token, review.delete_token, payload)

      assert [%{body: "from cli upload"}] = Reviews.list_comments(review.id)
    end
  end

  defp insert_top_level_comment!(%Crit.Review{} = review) do
    Crit.Repo.insert!(%Crit.Comment{
      review_id: review.id,
      start_line: 1,
      end_line: 1,
      body: "seed",
      scope: "line"
    })
  end
end
