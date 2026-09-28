import { test, expect } from "@playwright/test";
import { createReview, deleteReview, loadReview } from "./helpers";

test.describe("Mermaid fullscreen overlay", () => {
  let token: string;
  let deleteToken: string;

  test.beforeEach(async ({ request }) => {
    const review = await createReview(request, {
      files: [{ path: "plan.md", content: "# Plan\n\n```mermaid\ngraph TD; A-->B;\n```\n" }],
    });
    token = review.token;
    deleteToken = review.deleteToken;
  });

  test.afterEach(async ({ request }) => {
    await deleteReview(request, deleteToken);
  });

  test("opens from the expand button, closes on Escape and returns focus", async ({ page }) => {
    await loadReview(page, token);
    const block = page.locator(".line-content.mermaid-block").first();
    await expect(block.locator("svg").first()).toBeVisible({ timeout: 10_000 });

    const expand = block.locator(".mermaid-expand");
    await block.hover();
    await expand.click();

    const overlay = page.locator("#mermaidOverlay");
    await expect(overlay).toHaveClass(/\bactive\b/);
    await expect(overlay.locator("#mermaidOverlayCanvas svg")).toBeVisible();
    await expect(page.locator("#mermaidOverlayClose")).toBeFocused();

    await page.keyboard.press("Escape");
    await expect(overlay).not.toHaveClass(/\bactive\b/);
    await expect(overlay).toBeHidden();
    await expect(expand).toBeFocused();
  });
});
