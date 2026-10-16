import { test, expect } from "@playwright/test";
import { createReview, deleteReview, loadReview } from "./helpers";

test.describe("Diagram fullscreen overlay", () => {
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
    const block = page.locator(".line-content.render-block").first();
    await expect(block.locator(".crit-render-output svg").first()).toBeVisible({ timeout: 10_000 });

    const expand = block.locator(".crit-render-expand");
    await expect(expand).toHaveAccessibleName(/diagram fullscreen/);
    await block.hover();
    await expand.click();

    const overlay = page.locator("#diagramOverlay");
    await expect(overlay).toHaveClass(/\bactive\b/);
    await expect(overlay.locator("#diagramOverlayCanvas svg")).toBeVisible();
    await expect(page.locator("#diagramOverlayClose")).toBeFocused();

    await page.keyboard.press("Escape");
    await expect(overlay).not.toHaveClass(/\bactive\b/);
    await expect(overlay).toBeHidden();
    await expect(expand).toBeFocused();
  });
});
