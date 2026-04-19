import { test, expect } from "@playwright/test";
import {
  createReview,
  deleteReview,
  loadReview,
  seedComment,
  waitForCommentCard,
  addCommentViaUI,
} from "./helpers";

test.describe("Comments Panel — Detail", () => {
  let token: string;
  let deleteToken: string;

  test.beforeEach(async ({ request }) => {
    const review = await createReview(request, {
      files: [
        {
          path: "example.md",
          content:
            "Line 1\nLine 2\nLine 3\nLine 4\nLine 5\nLine 6\nLine 7\nLine 8\nLine 9\nLine 10\n" +
            "Line 11\nLine 12\nLine 13\nLine 14\nLine 15\nLine 16\nLine 17\nLine 18\nLine 19\nLine 20\n",
        },
      ],
    });
    token = review.token;
    deleteToken = review.deleteToken;
  });

  test.afterEach(async ({ request }) => {
    await deleteReview(request, deleteToken);
  });

  test("panel shows all comments", async ({ page, request }) => {
    await seedComment(request, token, {
      body: "First panel comment",
      startLine: 1,
    });
    await seedComment(request, token, {
      body: "Second panel comment",
      startLine: 5,
    });

    await loadReview(page, token);
    await waitForCommentCard(page, "First panel comment");

    // Open panel
    await page.locator("#comment-count").click();
    const panel = page.locator(".comments-panel");
    await expect(panel).toBeVisible({ timeout: 5_000 });

    // Panel should contain both comments
    await expect(panel).toContainText("First panel comment");
    await expect(panel).toContainText("Second panel comment");
  });

  test("Shift+C toggles panel open and closed", async ({ page, request }) => {
    await seedComment(request, token, {
      body: "Toggle test",
      startLine: 1,
    });

    await loadReview(page, token);
    await waitForCommentCard(page, "Toggle test");

    const panel = page.locator(".comments-panel");

    // Open with Shift+C
    await page.keyboard.press("Shift+C");
    await expect(panel).toHaveClass(/comments-panel-open/, { timeout: 5_000 });

    // Close with Shift+C
    await page.keyboard.press("Shift+C");
    await expect(panel).not.toHaveClass(/comments-panel-open/);
  });

  test("close button hides panel", async ({ page, request }) => {
    await seedComment(request, token, {
      body: "Close button test",
      startLine: 1,
    });

    await loadReview(page, token);
    await waitForCommentCard(page, "Close button test");

    // Open panel
    await page.locator("#comment-count").click();
    const panel = page.locator(".comments-panel");
    await expect(panel).toHaveClass(/comments-panel-open/, { timeout: 5_000 });

    // Close via close button
    await panel.locator(".comments-panel-close").click();
    await expect(panel).not.toHaveClass(/comments-panel-open/);
  });

  test("clicking a comment in panel scrolls to inline comment", async ({
    page,
    request,
  }) => {
    // Seed a comment at the bottom of the document
    await seedComment(request, token, {
      body: "Bottom comment to scroll to",
      startLine: 18,
    });

    await loadReview(page, token);
    await waitForCommentCard(page, "Bottom comment to scroll to");

    // Open comments panel
    await page.locator("#comment-count").click();
    const panel = page.locator(".comments-panel");
    await expect(panel).toHaveClass(/comments-panel-open/, { timeout: 5_000 });

    // Click the comment in the panel
    const panelComment = panel.locator(".panel-comment-block").first();
    await panelComment.click();

    // The inline comment card should be visible in the viewport
    const inlineCard = page
      .locator("#document-renderer .comment-card")
      .filter({ hasText: "Bottom comment to scroll to" });
    await expect(inlineCard).toBeVisible({ timeout: 5_000 });
  });

  test("panel shows resolved comments after toggling 'Show resolved' filter", async ({
    page,
  }) => {
    await loadReview(page, token);
    await addCommentViaUI(page, "Will be resolved for panel");

    // Resolve the comment
    const card = page
      .locator(".comment-card")
      .filter({ hasText: "Will be resolved for panel" });
    await card.locator(".resolve-btn").click();
    await expect(
      page.locator(".comment-card.resolved-card")
    ).toBeVisible({ timeout: 5_000 });

    // Open panel via Shift+C
    await page.keyboard.press("Shift+C");
    const panel = page.locator(".comments-panel");
    await expect(panel).toHaveClass(/comments-panel-open/, { timeout: 5_000 });

    // The "Show resolved" toggle label should become visible now
    const filterLabel = panel.locator(".comments-panel-switch");
    await expect(filterLabel).toBeVisible({ timeout: 5_000 });

    // Click the label to toggle the checkbox (checkbox itself is visually hidden)
    await filterLabel.click();

    // Panel should now contain the resolved comment
    await expect(panel).toContainText("Will be resolved for panel", { timeout: 5_000 });
  });
});
