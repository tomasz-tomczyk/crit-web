defmodule CritWeb.Plugs.RequireBearerAuthTest do
  use CritWeb.ConnCase, async: true

  alias CritWeb.Plugs.RequireBearerAuth
  alias Crit.Accounts

  @oauth_params %{
    "sub" => "require-bearer-test-uid",
    "name" => "Bearer User",
    "email" => "bearer@example.com",
    "picture" => nil
  }

  defp call(conn), do: RequireBearerAuth.call(conn, [])

  describe "RequireBearerAuth" do
    test "halts with 401 when no authorization header" do
      conn = build_conn() |> call()
      assert conn.halted
      assert conn.status == 401
      assert conn.resp_body =~ "authentication required"
    end

    test "halts with 401 when authorization header is not Bearer" do
      conn =
        build_conn()
        |> put_req_header("authorization", "Basic sometoken")
        |> call()

      assert conn.halted
      assert conn.status == 401
      assert conn.resp_body =~ "authentication required"
    end

    test "halts with 401 when Bearer token is invalid" do
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer crit_invalidtoken")
        |> call()

      assert conn.halted
      assert conn.status == 401
      assert conn.resp_body =~ "invalid token"
    end

    test "assigns current_user and current_token when Bearer token is valid" do
      {:ok, user} = Accounts.find_or_create_from_oauth("github", @oauth_params)
      {:ok, {plaintext, _token_record}} = Accounts.create_token(user, "test token")

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{plaintext}")
        |> call()

      refute conn.halted
      assert conn.assigns[:current_user].id == user.id
      assert conn.assigns[:current_token] == plaintext
    end
  end
end
