defmodule Crit.ConfigTest do
  use ExUnit.Case, async: false

  alias Crit.Config

  describe "validate_trusted_proxy!/0" do
    setup do
      orig_header = Application.get_env(:crit, :trusted_proxy_user_header)
      orig_cidrs = Application.get_env(:crit, :trusted_proxy_cidrs)

      on_exit(fn ->
        if is_nil(orig_header),
          do: Application.delete_env(:crit, :trusted_proxy_user_header),
          else: Application.put_env(:crit, :trusted_proxy_user_header, orig_header)

        if is_nil(orig_cidrs),
          do: Application.delete_env(:crit, :trusted_proxy_cidrs),
          else: Application.put_env(:crit, :trusted_proxy_cidrs, orig_cidrs)
      end)

      Application.delete_env(:crit, :trusted_proxy_user_header)
      Application.delete_env(:crit, :trusted_proxy_cidrs)
      :ok
    end

    test "ok when both unset" do
      assert :ok = Config.validate_trusted_proxy!()
    end

    test "ok when both set" do
      Application.put_env(:crit, :trusted_proxy_user_header, "x-auth-request-email")
      Application.put_env(:crit, :trusted_proxy_cidrs, [{{10, 0, 0, 0}, 8}])
      assert :ok = Config.validate_trusted_proxy!()
    end

    test "raises when header set without CIDRs" do
      Application.put_env(:crit, :trusted_proxy_user_header, "x-auth-request-email")

      assert_raise RuntimeError, ~r/CRIT_TRUSTED_PROXY_CIDRS/, fn ->
        Config.validate_trusted_proxy!()
      end
    end

    test "raises when header set with empty CIDR list" do
      Application.put_env(:crit, :trusted_proxy_user_header, "x-auth-request-email")
      Application.put_env(:crit, :trusted_proxy_cidrs, [])

      assert_raise RuntimeError, ~r/CRIT_TRUSTED_PROXY_CIDRS/, fn ->
        Config.validate_trusted_proxy!()
      end
    end
  end

  describe "parse_cidrs/1" do
    test "parses comma-separated IPv4 CIDRs" do
      assert [{{10, 0, 0, 0}, 8}, {{172, 16, 0, 0}, 12}] =
               Config.parse_cidrs("10.0.0.0/8,172.16.0.0/12")
    end

    test "trims whitespace" do
      assert [{{10, 0, 0, 0}, 8}] = Config.parse_cidrs(" 10.0.0.0/8 ")
    end

    test "ignores empty entries" do
      assert [{{10, 0, 0, 0}, 8}] = Config.parse_cidrs("10.0.0.0/8,,")
    end

    test "raises on malformed CIDR" do
      assert_raise RuntimeError, ~r/invalid CIDR/i, fn ->
        Config.parse_cidrs("not-a-cidr")
      end
    end

    test "returns [] for nil/empty" do
      assert [] = Config.parse_cidrs(nil)
      assert [] = Config.parse_cidrs("")
    end

    test "parses IPv6 CIDR" do
      assert [{{0, 0, 0, 0, 0, 0, 0, 1}, 128}] = Config.parse_cidrs("::1/128")
    end
  end

  describe "ip_in_cidrs?/2" do
    test "matches IPv4 inside range" do
      cidrs = [{{10, 0, 0, 0}, 8}]
      assert Config.ip_in_cidrs?({10, 1, 2, 3}, cidrs)
      refute Config.ip_in_cidrs?({11, 0, 0, 0}, cidrs)
    end

    test "matches with multiple ranges" do
      cidrs = [{{10, 0, 0, 0}, 8}, {{172, 16, 0, 0}, 12}]
      assert Config.ip_in_cidrs?({172, 20, 0, 1}, cidrs)
      refute Config.ip_in_cidrs?({172, 32, 0, 1}, cidrs)
    end

    test "empty cidrs never match" do
      refute Config.ip_in_cidrs?({10, 0, 0, 1}, [])
    end

    test "matches IPv6" do
      cidrs = [{{0, 0, 0, 0, 0, 0, 0, 0}, 0}]
      assert Config.ip_in_cidrs?({0xFE80, 0, 0, 0, 0, 0, 0, 1}, cidrs)
    end

    test "/32 matches only exact IPv4" do
      cidrs = [{{192, 168, 1, 5}, 32}]
      assert Config.ip_in_cidrs?({192, 168, 1, 5}, cidrs)
      refute Config.ip_in_cidrs?({192, 168, 1, 6}, cidrs)
    end
  end
end
