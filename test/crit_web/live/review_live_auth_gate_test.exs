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
      if original_selfhosted,
        do: Application.put_env(:crit, :selfhosted, original_selfhosted),
        else: Application.delete_env(:crit, :selfhosted)

      if original_oauth,
        do: Application.put_env(:crit, :oauth_provider, original_oauth),
        else: Application.delete_env(:crit, :oauth_provider)
    end)

    review = review_fixture()
    %{review: review}
  end

  describe "auth gate for selfhosted with OAuth" do
    test "shows auth gate when not logged in", %{conn: conn, review: review} do
      {:ok, _view, html} = live(conn, ~p"/r/#{review.token}")
      assert html =~ "Sign in to view this review"
    end

    test "shows review content when logged in", %{conn: conn, review: review} do
      {:ok, user} =
        Crit.Accounts.find_or_create_from_oauth("github", %{
          "sub" => "gate_uid_#{System.unique_integer()}",
          "email" => "gate@example.com",
          "name" => "Gate User"
        })

      conn = init_test_session(conn, %{user_id: user.id})
      {:ok, _view, html} = live(conn, ~p"/r/#{review.token}")
      refute html =~ "Sign in to view this review"
      assert html =~ "document-renderer"
    end

    test "page title is generic when not logged in", %{conn: conn, review: review} do
      {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")
      assert page_title(view) =~ "Review - Crit"
    end
  end
end
