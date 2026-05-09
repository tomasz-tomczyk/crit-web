defmodule CritWeb.Plugs.TrustedProxyAuthTest do
  use CritWeb.ConnCase, async: false

  import ExUnit.CaptureLog

  alias CritWeb.Plugs.TrustedProxyAuth
  alias Crit.Accounts
  alias Crit.Accounts.Scope
  alias Crit.User

  @header_name "x-auth-request-email"
  @cidrs [{{10, 0, 0, 0}, 8}]

  defp setup_env(opts \\ []) do
    header = Keyword.get(opts, :header, @header_name)
    cidrs = Keyword.get(opts, :cidrs, @cidrs)

    orig_header = Application.get_env(:crit, :trusted_proxy_user_header)
    orig_cidrs = Application.get_env(:crit, :trusted_proxy_cidrs)

    if is_nil(header),
      do: Application.delete_env(:crit, :trusted_proxy_user_header),
      else: Application.put_env(:crit, :trusted_proxy_user_header, header)

    Application.put_env(:crit, :trusted_proxy_cidrs, cidrs || [])

    on_exit(fn ->
      if is_nil(orig_header),
        do: Application.delete_env(:crit, :trusted_proxy_user_header),
        else: Application.put_env(:crit, :trusted_proxy_user_header, orig_header)

      if is_nil(orig_cidrs),
        do: Application.delete_env(:crit, :trusted_proxy_cidrs),
        else: Application.put_env(:crit, :trusted_proxy_cidrs, orig_cidrs)
    end)
  end

  defp anon_conn(opts \\ []) do
    remote_ip = Keyword.get(opts, :remote_ip, {10, 0, 0, 1})
    headers = Keyword.get(opts, :headers, [])

    conn = Phoenix.ConnTest.build_conn()
    conn = %{conn | remote_ip: remote_ip}

    conn =
      Enum.reduce(headers, conn, fn {k, v}, c ->
        Plug.Conn.put_req_header(c, k, v)
      end)

    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.assign(:current_scope, %Scope{
      user: nil,
      identity: Ecto.UUID.generate(),
      display_name: nil
    })
  end

  defp call(conn), do: TrustedProxyAuth.call(conn, [])

  describe "no-op cases" do
    test "skips when trusted_proxy_user_header is unset" do
      setup_env(header: nil, cidrs: [])

      conn =
        anon_conn(headers: [{@header_name, "user@example.com"}])
        |> call()

      assert conn.assigns.current_scope.user == nil
      assert Plug.Conn.get_session(conn, "user_id") == nil
    end

    test "skips when remote_ip is not in any CIDR" do
      setup_env()

      conn =
        anon_conn(
          remote_ip: {8, 8, 8, 8},
          headers: [{@header_name, "user@example.com"}]
        )
        |> call()

      assert conn.assigns.current_scope.user == nil
      assert Plug.Conn.get_session(conn, "user_id") == nil
      # No user should have been created
      assert Crit.Repo.aggregate(User, :count, :id) == 0
    end

    test "skips when header missing from request" do
      setup_env()
      conn = anon_conn() |> call()
      assert conn.assigns.current_scope.user == nil
    end

    test "session already authenticated wins over header" do
      setup_env()

      {:ok, existing} =
        Accounts.find_or_create_from_oauth("github", %{
          "sub" => "abc",
          "name" => "Existing",
          "email" => "existing@example.com"
        })

      conn =
        anon_conn(headers: [{@header_name, "different@example.com"}])
        |> Plug.Conn.assign(:current_scope, Scope.for_user(existing))
        |> Plug.Conn.put_session("user_id", existing.id)
        |> call()

      # Did not override
      assert conn.assigns.current_scope.user.id == existing.id
      assert Plug.Conn.get_session(conn, "user_id") == existing.id
    end

    test "logs warning and skips when multiple header values present" do
      setup_env()

      log =
        capture_log(fn ->
          conn =
            anon_conn()
            |> Plug.Conn.put_req_header(@header_name, "a@example.com")
            |> Plug.Conn.prepend_req_headers([{@header_name, "b@example.com"}])
            |> call()

          assert conn.assigns.current_scope.user == nil
        end)

      assert log =~ "trusted-proxy"
    end

    test "logs warning and skips when email is malformed" do
      setup_env()

      log =
        capture_log(fn ->
          conn =
            anon_conn(headers: [{@header_name, "not an email"}])
            |> call()

          assert conn.assigns.current_scope.user == nil
        end)

      assert log =~ "trusted-proxy"
    end
  end

  describe "happy path" do
    test "creates user on first sight, sets scope, sets session" do
      setup_env()

      conn =
        anon_conn(headers: [{@header_name, "new@example.com"}])
        |> call()

      assert %User{email: "new@example.com"} = conn.assigns.current_scope.user
      uid = conn.assigns.current_scope.user.id
      assert Plug.Conn.get_session(conn, "user_id") == uid
    end

    test "reuses existing user (no duplicate row)" do
      setup_env()

      {:ok, user} = Accounts.upsert_user_by_email("repeat@example.com")

      conn =
        anon_conn(headers: [{@header_name, "repeat@example.com"}])
        |> call()

      assert conn.assigns.current_scope.user.id == user.id
      assert Crit.Repo.aggregate(User, :count, :id) == 1
    end

    test "lowercases email for matching" do
      setup_env()

      {:ok, _user} = Accounts.upsert_user_by_email("mixed@example.com")

      conn =
        anon_conn(headers: [{@header_name, "Mixed@Example.COM"}])
        |> call()

      assert conn.assigns.current_scope.user.email == "mixed@example.com"
      assert Crit.Repo.aggregate(User, :count, :id) == 1
    end
  end
end
