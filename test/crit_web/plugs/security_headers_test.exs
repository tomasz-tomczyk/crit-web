defmodule CritWeb.Plugs.SecurityHeadersTest do
  use CritWeb.ConnCase, async: true

  describe "security headers" do
    test "sets permissions-policy on browser requests", %{conn: conn} do
      conn = get(conn, ~p"/")

      policy = get_resp_header(conn, "permissions-policy") |> List.first()
      assert policy =~ "camera=()"
      assert policy =~ "microphone=()"
      assert policy =~ "geolocation=()"
      assert policy =~ "payment=()"
    end

    test "sets x-content-type-options and x-frame-options", %{conn: conn} do
      conn = get(conn, ~p"/")

      assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
      assert get_resp_header(conn, "x-frame-options") == ["SAMEORIGIN"]
    end

    test "does not set HSTS when hsts_enabled is not configured", %{conn: conn} do
      Application.delete_env(:crit, :hsts_enabled)

      on_exit(fn -> Application.delete_env(:crit, :hsts_enabled) end)

      conn = get(conn, ~p"/")

      assert get_resp_header(conn, "strict-transport-security") == []
    end

    test "sets HSTS when hsts_enabled is true", %{conn: conn} do
      Application.put_env(:crit, :hsts_enabled, true)

      on_exit(fn -> Application.delete_env(:crit, :hsts_enabled) end)

      conn = get(conn, ~p"/")

      [hsts] = get_resp_header(conn, "strict-transport-security")
      assert hsts == "max-age=31536000; includeSubDomains"
    end

    test "includes Umami in CSP on hosted deployments", %{conn: conn} do
      Application.put_env(:crit, :selfhosted, false)
      on_exit(fn -> Application.delete_env(:crit, :selfhosted) end)

      conn = get(conn, ~p"/")
      [csp] = get_resp_header(conn, "content-security-policy")

      assert csp =~ "https://cloud.umami.is"
      assert csp =~ "https://gateway.umami.is"
      assert csp =~ "https://api-gateway.umami.dev"
    end

    test "omits Umami from CSP on self-hosted deployments", %{conn: conn} do
      Application.put_env(:crit, :selfhosted, true)
      on_exit(fn -> Application.delete_env(:crit, :selfhosted) end)

      conn = get(conn, ~p"/")
      [csp] = get_resp_header(conn, "content-security-policy")

      refute csp =~ "cloud.umami.is"
    end
  end

  describe "Umami analytics script" do
    test "renders on hosted deployments", %{conn: conn} do
      Application.put_env(:crit, :selfhosted, false)
      on_exit(fn -> Application.delete_env(:crit, :selfhosted) end)

      html = get(conn, ~p"/") |> html_response(200)

      assert html =~ "cloud.umami.is/script.js"
      assert html =~ "24d521a2-4440-4f90-9cbb-f0b2abcd67e2"
    end

    test "omits on self-hosted deployments", %{conn: conn} do
      Application.put_env(:crit, :selfhosted, true)
      on_exit(fn -> Application.delete_env(:crit, :selfhosted) end)

      html = get(conn, ~p"/privacy") |> html_response(200)

      refute html =~ "cloud.umami.is"
    end
  end
end
