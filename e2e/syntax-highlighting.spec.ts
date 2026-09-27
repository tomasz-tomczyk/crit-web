import { test, expect } from "@playwright/test";
import { addCommentViaUI, codeLine, createReview, deleteReview, loadReview } from "./helpers";

// One highlighter, as in crit: Shiki (crit's vendored @pierre/diffs build) for
// code files, fenced code in documents and fenced code in comments. Token
// spans carry --diffs-token-light / --diffs-token-dark; there is no hljs.

const DOC = [
  "# Plan",
  "",
  "```elixir",
  "defmodule Plan do",
  "  def run, do: :ok",
  "end",
  "```",
  "",
  "- Step",
  "  ```js",
  "  const x = 1",
  "  ```",
  "",
  "```not-a-language",
  "plain <text>",
  "```",
  "",
].join("\n");

test.describe("Syntax highlighting", () => {
  let token: string;
  let deleteToken: string;

  test.beforeEach(async ({ request, page }) => {
    const review = await createReview(request, {
      files: [
        { path: "plan.md", content: DOC },
        { path: "page.html.heex", content: '<div class="a">\n  <%= @name %>\n</div>\n' },
      ],
    });
    token = review.token;
    deleteToken = review.deleteToken;
    await loadReview(page, token);
  });

  test.afterEach(async ({ request }) => {
    await deleteReview(request, deleteToken);
  });

  test("fenced code in documents is highlighted per line on first paint", async ({ page }) => {
    const fence = page.locator('.line-block[data-file-path="plan.md"] code.crit-code').filter({ hasText: "defmodule Plan do" });
    await expect(fence.locator('span[style*="--diffs-token-dark"]').first()).toBeVisible();
    // Each fence line is its own commentable block.
    await expect(page.locator('.line-block[data-file-path="plan.md"][data-start-line="5"] code.crit-code')).toContainText("def run");
    await expect(page.locator(".hljs, [class^='hljs-']")).toHaveCount(0);
  });

  test("fences nested in lists are highlighted once mounted", async ({ page }) => {
    const nested = page.locator('.line-block[data-file-path="plan.md"] pre > code.language-js');
    await expect(nested).toHaveClass(/crit-code/);
    await expect(nested.locator('span[style*="--diffs-token"]').first()).toBeVisible();
  });

  test("unknown languages render as plain text", async ({ page }) => {
    const plain = page.locator('.line-block[data-file-path="plan.md"] code.crit-code').filter({ hasText: "plain <text>" });
    await expect(plain).toBeVisible();
    await expect(plain.locator("span[style]")).toHaveCount(0);
  });

  test("code files are highlighted by file name, HEEx as HTML", async ({ page }) => {
    await expect(codeLine(page, "page.html.heex", 1).locator('span[style*="--diffs-token"]').first()).toBeVisible();
  });

  test("the light theme uses the light token colour", async ({ page }) => {
    const span = page.locator('.line-block[data-file-path="plan.md"] code.crit-code span[style]').first();
    await expect(span).toBeVisible();
    const colours = async () => span.evaluate((el) => ({
      color: getComputedStyle(el).color,
      light: el.style.getPropertyValue("--diffs-token-light"),
      dark: el.style.getPropertyValue("--diffs-token-dark"),
    }));
    const toRgb = (hex: string) => {
      const n = parseInt(hex.replace("#", "").slice(0, 6), 16);
      return `rgb(${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255})`;
    };
    await page.evaluate(() => document.documentElement.setAttribute("data-theme", "dark"));
    let c = await colours();
    expect(c.color).toBe(toRgb(c.dark));
    await page.evaluate(() => document.documentElement.setAttribute("data-theme", "light"));
    c = await colours();
    expect(c.color).toBe(toRgb(c.light));
  });

  test("fenced code in comments is sanitised, then highlighted in place", async ({ page }) => {
    await addCommentViaUI(page, "See:\n```go\nfunc main() {}\n```", { waitText: "See:" });
    const code = page.locator(".comment-card .comment-body pre > code");
    await expect(code).toHaveAttribute("data-crit-code", "highlighted");
    await expect(code.locator('span[style*="--diffs-token"]').first()).toBeVisible();
  });
});
