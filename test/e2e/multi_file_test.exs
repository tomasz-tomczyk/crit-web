defmodule CritWeb.E2E.MultiFileTest do
  use CritWeb.E2ECase, async: true

  describe "Multi-File Review" do
    setup %{request: request} do
      review = create_multi_file_review(request)
      on_exit(fn -> delete_review(request, review.delete_token) end)
      %{token: review.token, delete_token: review.delete_token}
    end

    test "renders the file tree and matching file sections", %{page: page, token: token} do
      load_review(page, token)

      file_tree_panel = Page.locator(page, "#fileTreePanel")
      Expect.to_be_visible!(file_tree_panel, timeout: 10_000)

      Expect.to_have_count!(Page.locator(page, ".tree-file"), 3)
      Expect.to_have_count!(Page.locator(page, "details.file-section"), 3)

      for file_name <- ["main.ts", "utils.ts", "README.md"] do
        Expect.to_be_visible!(Page.locator(page, ".tree-file-name", has_text: file_name))
        Expect.to_be_visible!(Page.locator(page, ".file-header-name", has_text: file_name))
      end
    end

    test "centers the review conversation at reading width with mobile gutters",
         %{page: page, token: token} do
      load_review(page, token)

      conversation = Page.locator(page, "#reviewConversation")
      Expect.to_be_visible!(conversation)

      desktop =
        Locator.evaluate!(conversation, """
        (element) => {
          const rect = element.getBoundingClientRect();
          const parent = element.parentElement.getBoundingClientRect();
          return { x: rect.x, width: rect.width, parentX: parent.x, parentWidth: parent.width };
        }
        """)

      assert desktop["width"] <= 1040

      assert abs(
               desktop["x"] - desktop["parentX"] -
                 (desktop["parentWidth"] - desktop["width"]) / 2
             ) < 2

      Page.set_viewport_size!(page, %{width: 390, height: 844})
      mobile = Locator.bounding_box!(conversation)
      refute is_nil(mobile)
      assert mobile.x >= 16
      assert 390 - mobile.x - mobile.width >= 16
      assert Page.evaluate!(page, "() => document.documentElement.scrollWidth") <= 390
    end

    test "clicking a file in the tree expands and scrolls to it", %{page: page, token: token} do
      load_review(page, token)

      utils_section =
        Page.locator(page, ~s[details.file-section:has(.file-header-name:has-text("utils.ts"))])

      Locator.click!(Locator.locator(utils_section, "summary.file-header"))
      Expect.not_to_have_attribute!(utils_section, "open", "")
      utils_header = Locator.locator(utils_section, "summary.file-header")

      # Playwright scrolls elements into view before clicking them, so reset the
      # page and prove the tree click itself moves this off-screen target.
      Page.evaluate!(page, "() => window.scrollTo(0, 0)")

      Expect.poll!(
        fn ->
          Locator.evaluate!(
            utils_header,
            "(header) => header.getBoundingClientRect().top > window.innerHeight"
          )
        end,
        &assert(&1 == true)
      )

      Locator.click!(Page.locator(page, ~s(.tree-file[data-path="src/utils.ts"])))

      Expect.to_have_attribute!(utils_section, "open", "")
      Expect.poll!(fn -> Page.evaluate!(page, "() => window.scrollY") end, &assert(&1 > 0))
      Expect.to_be_in_viewport!(utils_header)

      Expect.poll!(
        fn ->
          Locator.evaluate!(utils_header, """
          (header) => {
            const { top } = header.getBoundingClientRect();
            return top >= 0 && top < 200;
          }
          """)
        end,
        &assert(&1 == true)
      )
    end

    test "can add comments to different files", %{page: page, request: request, token: token} do
      # Seed comments on different files
      seed_comment(request, token,
        body: "Fix the main function",
        start_line: 1,
        file: "src/main.ts"
      )

      seed_comment(request, token, body: "Update the readme", start_line: 1, file: "README.md")

      load_review(page, token)

      # Both comments should be visible
      Expect.to_be_visible!(
        Locator.filter(Page.locator(page, ".comment-card"), has_text: "Fix the main function"),
        timeout: 10_000
      )

      Expect.to_be_visible!(
        Locator.filter(Page.locator(page, ".comment-card"), has_text: "Update the readme"),
        timeout: 10_000
      )

      # Total comment count should be 2
      Expect.to_have_text!(Page.locator(page, "#commentCountNumber"), "2")
    end

    test "creates file- and review-level comments via the UI", %{page: page, token: token} do
      load_review(page, token)

      review_conversation = Page.locator(page, "#reviewConversation")
      Locator.click!(Locator.get_by_role(review_conversation, :button, name: "Add comment"))
      review_textarea = Locator.locator(review_conversation, ".comment-form textarea")
      Locator.fill!(review_textarea, "Review-wide feedback")
      Locator.press!(review_textarea, "Control+Enter")

      Expect.to_be_visible!(
        Locator.locator(review_conversation, ".comment-card", has_text: "Review-wide feedback")
      )

      main_section =
        Page.locator(page, ~s[details.file-section:has(.file-header-name:has-text("main.ts"))])

      # File sections can be collapsed by the renderer when the review loads.
      # Open this section explicitly before interacting with its form.
      # (JS: `if (!(await getAttribute("open")))`, so "" counts as not open too.)
      if Locator.get_attribute!(main_section, "open") in [nil, ""] do
        Locator.click!(Locator.locator(main_section, "summary"))
      end

      Locator.click!(Locator.get_by_title(main_section, "Add file comment"))
      # Rendering the form can recreate the details element from its persisted
      # collapsed state. Keep the target section open while the form is used.
      Locator.evaluate!(main_section, "(element) => { element.open = true; }")
      # renderCommentFormUI uses .comment-form (not .file-comment-form)
      file_textarea = Locator.locator(main_section, ".file-comments .comment-form textarea")
      Expect.to_be_visible!(file_textarea)
      Locator.fill!(file_textarea, "Main file feedback")
      Locator.press!(file_textarea, "Control+Enter")

      Expect.to_be_visible!(
        Locator.locator(main_section, ".file-comments .comment-card",
          has_text: "Main file feedback"
        )
      )

      Expect.to_have_text!(Page.locator(page, "#commentCountNumber"), "2")
    end
  end
end
