defmodule CritWeb.Plugs.FlyClientIpTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  alias CritWeb.Plugs.FlyClientIp

  setup do
    original = Application.get_env(:crit, :trust_fly_client_ip)
    on_exit(fn -> Application.put_env(:crit, :trust_fly_client_ip, original || false) end)
    :ok
  end

  defp call(header) do
    conn(:get, "/")
    |> Map.put(:remote_ip, {172, 16, 0, 1})
    |> then(fn conn ->
      if header, do: put_req_header(conn, "fly-client-ip", header), else: conn
    end)
    |> FlyClientIp.call([])
  end

  test "uses Fly-Client-IP when running on Fly" do
    Application.put_env(:crit, :trust_fly_client_ip, true)
    assert call("203.0.113.7").remote_ip == {203, 0, 113, 7}
    assert call("2001:db8::1").remote_ip == {8193, 3512, 0, 0, 0, 0, 0, 1}
  end

  test "keeps the peer address for a missing or malformed header" do
    Application.put_env(:crit, :trust_fly_client_ip, true)
    assert call(nil).remote_ip == {172, 16, 0, 1}
    assert call("not-an-ip").remote_ip == {172, 16, 0, 1}
  end

  test "ignores the header off Fly" do
    Application.put_env(:crit, :trust_fly_client_ip, false)
    assert call("203.0.113.7").remote_ip == {172, 16, 0, 1}
  end
end
