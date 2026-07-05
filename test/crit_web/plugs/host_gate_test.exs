defmodule CritWeb.Plugs.HostGateTest do
  use CritWeb.ConnCase, async: false

  import Crit.ReviewsFixtures

  setup do
    old_canonical = Application.get_env(:crit, :canonical_host)
    old_preview = Application.get_env(:crit, :preview_host)

    Application.put_env(:crit, :canonical_host, "app.example.test")
    Application.put_env(:crit, :preview_host, "preview.example.test")

    on_exit(fn ->
      if is_nil(old_canonical),
        do: Application.delete_env(:crit, :canonical_host),
        else: Application.put_env(:crit, :canonical_host, old_canonical)

      if is_nil(old_preview),
        do: Application.delete_env(:crit, :preview_host),
        else: Application.put_env(:crit, :preview_host, old_preview)
    end)

    :ok
  end

  test "preview host allows raw paths", %{conn: conn} do
    review =
      review_fixture(%{
        review_type: :preview,
        files: [%{"path" => "index.html", "content" => "<html></html>"}]
      })

    conn =
      conn
      |> Map.put(:host, "preview.example.test")
      |> get(~p"/r/#{review.token}/raw/index.html")

    assert response(conn, 200) =~ "<html>"
  end

  test "preview host allows preview-agent static scripts", %{conn: conn} do
    conn =
      conn
      |> Map.put(:host, "preview.example.test")
      |> get("/preview-agent/agent-protocol.js")

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") |> hd() =~ "javascript"
  end

  test "preview host blocks app routes", %{conn: conn} do
    conn =
      conn
      |> Map.put(:host, "preview.example.test")
      |> get(~p"/dashboard")

    assert response(conn, 404)
  end

  test "preview host blocks interactive review LiveView", %{conn: conn} do
    review = review_fixture()

    conn =
      conn
      |> Map.put(:host, "preview.example.test")
      |> get(~p"/r/#{review.token}")

    assert response(conn, 404)
  end

  test "preview host blocks non-GET to raw paths", %{conn: conn} do
    review =
      review_fixture(%{
        review_type: :preview,
        files: [%{"path" => "index.html", "content" => "<html></html>"}]
      })

    conn =
      conn
      |> Map.put(:host, "preview.example.test")
      |> post(~p"/r/#{review.token}/raw/index.html")

    assert response(conn, 404)
  end

  test "preview host allows /health", %{conn: conn} do
    conn =
      conn
      |> Map.put(:host, "preview.example.test")
      |> get("/health")

    assert conn.status == 200
  end

  test "unknown host returns 404", %{conn: conn} do
    conn =
      conn
      |> Map.put(:host, "evil.example.test")
      |> get(~p"/")

    assert response(conn, 404)
  end

  test "localhost bypasses host gate in dev/test", %{conn: conn} do
    conn =
      conn
      |> Map.put(:host, "127.0.0.1")
      |> get(~p"/")

    assert html_response(conn, 200)
  end

  test "canonical host keeps app routes reachable", %{conn: conn} do
    conn =
      conn
      |> Map.put(:host, "app.example.test")
      |> get(~p"/")

    assert html_response(conn, 200)
  end
end
