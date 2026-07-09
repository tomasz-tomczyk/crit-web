# MANUAL QA: see test/manual/share_receiver_qa.md
defmodule CritWeb.ShareReceiverControllerTest do
  use CritWeb.ConnCase, async: true

  describe "GET /share-receiver" do
    test "renders a minimal page", %{conn: conn} do
      html = conn |> get(~p"/share-receiver") |> html_response(200)
      assert html =~ ~s|id="share-receiver"|
      # No nested <html>: should appear exactly once.
      assert html |> String.split("<html") |> length() == 2
    end

    test "is noindexed", %{conn: conn} do
      conn = get(conn, ~p"/share-receiver")
      assert get_resp_header(conn, "x-robots-tag") == ["noindex"]
    end

    test "does not load app.js or app.css", %{conn: conn} do
      html = conn |> get(~p"/share-receiver") |> html_response(200)
      refute html =~ "/assets/js/app.js"
      refute html =~ "/assets/css/app.css"
    end

    test "loads the share_receiver bundle", %{conn: conn} do
      html = conn |> get(~p"/share-receiver") |> html_response(200)
      assert html =~ "/assets/js/share_receiver"
    end

    test "source exposes share policy relay operation" do
      root = File.cwd!()
      index = File.read!(Path.join(root, "assets/js/share_receiver/index.js"))
      handlers = File.read!(Path.join(root, "assets/js/share_receiver/handlers.js"))

      assert index =~ "sharePolicy: handlers.sharePolicy"
      assert handlers =~ "export async function sharePolicy"
      assert handlers =~ "/api/share-policy"
    end
  end
end
