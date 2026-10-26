import { test, expect } from "@playwright/test";
import { createReview, deleteReview, loadReview } from "./helpers";

test("GitHub-style links jump to headings in shared documents", async ({ page, request }) => {
  const content = [
    "# Plan",
    "",
    "See [phase 2](#rollout--phase-2).",
    "",
    ...Array.from({ length: 50 }, (_, i) => `Paragraph ${i}: work to complete before rollout.\n`),
    "## Rollout — [Phase 2](https://example.com/phase-2)",
    "",
    "Per-tenant rate limits.",
  ].join("\n");
  const review = await createReview(request, {
    files: [{ path: "plan.md", content }],
  });

  try {
    await loadReview(page, review.token);
    const target = page.locator("#document-renderer h2#rollout--phase-2");
    await expect(target).toBeAttached();
    await expect(target).not.toBeInViewport();

    await page.locator('#document-renderer a[href="#rollout--phase-2"]', { hasText: "phase 2" }).click();
    await expect(page).toHaveURL(/#rollout--phase-2$/);
    await expect(target).toBeInViewport();
  } finally {
    await deleteReview(request, review.deleteToken);
  }
});

test("shared headings keep GitHub's spaces, underscores, and duplicate suffixes", async ({ page, request }) => {
  const review = await createReview(request, {
    files: [{
      path: "headings.md",
      content: [
        "## S7 — Data collection",
        "## Step 1 – Checkout",
        "## my_var settings",
        "## Shop 🚀 launch",
        "## See [shop-api](https://example.com)",
        "## S7 — Data collection",
      ].join("\n\n"),
    }],
  });

  try {
    await loadReview(page, review.token);
    for (const id of [
      "s7--data-collection",
      "step-1--checkout",
      "my_var-settings",
      "shop--launch",
      "see-shop-api",
      "s7--data-collection-1",
    ]) {
      await expect(page.locator(`#document-renderer h2[id="${id}"]`)).toHaveCount(1);
    }
  } finally {
    await deleteReview(request, review.deleteToken);
  }
});
