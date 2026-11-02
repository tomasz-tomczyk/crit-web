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

  test "encoded dot-dot slugs and image names 404 without leaving the archive", %{conn: conn} do
    Application.put_env(:crit, :selfhosted, false)

    secret = "CRIT-NEWSLETTER-OUTSIDE-#{System.unique_integer([:positive])}"
    root = Path.join(:code.priv_dir(:crit), "newsletters")
    outside = Path.join(System.tmp_dir!(), "crit-nl-#{System.unique_integer([:positive])}")
    draft = Path.join(root, "draft-not-published")
    File.mkdir_p!(Path.join(outside, "images"))
    File.write!(Path.join(outside, "index.html"), secret)
    File.write!(Path.join(outside, "images/leak.png"), secret)
    File.mkdir_p!(draft)
    File.write!(Path.join(draft, "index.html"), secret)

    on_exit(fn ->
      File.rm_rf!(outside)
      File.rm_rf!(draft)
    end)

    slug = root |> relative_escape(outside) |> encode_slug()

    page = get(conn, "/newsletter/#{slug}")
    assert response(page, 404)
    refute response(page, 404) =~ secret

    # Extra path segments never match the newsletter route. Still must not
    # serve a file from outside the archive.
    escaped = get(recycle(conn), "/newsletter/..%2f..%2fetc/passwd")
    assert response(escaped, 404)
    refute response(escaped, 404) =~ "root:"

    image = get(recycle(conn), "/newsletter/#{slug}/images/leak.png")
    assert response(image, 404)
    refute response(image, 404) =~ secret

    named =
      get(recycle(conn), "/newsletter/2026-09-first-update/images/%2e%2e%2f%2e%2e%2fpasswd")

    assert response(named, 404)

    draft_page = get(recycle(conn), ~p"/newsletter/draft-not-published")
    assert response(draft_page, 404)
    refute response(draft_page, 404) =~ secret

    published = get(recycle(conn), ~p"/newsletter/2026-09-first-update")
    assert response(published, 200) =~ "Story mode, a new renderer, and finish hooks"
  end

  test "archive lists the first issue and exposes an email signup", %{conn: conn} do
    Application.put_env(:crit, :selfhosted, false)
    html = conn |> get(~p"/newsletter") |> html_response(200)
    assert html =~ "September 29, 2026"
    assert html =~ ~s(href="/newsletter/2026-09-first-update")
    assert html =~ ~s(action="/newsletter/subscribe")
  end

  test "malformed newsletter payloads return validation errors", %{conn: conn} do
    Application.put_env(:crit, :selfhosted, false)

    for attrs <- [nil, "not-a-map", ["not-a-map"], 12] do
      assert conn
             |> recycle()
             |> post(~p"/newsletter/subscribe", %{"newsletter" => attrs})
             |> html_response(422)
    end

    refute_receive {:email, _}
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

  test "a filled honeypot looks like success but sends nothing", %{conn: conn} do
    Application.put_env(:crit, :selfhosted, false)

    assert conn
           |> post(~p"/newsletter/subscribe",
             newsletter: %{email: "victim@example.com", homepage: "http://spam.example"}
           )
           |> html_response(200) =~ "Check your inbox"

    refute_receive {:email, _}

    assert Crit.Repo.get_by(Crit.Accounts.MarketingConsentEvent, email: "victim@example.com") ==
             nil
  end

  describe "with Turnstile enabled" do
    setup do
      original = Application.get_env(:crit, Crit.Turnstile)

      Application.put_env(:crit, Crit.Turnstile,
        site_key: "site-key",
        secret_key: "secret",
        req_options: [plug: {Req.Test, Crit.Turnstile}]
      )

      on_exit(fn -> Application.put_env(:crit, Crit.Turnstile, original || []) end)
      Application.put_env(:crit, :selfhosted, false)
      :ok
    end

    test "forms carry the site key and the CSP allows Cloudflare", %{conn: conn} do
      conn = get(conn, ~p"/newsletter")
      html = html_response(conn, 200)
      assert html =~ ~s(data-turnstile-sitekey="site-key")
      assert html =~ "data-turnstile-slot"
      [csp] = get_resp_header(conn, "content-security-policy")
      assert csp =~ ~r/script-src [^;]*https:\/\/challenges\.cloudflare\.com/
      assert csp =~ ~r/frame-src [^;]*https:\/\/challenges\.cloudflare\.com/
    end

    test "a signup without a token sends nothing", %{conn: conn} do
      assert conn
             |> post(~p"/newsletter/subscribe", newsletter: %{email: "victim@example.com"})
             |> html_response(422) =~ "couldn&#39;t check that you&#39;re human"

      refute_receive {:email, _}
    end

    test "a rejected token sends nothing", %{conn: conn} do
      Req.Test.stub(
        Crit.Turnstile,
        &Req.Test.json(&1, %{"success" => false, "error-codes" => []})
      )

      assert conn
             |> post(~p"/newsletter/subscribe", %{
               "newsletter" => %{"email" => "victim@example.com"},
               "cf-turnstile-response" => "bad"
             })
             |> html_response(422)

      refute_receive {:email, _}
    end

    test "a valid token sends the confirmation email", %{conn: conn} do
      Req.Test.stub(Crit.Turnstile, &Req.Test.json(&1, %{"success" => true}))

      assert conn
             |> post(~p"/newsletter/subscribe", %{
               "newsletter" => %{"email" => "reader@example.com"},
               "cf-turnstile-response" => "good"
             })
             |> html_response(200) =~ "Check your inbox"

      assert_receive {:email, _}
    end
  end

  test "Turnstile stays off without keys", %{conn: conn} do
    Application.put_env(:crit, :selfhosted, false)
    conn = get(conn, ~p"/newsletter")
    refute html_response(conn, 200) =~ "data-turnstile"
    [csp] = get_resp_header(conn, "content-security-policy")
    refute csp =~ "challenges.cloudflare.com"
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

  defp relative_escape(from, to) do
    {from_rest, to_rest} =
      drop_common(Path.split(Path.expand(from)), Path.split(Path.expand(to)))

    Path.join(List.duplicate("..", length(from_rest)) ++ to_rest)
  end

  defp drop_common([same | from], [same | to]), do: drop_common(from, to)
  defp drop_common(from, to), do: {from, to}

  defp encode_slug(relative) do
    relative
    |> String.graphemes()
    |> Enum.map_join(fn
      "." -> "%2e"
      "/" -> "%2f"
      char -> URI.encode(char)
    end)
  end
end

defmodule CritWeb.NewsletterControllerTest.FailingMailer do
  use Swoosh.Adapter
  def deliver(_email, _config), do: {:error, :unavailable}
end
