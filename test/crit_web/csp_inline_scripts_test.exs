defmodule CritWeb.CSPInlineScriptsTest do
  @moduledoc """
  Regression test: every inline `<script>` rendered in a response body must
  have its sha256-base64 hash listed in the `script-src` directive of the
  `Content-Security-Policy` header.

  When you add or modify an inline `<script>`, the browser will block it
  unless the new hash is added to `CritWeb.Plugs.SecurityHeaders`. This
  test catches that class of bug across the routes listed in @routes.
  """

  use CritWeb.ConnCase, async: false

  # Routes that exercise both the root layout (long theme bootstrap) and
  # the device_html layout (short theme bootstrap).
  @routes [
    "/",
    "/auth/cli",
    "/auth/cli/success"
  ]

  test "every inline <script> in rendered pages has its hash in the CSP allowlist", %{conn: conn} do
    results =
      Enum.map(@routes, fn path ->
        resp = get(conn, path)
        body = resp.resp_body
        csp = get_resp_header(resp, "content-security-policy") |> List.first() || ""

        scripts =
          body
          |> extract_inline_scripts()
          # Skip dynamic JSON-LD — its content varies per request and would
          # require 'unsafe-inline'. Currently no route under test emits it,
          # but we filter defensively so the test isn't accidentally weakened.
          |> Enum.reject(&json_ld_script?/1)

        {path, csp, scripts}
      end)

    # Forward direction: every rendered inline script's hash must be allowed.
    for {path, csp, scripts} <- results,
        content <- scripts do
      hash = sha256_base64(content)
      directive = "'sha256-#{hash}'"

      assert String.contains?(csp, directive),
             """
             Inline <script> on #{path} has hash #{hash} but CSP script-src does not include it.

             CSP header: #{csp}

             Script content (first 200 chars):
             #{String.slice(content, 0, 200)}
             """
    end

    # Reverse direction: every hash in the CSP must be used by at least one
    # rendered script across the tested routes. Catches stale entries.
    csp =
      results
      |> List.first()
      |> elem(1)

    csp_hashes = extract_csp_hashes(csp)

    rendered_hashes =
      results
      |> Enum.flat_map(fn {_path, _csp, scripts} -> scripts end)
      |> Enum.map(&sha256_base64/1)
      |> MapSet.new()

    unused = Enum.reject(csp_hashes, &MapSet.member?(rendered_hashes, &1))

    assert unused == [],
           """
           CSP script-src contains hashes not produced by any rendered inline <script>
           across the tested routes (#{Enum.join(@routes, ", ")}):

           Unused hashes: #{inspect(unused)}

           Either remove them from CritWeb.Plugs.SecurityHeaders or add a route
           that renders the script to @routes in this test.
           """
  end

  defp extract_inline_scripts(html) do
    Regex.scan(~r/<script(?![^>]*\bsrc=)[^>]*>(.*?)<\/script>/s, html)
    |> Enum.map(fn [_, content] -> content end)
  end

  defp json_ld_script?(content) do
    String.starts_with?(String.trim_leading(content), "{") and
      String.contains?(content, "@context")
  end

  defp sha256_base64(content) do
    :crypto.hash(:sha256, content) |> Base.encode64()
  end

  defp extract_csp_hashes(csp) do
    Regex.scan(~r/'sha256-([A-Za-z0-9+\/=]+)'/, csp)
    |> Enum.map(fn [_, h] -> h end)
  end
end
