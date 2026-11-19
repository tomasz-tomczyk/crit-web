defmodule CritWeb.E2E.CodeFontTest do
  use CritWeb.E2ECase, async: true

  describe "Code font setting" do
    setup %{page: page, request: request} do
      review =
        create_review(request,
          files: [%{path: "example.go", content: "package main\n\nfunc main() {}\n"}]
        )

      on_exit(fn -> delete_review(request, review.delete_token) end)
      load_review(page, review.token)
      %{token: review.token, delete_token: review.delete_token}
    end

    test "applies the system preset to code only and persists it", %{page: page} do
      code_font = fn ->
        Page.evaluate!(page, """
        () => getComputedStyle(document.documentElement).getPropertyValue("--crit-font-code").trim()
        """)
      end

      ui_font = fn ->
        Page.evaluate!(page, """
        () => getComputedStyle(document.documentElement).getPropertyValue("--crit-font-mono").trim()
        """)
      end

      original_ui_font = ui_font.()

      Locator.click!(Page.locator(page, "#settingsToggle"))
      Locator.select_option!(Page.locator(page, "#codeFontSelect"), "system")

      Expect.poll!(
        code_font,
        &assert(&1 == "ui-monospace, SFMono-Regular, Menlo, Consolas, monospace")
      )

      assert ui_font.() == original_ui_font

      consumer_fonts =
        Page.evaluate!(page, """
        () => {
          const probe = document.createElement("div");
          probe.innerHTML = '<div class="line-content code-line">code</div>'
            + '<div class="suggestion-diff">suggestion</div>'
            + '<div class="comment-body"><code>comment code</code></div>';
          document.body.appendChild(probe);
          return Array.from(probe.querySelectorAll(".code-line, .suggestion-diff, .comment-body code"))
            .map(element => getComputedStyle(element).fontFamily);
        }
        """)

      assert length(consumer_fonts) == 3
      Enum.each(consumer_fonts, &assert(&1 =~ "ui-monospace"))
      # Code files (Pierre, shadow DOM) use the same font through --diffs-font-family.
      Expect.poll!(
        fn ->
          page
          |> Page.locator(~s(.crit-code-file [data-content] > [data-line="1"]))
          |> Locator.evaluate!("el => getComputedStyle(el).fontFamily")
        end,
        &assert(&1 =~ "ui-monospace")
      )

      Page.reload!(page)

      Expect.poll!(
        code_font,
        &assert(&1 == "ui-monospace, SFMono-Regular, Menlo, Consolas, monospace")
      )
    end

    test "supports custom stacks and rejects declaration escapes", %{page: page} do
      Locator.click!(Page.locator(page, "#settingsToggle"))
      Locator.select_option!(Page.locator(page, "#codeFontSelect"), "custom")
      input = Page.locator(page, "#codeFontCustomInput")

      Locator.fill!(input, "'Comic Mono', monospace")
      Locator.blur!(input)

      Expect.poll!(
        fn ->
          Page.evaluate!(page, """
          () => getComputedStyle(document.documentElement).getPropertyValue("--crit-font-code").trim()
          """)
        end,
        &assert(&1 == "'Comic Mono', monospace")
      )

      Locator.fill!(input, "monospace; background: red")
      Locator.blur!(input)
      Expect.to_have_attribute!(input, "aria-invalid", "true")
      Expect.to_contain_text!(Page.locator(page, ".mini-toast--error"), "valid font-family")
    end
  end
end
