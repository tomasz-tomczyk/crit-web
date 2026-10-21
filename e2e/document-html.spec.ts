import { test, expect } from "@playwright/test";
import { createReview, deleteReview, loadReview } from "./helpers";

// Raw HTML in a shared document must not run script on the review page.
const CONTENT = [
  "# Raw HTML",
  "",
  'before <img src=x onerror="window.__xss=1"> after',
  "",
  '<div onclick="window.__xss=1"><script>window.__xss=1</script>block</div>',
  "",
  'a <a href="javascript:window.__xss=1">bad</a> link',
  "",
  "<details><summary>More</summary>hidden</details>",
  "",
].join("\n");

test.describe("Document HTML sanitizing", () => {
  let token: string;
  let deleteToken: string;

  test.beforeEach(async ({ request }) => {
    const review = await createReview(request, {
      files: [{ path: "raw.md", content: CONTENT }],
    });
    token = review.token;
    deleteToken = review.deleteToken;
  });

  test.afterEach(async ({ request }) => {
    await deleteReview(request, deleteToken);
  });

  test("strips handlers, scripts and javascript: URLs and keeps plain HTML", async ({ page }) => {
    await loadReview(page, token);
    const doc = page.locator("#document-renderer");

    // The broken image still renders (then becomes a placeholder) but
    // without its handler. The CSP blocks inline handlers too; these checks
    // cover the markup itself.
    await expect(doc.locator(".img-placeholder")).toHaveText("[image]");
    await expect(doc.locator("[onerror], [onclick]")).toHaveCount(0);
    await expect(doc.getByText("block", { exact: true })).toBeVisible();
    await expect(doc.locator("script")).toHaveCount(0);
    await expect(doc.locator("a", { hasText: "bad" })).not.toHaveAttribute("href");
    await expect(doc.locator("details summary")).toHaveText("More");
    expect(await page.evaluate(() => (window as { __xss?: number }).__xss)).toBeUndefined();
  });
});
