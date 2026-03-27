defmodule CritWeb.Plugs.ApiAuthTest do
  use CritWeb.ConnCase, async: false

  alias CritWeb.Plugs.ApiAuth
  alias Crit.Accounts

  @oauth_params %{
    "sub" => "api-auth-test-uid",
    "name" => "API User",
    "email" => "apiuser@example.com",
    "picture" => nil
  }

  defp call(conn), do: ApiAuth.call(conn, [])

  defp with_enforcement(fun) do
    orig_selfhosted = Application.get_env(:crit, :selfhosted)
    orig_provider = Application.get_env(:crit, :oauth_provider)

    Application.put_env(:crit, :selfhosted, true)
    Application.put_env(:crit, :oauth_provider, "github")

    try do
      fun.()
    after
      if is_nil(orig_selfhosted),
        do: Application.delete_env(:crit, :selfhosted),
        else: Application.put_env(:crit, :selfhosted, orig_selfhosted)

      if is_nil(orig_provider),
        do: Application.delete_env(:crit, :oauth_provider),
        else: Application.put_env(:crit, :oauth_provider, orig_provider)
    end
  end

  describe "passthrough mode (not selfhosted or no oauth_provider)" do
    test "passes through when selfhosted is false" do
      Application.put_env(:crit, :selfhosted, false)
      conn = build_conn() |> call()
      refute conn.halted
    end

    test "passes through when oauth_provider is nil" do
      Application.put_env(:crit, :selfhosted, true)
      Application.delete_env(:crit, :oauth_provider)
      conn = build_conn() |> call()
      refute conn.halted
    after
      Application.delete_env(:crit, :selfhosted)

      Application.put_env(:crit, :oauth_provider,
        strategy: Assent.Strategy.Github,
        client_id: "test_github_client_id",
        client_secret: "test_github_client_secret"
      )
    end

    test "does not assign current_user in passthrough" do
      conn = build_conn() |> call()
      refute Map.has_key?(conn.assigns, :current_user)
    end
  end

  describe "enforced mode (selfhosted=true and oauth_provider set)" do
    test "halts with 401 when no authorization header" do
      with_enforcement(fn ->
        conn = build_conn() |> call()
        assert conn.halted
        assert conn.status == 401
        assert conn.resp_body =~ "authentication required"
      end)
    end

    test "halts with 401 when authorization header is not Bearer" do
      with_enforcement(fn ->
        conn =
          build_conn()
          |> put_req_header("authorization", "Basic sometoken")
          |> call()

        assert conn.halted
        assert conn.status == 401
        assert conn.resp_body =~ "authentication required"
      end)
    end

    test "halts with 401 when Bearer token is invalid" do
      with_enforcement(fn ->
        conn =
          build_conn()
          |> put_req_header("authorization", "Bearer crit_invalidtoken")
          |> call()

        assert conn.halted
        assert conn.status == 401
        assert conn.resp_body =~ "invalid token"
      end)
    end

    test "assigns current_user and does not halt when Bearer token is valid" do
      {:ok, user} = Accounts.find_or_create_from_oauth("github", @oauth_params)
      {:ok, {plaintext, _token_record}} = Accounts.create_token(user, "test token")

      with_enforcement(fn ->
        conn =
          build_conn()
          |> put_req_header("authorization", "Bearer #{plaintext}")
          |> call()

        refute conn.halted
        assert conn.assigns[:current_user].id == user.id
      end)
    end
  end
end
