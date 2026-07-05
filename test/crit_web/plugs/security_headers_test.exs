defmodule CritWeb.Plugs.SecurityHeadersTest do
  use CritWeb.ConnCase, async: false

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

    test "omits x-frame-options on preview host", %{conn: conn} do
      Application.put_env(:crit, :canonical_host, "app.example.test")
      Application.put_env(:crit, :preview_host, "preview.example.test")

      on_exit(fn ->
        Application.delete_env(:crit, :canonical_host)
        Application.delete_env(:crit, :preview_host)
      end)

      conn =
        conn
        |> Map.put(:host, "preview.example.test")
        |> get(~p"/agent-marker.css")

      assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
      assert get_resp_header(conn, "x-frame-options") == []
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

    test "allows preview origin in frame-src when PREVIEW_HOST is set", %{conn: conn} do
      Application.put_env(:crit, :canonical_host, "app.example.test")
      Application.put_env(:crit, :preview_host, "preview.example.test")

      on_exit(fn ->
        Application.delete_env(:crit, :canonical_host)
        Application.delete_env(:crit, :preview_host)
      end)

      conn =
        conn
        |> Map.put(:host, "app.example.test")
        |> get(~p"/")

      [csp] = get_resp_header(conn, "content-security-policy")

      assert csp =~
               "frame-src 'self' https://www.youtube.com https://www.youtube-nocookie.com http://preview.example.test"

      refute csp =~ "frame-src 'self' https://www.youtube.com https://www.youtube-nocookie.com;"
    end

    test "omits preview origin from frame-src when PREVIEW_HOST is unset", %{conn: conn} do
      old_preview = Application.get_env(:crit, :preview_host)
      Application.delete_env(:crit, :preview_host)

      on_exit(fn ->
        if is_nil(old_preview),
          do: Application.delete_env(:crit, :preview_host),
          else: Application.put_env(:crit, :preview_host, old_preview)
      end)

      conn = get(conn, ~p"/")
      [csp] = get_resp_header(conn, "content-security-policy")

      assert csp =~
               "frame-src 'self' https://www.youtube.com https://www.youtube-nocookie.com; object-src 'none'"
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
