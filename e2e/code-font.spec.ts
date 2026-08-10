import { test, expect } from "@playwright/test";
import { createReview, deleteReview, loadReview } from "./helpers";

test.describe("Code font setting", () => {
  let token: string;
  let deleteToken: string;

  test.beforeEach(async ({ page, request }) => {
    const review = await createReview(request, {
      files: [{ path: "example.go", content: "package main\n\nfunc main() {}\n" }],
    });
    token = review.token;
    deleteToken = review.deleteToken;
    await loadReview(page, token);
  });

  test.afterEach(async ({ request }) => {
    await deleteReview(request, deleteToken);
  });

  test("applies the system preset to code only and persists it", async ({ page }) => {
    const codeFont = () => page.evaluate(() =>
      getComputedStyle(document.documentElement).getPropertyValue("--crit-font-code").trim()
    );
    const uiFont = () => page.evaluate(() =>
      getComputedStyle(document.documentElement).getPropertyValue("--crit-font-mono").trim()
    );
    const originalUiFont = await uiFont();

    await page.locator("#settingsToggle").click();
    await page.locator("#codeFontSelect").selectOption("system");
    await expect.poll(codeFont).toBe("ui-monospace, SFMono-Regular, Menlo, Consolas, monospace");
    expect(await uiFont()).toBe(originalUiFont);
    const consumerFonts = await page.evaluate(() => {
      const probe = document.createElement("div");
      probe.innerHTML = '<div class="line-content code-line">code</div>'
        + '<div class="suggestion-diff">suggestion</div>'
        + '<div class="comment-body"><code>comment code</code></div>';
      document.body.appendChild(probe);
      return Array.from(probe.querySelectorAll(".code-line, .suggestion-diff, .comment-body code"))
        .map(element => getComputedStyle(element).fontFamily);
    });
    expect(consumerFonts).toHaveLength(3);
    consumerFonts.forEach(font => expect(font).toContain("ui-monospace"));

    await page.reload();
    await expect.poll(codeFont).toBe("ui-monospace, SFMono-Regular, Menlo, Consolas, monospace");
  });

  test("supports custom stacks and rejects declaration escapes", async ({ page }) => {
    await page.locator("#settingsToggle").click();
    await page.locator("#codeFontSelect").selectOption("custom");
    const input = page.locator("#codeFontCustomInput");

    await input.fill("'Comic Mono', monospace");
    await input.blur();
    await expect.poll(() => page.evaluate(() =>
      getComputedStyle(document.documentElement).getPropertyValue("--crit-font-code").trim()
    )).toBe("'Comic Mono', monospace");

    await input.fill("monospace; background: red");
    await input.blur();
    await expect(input).toHaveAttribute("aria-invalid", "true");
    await expect(page.locator(".mini-toast--error")).toContainText("valid font-family");
  });
});
