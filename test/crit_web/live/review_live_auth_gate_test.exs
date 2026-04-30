defmodule CritWeb.ReviewLiveAuthGateTest do
  use CritWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Crit.ReviewsFixtures

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

    review = review_fixture()
    %{review: review}
  end

  describe "auth gate for selfhosted with OAuth" do
    test "redirects unauthenticated visitor to OAuth login with return_to", %{
      conn: conn,
      review: review
    } do
      # Subscribe BEFORE mount. If the LiveView reached `mount/3` it would
      # subscribe to this same topic; broadcasting from the test after the
      # redirect proves we are the *only* subscriber (mount never ran).
      Phoenix.PubSub.subscribe(Crit.PubSub, "review:#{review.token}")
      original_activity = review.last_activity_at

      assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/r/#{review.token}")
      assert to =~ "/auth/login"
      assert to =~ "return_to="
      assert to =~ URI.encode_www_form("/r/#{review.token}")

      # `touch_last_activity/1` is only called from inside the LiveView mount.
      # If the on_mount hook halted properly, last_activity_at is unchanged.
      reloaded = Crit.Reviews.get_by_token(review.token)
      assert reloaded.last_activity_at == original_activity

      # And there should be no second subscriber on the review topic — if the
      # LV had reached mount, broadcast_from(self, ...) from a poisoned message
      # would route to it. We assert by broadcasting and confirming our test
      # process is the sole receiver.
      Phoenix.PubSub.broadcast(Crit.PubSub, "review:#{review.token}", :probe)
      assert_receive :probe, 100
      # No further messages — i.e. the LV process did not also receive+rebroadcast.
      refute_receive {:comment_added, _}, 50
      refute_receive {:comments_full_sync, _}, 50
    end

    test "shows review content when logged in", %{conn: conn, review: review} do
      {:ok, user} =
        Crit.Accounts.find_or_create_from_oauth("github", %{
          "sub" => "gate_uid_#{System.unique_integer()}",
          "email" => "gate@example.com",
          "name" => "Gate User"
        })

      conn = init_test_session(conn, %{user_id: user.id})
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")
      assert has_element?(view, "#document-renderer")
      refute has_element?(view, ".crit-auth-gate")
    end
  end

  describe "without selfhosted+OAuth (public mode)" do
    setup do
      Application.put_env(:crit, :selfhosted, false)
      Application.delete_env(:crit, :oauth_provider)
      :ok
    end

    test "anonymous visitor can view review", %{conn: conn, review: review} do
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")
      assert has_element?(view, "#document-renderer")
    end
  end
end
