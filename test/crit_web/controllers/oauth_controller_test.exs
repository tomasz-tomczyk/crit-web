defmodule CritWeb.OAuthControllerTest do
  use CritWeb.ConnCase, async: true

  describe "DELETE /auth/logout" do
    test "clears user_id from session and redirects to /" do
      conn =
        build_conn()
        |> init_test_session(%{"user_id" => 42})
        |> delete(~p"/auth/logout")

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, "user_id") == nil
    end
  end

  describe "GET /auth/login" do
    test "redirects to GitHub when provider is configured" do
      # config/test.exs sets up a stub GitHub provider
      conn = get(build_conn(), ~p"/auth/login")
      assert redirected_to(conn) =~ "github.com/login/oauth/authorize"
    end
  end
end
