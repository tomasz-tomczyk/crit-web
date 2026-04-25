import { test, expect } from "@playwright/test";
import { createReview, deleteReview, loadReview } from "./helpers";

test.describe("Table of Contents", () => {
  let token: string;
  let deleteToken: string;

  test.afterEach(async ({ request }) => {
    if (deleteToken) await deleteReview(request, deleteToken);
  });

  test("toggle button is visible and panel opens when document has headings", async ({
    page,
    request,
  }) => {
    const review = await createReview(request, {
      files: [
        {
          path: "with-headings.md",
          content:
            "# Top Heading\n\nSome content.\n\n## Subsection\n\nMore content.\n",
        },
      ],
    });
    token = review.token;
    deleteToken = review.deleteToken;

    await page.setViewportSize({ width: 1400, height: 900 });
    await loadReview(page, token);

    const toggle = page.locator("#crit-toc-toggle");
    const panel = page.locator("#crit-toc");

    await expect(toggle).toBeVisible();
    await expect(panel.locator(".crit-toc-list a")).toHaveCount(2);
  });

  test("toggle button and panel are hidden when document has no headings", async ({
    page,
    request,
  }) => {
    const review = await createReview(request, {
      files: [
        {
          path: "no-headings.md",
          content:
            "Just a paragraph of text.\n\nAnother paragraph, no headings here.\n",
        },
      ],
    });
    token = review.token;
    deleteToken = review.deleteToken;

    // Wide viewport — default behavior would open TOC if not guarded
    await page.setViewportSize({ width: 1400, height: 900 });
    await loadReview(page, token);

    const toggle = page.locator("#crit-toc-toggle");
    const panel = page.locator("#crit-toc");

    await expect(toggle).toBeHidden();
    await expect(panel).toHaveClass(/crit-toc-hidden/);
  });

  test("panel stays hidden for empty TOC even when localStorage says open", async ({
    page,
    request,
  }) => {
    const review = await createReview(request, {
      files: [
        {
          path: "no-headings.md",
          content: "Just text. No headings at all in this file.\n",
        },
      ],
    });
    token = review.token;
    deleteToken = review.deleteToken;

    // Pre-seed localStorage with a previous "open" state
    await page.goto("/");
    await page.evaluate(() => localStorage.setItem("crit-toc", "open"));

    await page.setViewportSize({ width: 1400, height: 900 });
    await loadReview(page, token);

    const toggle = page.locator("#crit-toc-toggle");
    const panel = page.locator("#crit-toc");

    await expect(toggle).toBeHidden();
    await expect(panel).toHaveClass(/crit-toc-hidden/);
  });
});
