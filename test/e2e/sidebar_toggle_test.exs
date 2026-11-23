defmodule CritWeb.E2E.SidebarToggleTest.Shared do
  @moduledoc false
  import Playwright.Test.Assertions
  import CritWeb.E2E.Helpers
  alias Playwright.{APIRequestContext, APIResponse, Page}

  def collapsed(page),
    do: Page.evaluate!(page, ~s|() => document.body.classList.contains("file-tree-collapsed")|)

  # Log in as the owner of a new multi-file review. The owner can change the
  # comment policy, which patches the header without re-rendering the document
  # (canComment stays true for the owner), so JS-owned header state has to
  # survive the patch on its own.
  def owner_review(request, page) do
    seed =
      APIRequestContext.post!(request, "#{base_url()}/api/test/seed-user",
        data: %{name: "Sidebar Owner"}
      )

    assert APIResponse.status(seed) == 200
    %{"user_id" => user_id, "token" => bearer} = APIResponse.json!(seed)

    res =
      APIRequestContext.post!(request, "#{base_url()}/api/reviews",
        headers: %{"Authorization" => "Bearer #{bearer}"},
        data: %{
          files: [
            %{path: "src/main.ts", content: "export const a = 1;\n"},
            %{path: "README.md", content: "# Project\n\nIntro.\n"}
          ],
          comments: []
        }
      )

    assert APIResponse.status(res) == 201
    %{"url" => url, "delete_token" => delete_token} = APIResponse.json!(res)
    [_, token] = String.split(url, "/r/")
    Page.goto!(page, "/test/login-as/#{user_id}")
    %{token: token, delete_token: delete_token}
  end
end

defmodule CritWeb.E2E.SidebarToggleTest do
  use CritWeb.E2ECase, async: true

  import CritWeb.E2E.SidebarToggleTest.Shared

  describe "File tree sidebar toggle" do
    setup %{request: request} do
      review = create_multi_file_review(request)
      on_exit(fn -> delete_review(request, review.delete_token) end)
      %{token: review.token, delete_token: review.delete_token}
    end

    test "click and `b` toggle the sidebar, and the state persists", %{page: page, token: token} do
      load_review(page, token)
      toggle = Page.locator(page, "#fileTreeToggle")
      Expect.to_be_visible!(toggle)
      Expect.to_have_attribute!(toggle, "aria-expanded", "true")
      assert collapsed(page) == false

      Locator.click!(toggle)
      Expect.poll!(fn -> collapsed(page) end, &assert(&1 == true))
      Expect.to_have_attribute!(toggle, "aria-expanded", "false")
      Expect.to_have_attribute!(toggle, "aria-label", "Show sidebar")
      Expect.to_have_attribute!(toggle, "title", "Show sidebar (b)")

      Keyboard.press!(Page.keyboard(page), "b")
      Expect.poll!(fn -> collapsed(page) end, &assert(&1 == false))
      Expect.to_have_attribute!(toggle, "aria-expanded", "true")

      Keyboard.press!(Page.keyboard(page), "b")
      Expect.poll!(fn -> collapsed(page) end, &assert(&1 == true))

      load_review(page, token)
      Expect.poll!(fn -> collapsed(page) end, &assert(&1 == true))
      Expect.to_have_attribute!(Page.locator(page, "#fileTreeToggle"), "aria-expanded", "false")
    end

    test "rebinding the shortcut updates the toggle's title", %{page: page, token: token} do
      load_review(page, token)
      Keyboard.press!(Page.keyboard(page), "?")
      Locator.click!(Page.locator(page, ~s([data-shortcut-id="toggle_file_tree"])))
      Keyboard.press!(Page.keyboard(page), "m")
      Expect.to_contain_text!(Page.locator(page, ~s([data-shortcut-id="toggle_file_tree"])), "m")

      Expect.to_have_attribute!(
        Page.locator(page, "#fileTreeToggle"),
        "title",
        "Hide sidebar (m)"
      )
    end
  end
end

# The tests outside the describe, which don't run its beforeEach.
defmodule CritWeb.E2E.SidebarToggleTest.TopLevel do
  use CritWeb.E2ECase, async: true

  import CritWeb.E2E.SidebarToggleTest.Shared

  test "JS-owned header state survives a LiveView patch", %{page: page, request: request} do
    %{token: token, delete_token: delete_token} = owner_review(request, page)
    seed_comment(request, token, file: "README.md")
    load_review(page, token)

    toggle = Page.locator(page, "#fileTreeToggle")
    viewed = Page.locator(page, "#viewedCount")
    count = Page.locator(page, "#commentCountNumber")
    Expect.to_be_visible!(toggle)
    Expect.to_contain_text!(viewed, "files viewed")
    Expect.to_have_text!(count, "1")
    Locator.click!(toggle)
    Expect.to_have_attribute!(toggle, "aria-expanded", "false")

    Locator.click!(Page.locator(page, "#comment-policy-menu-trigger"))
    Locator.click!(Page.locator(page, ~s([data-test="comment-policy-set-logged_in_only"])))
    Expect.to_contain_text!(Page.locator(page, "#comment-policy-menu-trigger"), "Login required")

    Expect.to_be_visible!(toggle)
    Expect.to_have_attribute!(toggle, "aria-expanded", "false")
    Expect.to_have_attribute!(toggle, "aria-label", "Show sidebar")
    Expect.to_have_attribute!(toggle, "title", "Show sidebar (b)")
    Expect.to_be_visible!(viewed)
    Expect.to_contain_text!(viewed, "files viewed")
    Expect.to_have_text!(count, "1")

    Expect.to_have_attribute!(
      Page.locator(page, "#comment-count"),
      "title",
      ~r/1 unresolved comment/
    )

    assert collapsed(page) == true

    delete_review(request, delete_token)
  end

  test "the sidebar toggle is hidden on single-file reviews", %{page: page, request: request} do
    %{token: token, delete_token: delete_token} = create_review(request)
    load_review(page, token)
    Expect.to_be_hidden!(Page.locator(page, "#fileTreeToggle"))
    # `b` is a no-op without the control.
    Keyboard.press!(Page.keyboard(page), "b")
    assert collapsed(page) == false
    delete_review(request, delete_token)
  end
end
