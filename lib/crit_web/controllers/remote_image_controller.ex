defmodule CritWeb.RemoteImageController do
  @moduledoc """
  Serves the click-to-load frame for one remote image:
  `GET /remote-image?src=<http(s) URL>&alt=<text>`.

  Shared documents and comments may be written by an AI agent, so the review
  page's CSP blocks remote images outside `CritWeb.Plugs.SecurityHeaders`'
  allowlist and crit-remote-images.js shows a placeholder instead. When the
  reader clicks it, the page loads this route in a sandboxed iframe. The frame
  shows the image and posts its size (or a failure) back to the review page.

  Port of crit's `handleRemoteImage` (internal/server/csp.go): the inline
  script and the policy match it byte for byte.
  """
  use CritWeb, :controller

  # Reports the image's size (or failure) to the review page so it can size
  # the frame. It is the frame's only script, allowed by hash.
  @frame_script """
  (function () {
    var img = document.getElementById('img');
    function send(status) {
      parent.postMessage({ type: 'crit-remote-image', status: status, width: img.naturalWidth, height: img.naturalHeight }, '*');
    }
    if (img.complete) {
      send(img.naturalWidth ? 'loaded' : 'error');
      return;
    }
    img.addEventListener('load', function () { send('loaded'); });
    img.addEventListener('error', function () { send('error'); });
  })();\
  """

  @frame_script_hash "'sha256-" <> Base.encode64(:crypto.hash(:sha256, @frame_script)) <> "'"

  # Lets the frame load one remote image and nothing else. The sandbox
  # directive gives it an opaque origin even when it is opened directly.
  @frame_csp Enum.join(
               [
                 "sandbox allow-scripts",
                 "default-src 'none'",
                 "img-src http: https:",
                 "style-src 'unsafe-inline'",
                 "script-src " <> @frame_script_hash,
                 "base-uri 'none'",
                 "form-action 'none'",
                 "frame-ancestors 'self'"
               ],
               "; "
             )

  @max_src_bytes 8 * 1024
  @max_alt_bytes 1024

  @doc false
  def frame_script, do: @frame_script

  @doc false
  def frame_csp, do: @frame_csp

  # src and alt are HTML-escaped into the page, and the frame's CSP allows
  # only the hashed script.
  # sobelow_skip ["XSS.SendResp"]
  def show(conn, params) do
    with {:ok, src} <- validate_src(params["src"]) do
      alt = truncate_alt(params["alt"])

      page =
        ~s(<!doctype html><html><head><meta charset="utf-8"><meta name="referrer" content="no-referrer">) <>
          "<style>html,body{margin:0;padding:0;background:transparent;overflow:hidden}" <>
          "img{display:block;width:100%;height:100%;object-fit:contain}</style></head><body>" <>
          ~s(<img id="img" src="#{escape(src)}" alt="#{escape(alt)}">) <>
          "<script>" <> @frame_script <> "</script></body></html>"

      conn
      |> put_frame_headers()
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_content_type("text/html")
      |> send_resp(200, page)
    else
      {:error, message} ->
        conn
        |> put_frame_headers()
        |> put_resp_content_type("text/plain")
        |> send_resp(400, message)
    end
  end

  # Replaces the site-wide policy from CritWeb.Plugs.SecurityHeaders.
  defp put_frame_headers(conn) do
    conn
    |> put_resp_header("content-security-policy", @frame_csp)
    |> put_resp_header("referrer-policy", "no-referrer")
    |> put_resp_header("x-content-type-options", "nosniff")
  end

  defp validate_src(src) when is_binary(src) and byte_size(src) > @max_src_bytes,
    do: {:error, "src too long"}

  defp validate_src(src) when is_binary(src) do
    case URI.new(src) do
      {:ok, %URI{scheme: scheme, host: host} = uri}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        {:ok, URI.to_string(uri)}

      _ ->
        {:error, "src must be an http(s) URL"}
    end
  end

  defp validate_src(_), do: {:error, "src must be an http(s) URL"}

  defp truncate_alt(alt) when is_binary(alt) do
    alt = if String.valid?(alt), do: alt, else: ""

    if byte_size(alt) > @max_alt_bytes do
      # Cut on a character boundary.
      alt |> binary_part(0, @max_alt_bytes) |> String.chunk(:valid) |> List.first("")
    else
      alt
    end
  end

  defp truncate_alt(_), do: ""

  defp escape(value), do: value |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
