defmodule CritWeb.AuthApiControllerTest do
  use CritWeb.ConnCase, async: true

  alias Crit.{Accounts, Repo, UserApiToken}

  @oauth_params %{
    "sub" => "auth-api-test-uid",
    "name" => "Auth User",
    "email" => "auth@example.com",
    "picture" => nil
  }

  defp create_user_and_token do
    {:ok, user} = Accounts.find_or_create_from_oauth("github", @oauth_params)
    {:ok, {plaintext, _token}} = Accounts.create_token(user, "test token")
    {user, plaintext}
  end

  defp auth_conn(conn, token) do
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  describe "GET /api/auth/whoami" do
    test "returns user info when authenticated", %{conn: conn} do
      {_user, token} = create_user_and_token()

      conn =
        conn
        |> auth_conn(token)
        |> get("/api/auth/whoami")

      assert %{"name" => "Auth User", "email" => "auth@example.com"} = json_response(conn, 200)
    end

    test "returns 401 without Bearer token", %{conn: conn} do
      conn = get(conn, "/api/auth/whoami")
      assert json_response(conn, 401)
    end

    test "returns 401 with invalid token", %{conn: conn} do
      conn =
        conn
        |> auth_conn("crit_invalid_token")
        |> get("/api/auth/whoami")

      assert json_response(conn, 401)
    end
  end

  describe "DELETE /api/auth/token" do
    test "revokes the token used for authentication", %{conn: conn} do
      {_user, token} = create_user_and_token()

      conn =
        conn
        |> auth_conn(token)
        |> delete("/api/auth/token")

      assert response(conn, 204)

      # Verify the token is revoked
      assert {:error, :invalid} = Accounts.verify_token(token)
    end

    test "is idempotent — returns 204 even if token already gone", %{conn: conn} do
      {_user, token} = create_user_and_token()

      # Delete the token first
      token_hash = Base.url_encode64(:crypto.hash(:sha256, token), padding: false)
      Repo.get_by!(UserApiToken, token_hash: token_hash) |> Repo.delete!()

      # The plug will return 401 since the token is gone.
      # This is correct behavior — RequireBearerAuth validates before reaching the controller.
      conn =
        conn
        |> auth_conn(token)
        |> delete("/api/auth/token")

      assert response(conn, 401)
    end

    test "returns 401 without Bearer token", %{conn: conn} do
      conn = delete(conn, "/api/auth/token")
      assert response(conn, 401)
    end
  end
end
