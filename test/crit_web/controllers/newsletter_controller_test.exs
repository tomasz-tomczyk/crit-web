defmodule CritWeb.NewsletterControllerTest do
  use CritWeb.ConnCase, async: false

  setup do
    orig = Application.get_env(:crit, :selfhosted)

    on_exit(fn ->
      if is_nil(orig),
        do: Application.delete_env(:crit, :selfhosted),
        else: Application.put_env(:crit, :selfhosted, orig)
    end)

    :ok
  end

  test "serves newsletter HTML on hosted instances", %{conn: conn} do
    Application.put_env(:crit, :selfhosted, false)

    conn = get(conn, ~p"/newsletter/2026-09-first-update")
    assert response(conn, 200) =~ "Story mode, a new renderer, and finish hooks"
    assert response(conn, 200) =~ ~s(src="https://assets.crit.md/newsletter/2026-09-first-update/)
    refute response(conn, 200) =~ "{{{ pm:unsubscribe }}}"
  end

  test "serves newsletter images on hosted instances", %{conn: conn} do
    Application.put_env(:crit, :selfhosted, false)

    conn = get(conn, ~p"/newsletter/2026-09-first-update/images/crit-logo.png")
    assert response(conn, 200)
    assert get_resp_header(conn, "content-type") |> hd() =~ "image/png"
  end

  test "404s newsletter on selfhosted instances", %{conn: conn} do
    Application.put_env(:crit, :selfhosted, true)

    conn = get(conn, ~p"/newsletter/2026-09-first-update")
    assert response(conn, 404)
  end

  test "404s unknown slug", %{conn: conn} do
    Application.put_env(:crit, :selfhosted, false)

    conn = get(conn, ~p"/newsletter/does-not-exist")
    assert response(conn, 404)
  end

  test "archive lists the first issue and exposes an email signup", %{conn: conn} do
    Application.put_env(:crit, :selfhosted, false)
    html = conn |> get(~p"/newsletter") |> html_response(200)
    assert html =~ "September 29, 2026"
    assert html =~ ~s(href="/newsletter/2026-09-first-update")
    assert html =~ ~s(action="/newsletter/subscribe")
  end

  test "anonymous signup can be confirmed and unsubscribed; GETs do not change consent", %{
    conn: conn
  } do
    Application.put_env(:crit, :selfhosted, false)

    html =
      conn
      |> post(~p"/newsletter/subscribe", newsletter: %{email: "reader@example.com"})
      |> html_response(200)

    assert html =~ "Check your inbox"
    assert_receive {:email, message}
    [_, token] = Regex.run(~r{/newsletter/confirm/(\S+)}, message.text_body)
    [_, unsubscribe_token] = Regex.run(~r{/newsletter/unsubscribe/(\S+)}, message.text_body)
    confirmation = get(recycle(conn), ~p"/newsletter/confirm/#{token}")
    assert html_response(confirmation, 200) =~ "Confirm subscription"
    assert get_resp_header(confirmation, "referrer-policy") == ["no-referrer"]
    assert Crit.Newsletters.recipients() == []
    html = conn |> recycle() |> post(~p"/newsletter/confirm/#{token}", %{}) |> html_response(200)
    assert html =~ "The next Crit update"
    assert Crit.Newsletters.recipients() == ["reader@example.com"]

    assert conn
           |> recycle()
           |> get(~p"/newsletter/unsubscribe/#{unsubscribe_token}")
           |> html_response(200) =~ "Unsubscribe"

    assert Crit.Newsletters.recipients() == ["reader@example.com"]

    assert conn
           |> recycle()
           |> post(~p"/newsletter/unsubscribe/#{unsubscribe_token}", %{})
           |> html_response(200) =~ "unsubscribed from Crit updates"

    assert Crit.Newsletters.recipients() == []
  end

  test "invalid signup and tokens produce a useful response", %{conn: conn} do
    Application.put_env(:crit, :selfhosted, false)

    assert conn
           |> post(~p"/newsletter/subscribe", newsletter: %{email: "invalid"})
           |> html_response(422) =~ "must be a valid email address"

    for path <- ["/newsletter/confirm/invalid", "/newsletter/unsubscribe/invalid"] do
      assert conn |> recycle() |> get(path) |> html_response(422) =~ "This link has expired"
      assert conn |> recycle() |> post(path, %{}) |> html_response(422) =~ "This link has expired"
    end
  end

  test "archive and subscription endpoints are unavailable on selfhosted instances", %{conn: conn} do
    Application.put_env(:crit, :selfhosted, true)

    for path <- ["/newsletter", "/newsletter/confirm/invalid", "/newsletter/unsubscribe/invalid"] do
      assert conn |> recycle() |> get(path) |> response(404)
    end

    assert conn
           |> recycle()
           |> post(~p"/newsletter/subscribe", newsletter: %{email: "reader@example.com"})
           |> response(404)

    refute_receive {:email, _}
  end

  test "subscription writes are rate limited", %{conn: conn} do
    Application.put_env(:crit, :selfhosted, false)
    original = Application.get_env(:crit, CritWeb.Plugs.RateLimit)
    Application.put_env(:crit, CritWeb.Plugs.RateLimit, disabled: false)
    on_exit(fn -> Application.put_env(:crit, CritWeb.Plugs.RateLimit, original) end)
    conn = %{conn | remote_ip: {192, 0, 2, 83}}

    for _ <- 1..5 do
      assert conn
             |> recycle()
             |> post(~p"/newsletter/subscribe", newsletter: %{email: "invalid"})
             |> response(422)
    end

    limited =
      conn |> recycle() |> post(~p"/newsletter/subscribe", newsletter: %{email: "invalid"})

    assert response(limited, 429)
    assert get_resp_header(limited, "retry-after") != []
  end

  test "delivery failure leaves signup retryable", %{conn: conn} do
    Application.put_env(:crit, :selfhosted, false)
    original = Application.get_env(:crit, Crit.Mailer)

    Application.put_env(:crit, Crit.Mailer,
      adapter: CritWeb.NewsletterControllerTest.FailingMailer
    )

    on_exit(fn -> Application.put_env(:crit, Crit.Mailer, original) end)

    assert conn
           |> post(~p"/newsletter/subscribe", newsletter: %{email: "reader@example.com"})
           |> html_response(503) =~ "Please try again"

    assert Crit.Repo.get_by(Crit.Accounts.MarketingConsentEvent, email: "reader@example.com") ==
             nil

    Application.put_env(:crit, Crit.Mailer, original)

    assert conn
           |> recycle()
           |> post(~p"/newsletter/subscribe", newsletter: %{email: "reader@example.com"})
           |> html_response(200) =~ "Check your inbox"

    assert_receive {:email, _}
  end

  test "sitemap includes the archive and published issue only on hosted instances", %{conn: conn} do
    Application.put_env(:crit, :selfhosted, false)
    sitemap = conn |> get(~p"/sitemap.xml") |> response(200)
    assert sitemap =~ "/newsletter</loc>"
    assert sitemap =~ "/newsletter/2026-09-first-update</loc>"
    refute sitemap =~ "/newsletter/confirm/"
    Application.put_env(:crit, :selfhosted, true)
    sitemap = conn |> recycle() |> get(~p"/sitemap.xml") |> response(200)
    refute sitemap =~ "/newsletter"
  end
end

defmodule CritWeb.NewsletterControllerTest.FailingMailer do
  use Swoosh.Adapter
  def deliver(_email, _config), do: {:error, :unavailable}
end
