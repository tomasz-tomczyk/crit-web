defmodule CritWeb.Plugs.RateLimitTest do
  use CritWeb.ConnCase, async: false

  alias CritWeb.Plugs.RateLimit

  defp call_plug(conn, opts) do
    RateLimit.call(conn, RateLimit.init(opts))
  end

  defp with_ip(conn, ip), do: %{conn | remote_ip: ip}

  # Monotonically unique IP per call — guarantees no bucket collisions across
  # tests in the suite-shared ETS table.
  defp unique_ip do
    n = System.unique_integer([:positive])
    {10, rem(div(n, 65_536), 256), rem(div(n, 256), 256), rem(n, 256)}
  end

  describe "with limiter enabled" do
    setup do
      Application.put_env(:crit, RateLimit, disabled: false)
      on_exit(fn -> Application.put_env(:crit, RateLimit, disabled: true) end)
      {:ok, ip: unique_ip()}
    end

    test "allows requests under the limit", %{conn: conn, ip: ip} do
      conn = conn |> with_ip(ip) |> call_plug(limit: 3)
      refute conn.halted
    end

    test "returns 429 with text body once limit is exceeded", %{conn: conn, ip: ip} do
      for _ <- 1..3, do: conn |> with_ip(ip) |> call_plug(limit: 3)

      blocked = conn |> with_ip(ip) |> call_plug(limit: 3)
      assert blocked.halted
      assert blocked.status == 429
      assert blocked.resp_body == "Too many requests"
      assert ["text/plain" <> _] = get_resp_header(blocked, "content-type")
      [retry] = get_resp_header(blocked, "retry-after")
      assert {n, ""} = Integer.parse(retry)
      assert n >= 0 and n <= 60
    end

    test "returns JSON body when response: :json", %{conn: conn, ip: ip} do
      for _ <- 1..3, do: conn |> with_ip(ip) |> call_plug(limit: 3, response: :json)

      blocked = conn |> with_ip(ip) |> call_plug(limit: 3, response: :json)
      assert blocked.status == 429
      assert blocked.resp_body == ~s({"error":"Too many requests"})
      assert ["application/json" <> _] = get_resp_header(blocked, "content-type")
      [retry] = get_resp_header(blocked, "retry-after")
      assert {n, ""} = Integer.parse(retry)
      assert n >= 0 and n <= 60
    end

    test "rate limit is per-IP", %{conn: conn} do
      a = unique_ip()
      b = unique_ip()

      for _ <- 1..3, do: conn |> with_ip(a) |> call_plug(limit: 3)

      other = conn |> with_ip(b) |> call_plug(limit: 3)
      refute other.halted
    end

    test "is bypassed when E2E=true", %{conn: conn, ip: ip} do
      System.put_env("E2E", "true")
      on_exit(fn -> System.delete_env("E2E") end)

      for _ <- 1..10 do
        conn = conn |> with_ip(ip) |> call_plug(limit: 1)
        refute conn.halted
      end
    end
  end

  describe "with limiter disabled (suite default)" do
    test "never halts no matter how many requests come in", %{conn: conn} do
      ip = unique_ip()

      for _ <- 1..1000 do
        conn = conn |> with_ip(ip) |> call_plug(limit: 1)
        refute conn.halted
      end
    end
  end

  describe "init/1" do
    test "rejects unknown :response value" do
      assert_raise ArgumentError, ":response must be :text or :json", fn ->
        RateLimit.init(response: :xml)
      end
    end

    test "accepts :text and :json" do
      assert RateLimit.init(response: :text)
      assert RateLimit.init(response: :json)
      assert RateLimit.init([])
    end
  end
end
