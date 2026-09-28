defmodule CritWeb.Plugs.PrecompressedTest do
  # Through the endpoint, so the plug's position before Plug.Static and the
  # router is covered too.
  use CritWeb.ConnCase, async: true

  @pierre_dir Path.join([File.cwd!(), "priv", "static", "pierre"])

  defp gzip_bytes(name), do: File.read!(Path.join(@pierre_dir, name <> ".gz"))

  defp chunk_name do
    @pierre_dir
    |> File.ls!()
    |> Enum.find(&String.starts_with?(&1, "chunk-"))
    |> String.replace_suffix(".gz", "")
  end

  test "serves the stored gzip bytes to a gzip-accepting client", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept-encoding", "gzip, deflate, br")
      |> get("/pierre/pierre-diffs.js")

    assert conn.status == 200
    assert get_resp_header(conn, "content-encoding") == ["gzip"]
    assert ["text/javascript" <> _] = get_resp_header(conn, "content-type")
    assert get_resp_header(conn, "vary") == ["Accept-Encoding"]
    assert conn.resp_body == gzip_bytes("pierre-diffs.js")
  end

  test "decompresses for a client that does not accept gzip", %{conn: conn} do
    conn = get(conn, "/pierre/palettes.js")

    assert conn.status == 200
    assert get_resp_header(conn, "content-encoding") == []
    assert conn.resp_body == :zlib.gunzip(gzip_bytes("palettes.js"))
    assert conn.resp_body =~ "window.crit.palettes="
  end

  test "gzip;q=0 refuses the encoding", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept-encoding", "gzip;q=0, br")
      |> get("/pierre/palettes.js")

    assert get_resp_header(conn, "content-encoding") == []
  end

  test "entry files revalidate; content-hashed chunks cache for a year", %{conn: conn} do
    entry = get(conn, "/pierre/pierre-worker.js")
    assert [cache] = get_resp_header(entry, "cache-control")
    assert cache =~ "no-cache"

    chunk = get(build_conn(), "/pierre/" <> chunk_name())
    assert [cache] = get_resp_header(chunk, "cache-control")
    assert cache =~ "max-age=31536000"
    assert cache =~ "immutable"
  end

  test "answers 304 when the ETag matches", %{conn: conn} do
    [etag] = conn |> get("/pierre/palettes.js") |> get_resp_header("etag")

    conn =
      build_conn()
      |> put_req_header("if-none-match", etag)
      |> get("/pierre/palettes.js")

    assert conn.status == 304
    assert conn.resp_body == ""
  end

  test "answers 304 for a list, a weak match or *", %{conn: conn} do
    [etag] = conn |> get("/pierre/palettes.js") |> get_resp_header("etag")

    for header <- [~s("other", #{etag}), "W/" <> etag, "*"] do
      conn =
        build_conn()
        |> put_req_header("if-none-match", header)
        |> get("/pierre/palettes.js")

      assert conn.status == 304, "expected 304 for If-None-Match: #{header}"
    end
  end

  test "serves the file when no listed ETag matches", %{conn: conn} do
    conn =
      conn
      |> put_req_header("if-none-match", ~s("other", W/"stale"))
      |> get("/pierre/palettes.js")

    assert conn.status == 200
  end

  test "HEAD returns headers without a body", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept-encoding", "gzip")
      |> head("/pierre/pierre-diffs.js")

    assert conn.status == 200
    assert get_resp_header(conn, "content-encoding") == ["gzip"]
    assert conn.resp_body == ""
  end

  test "unknown, nested and non-js names fall through to a 404", %{conn: conn} do
    assert get(conn, "/pierre/missing.js").status == 404
    assert get(build_conn(), "/pierre/pierre-diffs.js.gz").status == 404
    assert get(build_conn(), "/pierre/../mix.exs").status == 404
    assert get(build_conn(), "/pierre/nested/pierre-diffs.js").status == 404
  end
end
