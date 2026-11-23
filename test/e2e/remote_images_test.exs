defmodule CritWeb.E2E.RemoteImagesTest do
  use CritWeb.E2ECase, async: true

  alias Playwright.{ConsoleMessage, Request, Route}

  # Remote images in a shared document or a comment must not load until the
  # reader clicks them: an agent could encode data in the URL. Only the hosts
  # in the CSP's img-src (CritWeb.Plugs.SecurityHeaders.remote_image_hosts)
  # load directly. Port of crit's remote-images.filemode.spec.ts.

  @remote_host "remote-images.test"
  @allowed_host "assets.crit.md"
  @md_image "![Status badge](https://#{@remote_host}/md.png?d=secret-md)"
  @raw_image ~s(<img src="https://#{@remote_host}/raw.png?d=secret-raw" alt="Raw image" width="40" height="20">)
  @allowed_image "![Allowed](https://#{@allowed_host}/e2e-allowed.png)"
  # 40x20 PNG.
  @png Base.decode64!(
         "iVBORw0KGgoAAAANSUhEUgAAACgAAAAUCAIAAABwJOjsAAAAGklEQVR42u3BAQ0AAADCoPdPbQ8HFAAAAMB3DxQAAQq3iQAAAAAASUVORK5CYII="
       )

  defp doc(extra), do: "# Remote images\n\nIntro line.\n\n#{extra}\n"

  # Requests to the remote host, and any CSP violation the page logs. The
  # listeners send each one to the test, which collects them with `recorded/2`
  # (`page.on(...)` pushing into the arrays).
  defp watch(page) do
    owner = self()
    ref = make_ref()

    Page.on(page, :request, fn req ->
      if URI.parse(Request.url(req)).host == @remote_host,
        do: send(owner, {ref, :remote_requests, Request.url(req)})
    end)

    Page.on(page, :console, fn msg ->
      if ConsoleMessage.text(msg) =~ ~r/Content Security Policy/i,
        do: send(owner, {ref, :csp_errors, ConsoleMessage.text(msg)})
    end)

    ref
  end

  defp recorded(ref, key) do
    receive do
      {^ref, ^key, value} -> [value | recorded(ref, key)]
    after
      0 -> []
    end
  end

  describe "Remote images — click to load" do
    # The spec's afterEach deletes the review the test stored in its
    # describe-level `deleteToken`; here each test registers that delete when it
    # creates the review.
    defp track(request, review),
      do: on_exit(fn -> delete_review(request, review.delete_token) end)

    test "document images become placeholders and fetch nothing", %{
      page: page,
      request: request
    } do
      review =
        create_review(request,
          files: [%{path: "plan.md", content: doc(@md_image <> "\n\n" <> @raw_image)}]
        )

      track(request, review)
      seen = watch(page)
      load_review(page, review.token)

      renderer = Page.locator(page, "#document-renderer")
      Expect.to_have_count!(Locator.locator(renderer, ".crit-remote-image"), 2)

      renderer
      |> Locator.get_by_role(:button,
        name: ~r/Load remote image "Status badge" from remote-images\.test/
      )
      |> Expect.to_be_visible!()

      Expect.to_have_count!(Locator.locator(renderer, ~s(img[src*="#{@remote_host}"])), 0)

      assert recorded(seen, :remote_requests) == []
      assert recorded(seen, :csp_errors) == []
    end

    test "clicking a placeholder loads the image in a sandboxed frame", %{
      page: page,
      request: request
    } do
      review = create_review(request, files: [%{path: "plan.md", content: doc(@md_image)}])
      track(request, review)
      seen = watch(page)

      Page.route!(page, "https://#{@remote_host}/**", fn route ->
        Route.fulfill!(route, content_type: "image/png", body: {:binary, @png})
      end)

      load_review(page, review.token)

      renderer = Page.locator(page, "#document-renderer")
      assert recorded(seen, :remote_requests) == []

      renderer
      |> Locator.get_by_role(:button, name: ~r/Load remote image "Status badge"/)
      |> Locator.click!()

      frame = Locator.locator(renderer, "iframe.crit-remote-image-frame")
      Expect.to_have_attribute!(frame, "sandbox", "allow-scripts")
      Expect.to_have_attribute!(frame, "referrerpolicy", "no-referrer")
      # The frame reports the image size and the page sizes the frame to it.
      Expect.poll!(
        fn ->
          Locator.evaluate!(frame, "(el) => Math.round(el.getBoundingClientRect().width)")
        end,
        &assert(&1 == 40)
      )

      Expect.poll!(
        fn ->
          Locator.evaluate!(frame, "(el) => Math.round(el.getBoundingClientRect().height)")
        end,
        &assert(&1 == 20)
      )

      assert recorded(seen, :remote_requests) == ["https://#{@remote_host}/md.png?d=secret-md"]
      # Clicking did not open a comment form on the line.
      Expect.to_have_count!(Page.locator(page, ".comment-form"), 0)
    end

    test "a failed load says so and links to the image", %{page: page, request: request} do
      review = create_review(request, files: [%{path: "plan.md", content: doc(@md_image)}])
      track(request, review)
      Page.route!(page, "https://#{@remote_host}/**", &Route.abort!/1)
      load_review(page, review.token)

      renderer = Page.locator(page, "#document-renderer")

      renderer
      |> Locator.get_by_role(:button, name: ~r/Load remote image "Status badge"/)
      |> Locator.click!()

      error = Locator.locator(renderer, ".crit-remote-image-error")
      Expect.to_contain_text!(error, "Couldn’t load image from #{@remote_host}")

      error
      |> Locator.get_by_role(:link, name: "Open in a new tab")
      |> Expect.to_have_attribute!("href", "https://#{@remote_host}/md.png?d=secret-md")
    end

    test "comment images become placeholders", %{page: page, request: request} do
      review =
        create_review(request,
          files: [%{path: "plan.md", content: doc("Plain text.")}],
          comments: [
            %{
              file: "plan.md",
              start_line: 3,
              end_line: 3,
              body:
                ~s|See ![Agent image](https://#{@remote_host}/comment.png?d=secret-comment) and <img src="https://#{@remote_host}/comment-raw.png">|
            }
          ]
        )

      track(request, review)
      seen = watch(page)
      load_review(page, review.token)

      body = Locator.first(Page.locator(page, ".comment-card .comment-body"))
      Expect.to_contain_text!(body, "See")
      Expect.to_have_count!(Locator.locator(body, ".crit-remote-image"), 2)
      Expect.to_have_count!(Locator.locator(body, ~s(img[src*="#{@remote_host}"])), 0)
      assert recorded(seen, :remote_requests) == []
      assert recorded(seen, :csp_errors) == []
    end

    test "allowlisted hosts load directly", %{page: page, request: request} do
      review = create_review(request, files: [%{path: "plan.md", content: doc(@allowed_image)}])
      track(request, review)

      Page.route!(page, "https://#{@allowed_host}/e2e-allowed.png", fn route ->
        Route.fulfill!(route, content_type: "image/png", body: {:binary, @png})
      end)

      load_review(page, review.token)

      renderer = Page.locator(page, "#document-renderer")

      Expect.to_have_count!(
        Locator.locator(renderer, ~s(img[src="https://#{@allowed_host}/e2e-allowed.png"])),
        1
      )

      Expect.to_have_count!(Locator.locator(renderer, ".crit-remote-image"), 0)
    end
  end
end
