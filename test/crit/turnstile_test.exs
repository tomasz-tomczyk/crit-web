defmodule Crit.TurnstileTest do
  use ExUnit.Case, async: false

  alias Crit.Turnstile

  setup do
    original = Application.get_env(:crit, Turnstile)
    on_exit(fn -> Application.put_env(:crit, Turnstile, original || []) end)
    :ok
  end

  defp enable do
    Application.put_env(:crit, Turnstile,
      site_key: "site",
      secret_key: "secret",
      req_options: [plug: {Req.Test, Turnstile}]
    )
  end

  test "passes everything when keys are missing" do
    Application.put_env(:crit, Turnstile, site_key: "site", secret_key: "")
    refute Turnstile.enabled?()
    assert Turnstile.site_key() == nil
    assert Turnstile.verify(nil) == :ok
  end

  test "rejects a missing token without calling Cloudflare" do
    enable()
    assert Turnstile.verify(nil) == {:error, :missing_token}
    assert Turnstile.verify("") == {:error, :missing_token}
  end

  test "sends the secret and token and accepts a successful answer" do
    enable()

    Req.Test.stub(Turnstile, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert URI.decode_query(body) == %{"secret" => "secret", "response" => "tok"}
      Req.Test.json(conn, %{"success" => true})
    end)

    assert Turnstile.verify("tok") == :ok
  end

  test "returns Cloudflare's error codes on a failed check" do
    enable()

    Req.Test.stub(Turnstile, fn conn ->
      Req.Test.json(conn, %{"success" => false, "error-codes" => ["invalid-input-response"]})
    end)

    assert Turnstile.verify("tok") == {:error, {:rejected, ["invalid-input-response"]}}
  end

  @tag :capture_log
  test "fails closed when Cloudflare is unreachable" do
    enable()
    Req.Test.stub(Turnstile, &Req.Test.transport_error(&1, :econnrefused))
    assert Turnstile.verify("tok") == {:error, :unavailable}
  end
end
