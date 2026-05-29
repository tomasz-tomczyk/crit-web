defmodule CritWeb.RawController do
  use CritWeb, :controller

  alias Crit.Review
  alias Crit.Reviews

  plug :require_review_scope

  # The 7 transport-agnostic agent scripts crit injects into preview iframes,
  # vendored verbatim into priv/static/preview-agent/. Order matters and must
  # match crit's `agentScriptFiles` (server.go): protocol first, helpers next,
  # the main agent entry point last. Keeping the order identical preserves
  # DOM-anchor compatibility across the crit (Go) and crit-web (Phoenix)
  # renderers. `agent-marker.css` is served separately and is NOT injected.
  @agent_script_files [
    "agent-protocol.js",
    "agent-anchor-utils.js",
    "agent-marker-overlay.js",
    "agent-mutation-batcher.js",
    "agent-resolution.js",
    "agent-reanchor-state.js",
    "crit-agent.js"
  ]

  # Marker overlay CSS, inlined into preview HTML. crit local serves this at
  # `/agent-marker.css` and the vendored crit-agent.js fetches it from there —
  # but the preview sandbox CSP sets `connect-src 'none'` (and crit-web serves
  # it under /preview-agent/, not root), so that fetch fails. Inlining it as a
  # `<style>` makes the agent's failed fetch harmless and the markers styled.
  # Read at compile time; `@external_resource` triggers a recompile on change.
  @marker_css_path Path.join([
                     __DIR__,
                     "..",
                     "..",
                     "..",
                     "priv",
                     "static",
                     "preview-agent",
                     "agent-marker.css"
                   ])
  @external_resource @marker_css_path
  @marker_css File.read!(@marker_css_path)

  # Restrictive sandbox CSP for preview HTML rendered inside the same-origin
  # iframe. No external origins and the preview itself cannot frame anything
  # (`frame-src 'none'`). Inline styles/scripts are allowed because shared
  # static pages routinely rely on them and the content is already
  # untrusted-but-sandboxed. `connect-src 'self'` (not 'none') so the injected
  # crit-agent can fetch its same-origin marker CSS without a CSP violation —
  # external egress is still blocked since only 'self' is allowed. (crit local
  # serves this with no CSP at all; this is still far stricter.)
  @preview_csp Enum.join(
                 [
                   "default-src 'self' 'unsafe-inline' 'unsafe-eval'",
                   "img-src 'self' data: blob:",
                   "font-src 'self' data:",
                   "connect-src 'self'",
                   "frame-src 'none'"
                 ],
                 "; "
               )

  def show(conn, %{"token" => token, "file_path" => path_segments})
      when is_list(path_segments) do
    file_path = Enum.join(path_segments, "/")
    scope = conn.assigns[:current_scope] || %Crit.Accounts.Scope{}

    with %Review{} = review <- Reviews.get_by_token(token),
         :ok <- Reviews.check_org_access(review, scope),
         %{} = file <-
           Enum.find(review.files, fn f -> f.file_path == file_path end),
         basename when basename != :unsafe <- safe_basename(file.file_path),
         {:ok, content} <- decode_content(file) do
      preview? = review.review_type == :preview
      mime = mime_for(file_path, preview?)

      conn
      # The raw endpoint is a read-only GET addressed by an unguessable token,
      # loaded inside the sandboxed (opaque-origin) preview iframe — so every
      # subresource request is cross-origin. Plug.CSRFProtection raises
      # InvalidCrossOriginRequestError (403) for a cross-origin GET that returns
      # a JavaScript content-type (its anti-`<script src>` exfiltration guard),
      # which blocked a preview's own app.js. This endpoint mutates no state and
      # has no CSRF surface, so skip the guard. The check runs in a
      # register_before_send hook, so setting this here (before send_resp) is
      # honoured.
      |> put_private(:plug_skip_csrf_protection, true)
      |> put_resp_content_type(mime)
      |> put_resp_header("content-disposition", ~s(inline; filename="#{basename}"))
      |> maybe_preview_csp(preview?, mime)
      |> send_resp(200, maybe_inject_agent_scripts(content, preview?, mime))
    else
      _ -> conn |> put_status(404) |> text("not found")
    end
  end

  # The injected crit-agent fetches its marker overlay CSS from
  # `<origin>/agent-marker.css` (hard-coded in the vendored, byte-identical
  # crit-agent.js — crit local serves it at this same root path). Serve it here
  # so the fetch succeeds instead of 404ing in the iframe console.
  def marker_css(conn, _params) do
    conn
    |> put_resp_content_type("text/css")
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> send_resp(200, @marker_css)
  end

  # base64 snapshots (binary assets like images) are decoded back to raw bytes.
  defp decode_content(%{encoding: "base64", content: content}), do: Base.decode64(content)
  defp decode_content(%{content: content}), do: {:ok, content}

  # Preview reviews carry real web assets (HTML/CSS/JS/images) that must be
  # served with their true MIME type so the iframe renders them. Files-mode
  # reviews serve source files for in-browser reading and keep the historical
  # `text/plain` behaviour (so e.g. `.ex` isn't offered as an octet download).
  # `put_resp_content_type/2` appends `; charset=utf-8` to the bare type.
  defp mime_for(file_path, true), do: MIME.from_path(file_path)
  defp mime_for(_file_path, false), do: "text/plain"

  # Inject the agent scripts only into preview HTML, mirroring crit's
  # `servePreviewHTML`: insert before the last `</body>`, falling back to an
  # append when no closing body tag exists.
  defp maybe_inject_agent_scripts(content, true, "text/html") do
    scripts =
      Enum.map_join(@agent_script_files, fn name ->
        ~s(<script src="/preview-agent/#{name}"></script>)
      end)

    inject_before_body_close(content, scripts)
  end

  defp maybe_inject_agent_scripts(content, _preview?, _content_type), do: content

  defp inject_before_body_close(html, scripts) do
    case last_body_close_index(html) do
      nil -> html <> scripts
      idx -> binary_part(html, 0, idx) <> scripts <> binary_part(html, idx, byte_size(html) - idx)
    end
  end

  # Case-insensitive search for the last "</body>" occurrence, mirroring
  # crit's `bytes.LastIndex(bytes.ToLower(body), "</body>")`.
  defp last_body_close_index(html) do
    downcased = String.downcase(html)

    case :binary.matches(downcased, "</body>") do
      [] -> nil
      matches -> matches |> List.last() |> elem(0)
    end
  end

  defp maybe_preview_csp(conn, true, "text/html") do
    put_resp_header(conn, "content-security-policy", preview_csp())
  end

  defp maybe_preview_csp(conn, _preview?, _content_type), do: conn

  # In dev, Phoenix LiveReload injects an iframe pointing at
  # /phoenix/live_reload/frame into every page; `frame-src 'none'` blocks it and
  # logs a CSP violation in the console. Relax frame-src to 'self' when the code
  # reloader is enabled (dev only) so the dev console stays clean; prod keeps the
  # strict `frame-src 'none'`.
  defp preview_csp do
    if CritWeb.Endpoint.config(:code_reloader) do
      String.replace(@preview_csp, "frame-src 'none'", "frame-src 'self'")
    else
      @preview_csp
    end
  end

  # Mirrors `CritWeb.UserAuth.on_mount(:require_review_scope, ...)` for the
  # plain-controller raw endpoint. On selfhosted+OAuth instances, anonymous
  # visitors must hit the OAuth login flow with `return_to` set to the raw URL
  # so the LiveView gate's protection isn't bypassed by the raw endpoint.
  defp require_review_scope(conn, _opts) do
    cond do
      conn.assigns.current_scope.user ->
        conn

      Crit.Config.selfhosted_oauth?() ->
        return_to = conn.request_path <> maybe_query(conn.query_string)

        conn
        |> Phoenix.Controller.redirect(
          to: "/auth/login?return_to=#{URI.encode_www_form(return_to)}"
        )
        |> halt()

      true ->
        conn
    end
  end

  defp maybe_query(""), do: ""
  defp maybe_query(qs), do: "?" <> qs

  # RFC 6266 requires the `filename=` parameter to be ASCII. Reject anything
  # outside printable ASCII (0x20–0x7e), plus the quote and backslash that
  # would break the quoted-string in the content-disposition header.
  # We deliberately do NOT emit a `filename*=UTF-8''…` fallback here —
  # callers with non-ASCII basenames get a 404, which is acceptable.
  defp safe_basename(path) do
    base = Path.basename(path)

    if String.match?(base, ~r/[^\x20-\x7e]|["\\]/), do: :unsafe, else: base
  end
end
