defmodule CritWeb.Plugs.Precompressed do
  @moduledoc """
  Serves `/pierre/<name>.js` from `priv/static/pierre/<name>.js.gz`.

  The vendored @pierre/diffs bundle (see `scripts/sync-pierre.sh`) ships only
  as gzip, exactly as crit builds it. Browsers get the gzip bytes as-is with
  `Content-Encoding: gzip`; a client that refuses gzip gets them decompressed.
  Mirrors crit's `internal/server/precompressed.go`.

  The bundle's chunks import each other by relative, undigested names, so it
  lives outside esbuild and `phx.digest`. Chunk names are content hashes and
  are cached for a year. The entry, worker and palette files keep their names
  across releases, so the browser revalidates them with an ETag.
  """
  @behaviour Plug

  import Plug.Conn

  @prefix "pierre"
  @name ~r/\A[A-Za-z0-9_-]+\.js\z/

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{path_info: [@prefix, name]} = conn, _opts) when is_binary(name) do
    with true <- conn.method in ["GET", "HEAD"],
         true <- Regex.match?(@name, name),
         path = Path.join(dir(), name <> ".gz"),
         {:ok, %File.Stat{type: :regular} = stat} <- File.stat(path) do
      serve(conn, name, path, stat)
    else
      _ -> conn
    end
  end

  def call(conn, _opts), do: conn

  defp serve(conn, name, path, stat) do
    etag = ~s("#{stat.size}-#{stat.mtime |> :calendar.datetime_to_gregorian_seconds()}")

    conn =
      conn
      |> put_resp_content_type("text/javascript")
      |> put_resp_header("vary", "Accept-Encoding")
      |> put_resp_header("cache-control", cache_control(name))
      |> put_resp_header("etag", etag)

    cond do
      etag_matches?(conn, etag) ->
        conn |> send_resp(304, "") |> halt()

      accepts_gzip?(conn) ->
        conn
        |> put_resp_header("content-encoding", "gzip")
        |> send_file(200, path)
        |> halt()

      true ->
        conn |> send_resp(200, :zlib.gunzip(File.read!(path))) |> halt()
    end
  end

  # If-None-Match uses weak comparison (RFC 9110 13.1.2): `*` matches any
  # current representation, and a `W/` prefix is ignored on either side.
  defp etag_matches?(conn, etag) do
    conn
    |> get_req_header("if-none-match")
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.map(&String.trim/1)
    |> Enum.any?(&(&1 == "*" or weak(&1) == weak(etag)))
  end

  defp weak("W/" <> tag), do: tag
  defp weak(tag), do: tag

  defp cache_control("chunk-" <> _), do: "public, max-age=31536000, immutable"
  defp cache_control(_), do: "public, no-cache"

  # "gzip;q=0" refuses the encoding; any other gzip entry accepts it.
  defp accepts_gzip?(conn) do
    conn
    |> get_req_header("accept-encoding")
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.any?(fn part ->
      case part |> String.trim() |> String.split(";", parts: 2) do
        [enc | params] -> String.downcase(String.trim(enc)) == "gzip" and not refused?(params)
        _ -> false
      end
    end)
  end

  defp refused?([params]) do
    case Regex.run(~r/q=([0-9.]+)/, params) do
      [_, q] -> match?({v, _} when v == 0, Float.parse(q))
      _ -> false
    end
  end

  defp refused?(_), do: false

  defp dir, do: Application.app_dir(:crit, ["priv", "static", @prefix])
end
