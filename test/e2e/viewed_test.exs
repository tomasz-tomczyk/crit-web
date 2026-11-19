defmodule CritWeb.E2E.ViewedTest do
  use CritWeb.E2ECase, async: true

  # test.beforeAll/afterAll: one review for the whole describe (setup_all
  # can't go inside a describe, and this module has only this one), made with a
  # request context of its own (the `request` fixture is per test).
  setup_all %{browser: browser} do
    request =
      APIRequest.new_context!(Playwright.request(Playwright.Test.BrowserPool.playwright(browser)))

    review = create_multi_file_review(request)
    on_exit(fn -> delete_review(request, review.delete_token) end)
    %{token: review.token, delete_token: review.delete_token}
  end

  describe "Viewed Checkbox — Multi-File Review" do
    setup %{page: page} do
      # Clear any persisted viewed state before each test
      Page.goto!(page, "/")

      Page.evaluate!(page, """
      () => {
        for (let i = localStorage.length - 1; i >= 0; i--) {
          const key = localStorage.key(i);
          if (key && key.startsWith("crit-viewed-")) localStorage.removeItem(key);
        }
      }
      """)

      :ok
    end

    test "each file section has a viewed checkbox, unchecked by default", %{
      page: page,
      token: token
    } do
      load_review(page, token)

      checkboxes = Page.locator(page, ~s(.file-header-viewed input[type="checkbox"]))
      sections = Page.locator(page, "details.file-section")
      Expect.to_have_count!(sections, 3)
      Expect.to_have_count!(checkboxes, 3)

      Expect.poll!(
        fn ->
          Locator.evaluate_all!(
            checkboxes,
            "(elements) => elements.map((element) => element.checked)"
          )
        end,
        &assert(&1 == [false, false, false])
      )
    end

    test "clicking viewed checkbox marks file as viewed and persists to localStorage", %{
      page: page,
      token: token
    } do
      load_review(page, token)

      main_section =
        Page.locator(page, ~s{details.file-section:has(.file-header-name:has-text("main.ts"))})

      checkbox = Locator.locator(main_section, ~s(.file-header-viewed input[type="checkbox"]))
      Locator.click!(checkbox)
      Expect.to_be_checked!(checkbox)

      # Verify the persisted value belongs to the file that was checked.
      Expect.poll!(
        fn ->
          Page.evaluate!(page, """
          () => {
            const keys = Object.keys(localStorage).filter((key) =>
              key.startsWith("crit-viewed-")
            );
            const key = keys[0];
            return keys.length === 1 && key
              ? JSON.parse(localStorage.getItem(key) || "{}")
              : null;
          }
          """)
        end,
        &assert(&1 == %{"src/main.ts" => true})
      )
    end

    test "checking viewed collapses the file section", %{page: page, token: token} do
      load_review(page, token)

      section = Locator.first(Page.locator(page, "details.file-section"))
      Expect.to_have_attribute!(section, "open", "")

      checkbox = Locator.locator(section, ~s(.file-header-viewed input[type="checkbox"]))
      Locator.click!(checkbox)

      Expect.not_to_have_attribute!(section, "open", "")
    end

    test "viewed state persists across page reload", %{page: page, token: token} do
      load_review(page, token)

      checkbox =
        Locator.first(Page.locator(page, ~s(.file-header-viewed input[type="checkbox"])))

      Locator.click!(checkbox)
      Expect.to_be_checked!(checkbox)

      # Reload the page — use goto directly since loadReview waits for
      # visible .line-block elements, but viewed files collapse their sections
      Page.goto!(page, "/r/#{token}")
      # Wait for the file sections to render
      Page.wait_for_selector!(page, "details.file-section", timeout: 15_000)

      # Checkbox should still be checked
      reloaded_checkbox =
        Locator.first(Page.locator(page, ~s(.file-header-viewed input[type="checkbox"])))

      Expect.to_be_checked!(reloaded_checkbox, timeout: 5_000)
    end

    test "viewed checkbox updates the tree indicator", %{page: page, token: token} do
      load_review(page, token)

      file_path = "src/main.ts"

      # No viewed indicator initially
      tree_file = Page.locator(page, ~s(.tree-file[data-path="#{file_path}"]))
      Expect.to_have_count!(Locator.locator(tree_file, ".tree-viewed-check"), 0)

      section =
        Page.locator(page, ~s{details.file-section:has(.file-header-name:has-text("main.ts"))})

      section
      |> Locator.locator(~s(.file-header-viewed input[type="checkbox"]))
      |> Locator.click!()

      # Tree file should have viewed class and checkmark
      Expect.to_have_class!(tree_file, ~r/viewed/)
      Expect.to_be_visible!(Locator.locator(tree_file, ".tree-viewed-check"))
    end
  end
end
