import { test, expect } from "@playwright/test";
import {
  createReview,
  deleteReview,
  loadReview,
  waitForCommentCard,
  addCommentViaUI,
} from "./helpers";

test.describe("Multi-User PubSub Sync", () => {
  let token: string;
  let deleteToken: string;

  test.beforeEach(async ({ request }) => {
    const review = await createReview(request);
    token = review.token;
    deleteToken = review.deleteToken;
  });

  test.afterEach(async ({ request }) => {
    await deleteReview(request, deleteToken);
  });

  test("comment added on page 1 appears on page 2 via PubSub", async ({
    browser,
  }) => {
    // Open two separate browser contexts (simulates two users)
    const context1 = await browser.newContext();
    const context2 = await browser.newContext();

    const page1 = await context1.newPage();
    const page2 = await context2.newPage();

    try {
      // Load the same review on both pages
      await loadReview(page1, token);
      await loadReview(page2, token);

      // Add a comment on page 1
      await addCommentViaUI(page1, "Synced from page 1");

      // Page 2 should receive the comment via PubSub
      await waitForCommentCard(page2, "Synced from page 1");

      // Both pages should show count of 1
      await expect(page1.locator("#commentCountNumber")).toHaveText("1");
      await expect(page2.locator("#commentCountNumber")).toHaveText("1");
    } finally {
      await context1.close();
      await context2.close();
    }
  });

  test("reply added on page 1 appears on page 2 via PubSub", async ({
    browser,
  }) => {
    const context1 = await browser.newContext();
    const context2 = await browser.newContext();

    const page1 = await context1.newPage();
    const page2 = await context2.newPage();

    try {
      await loadReview(page1, token);
      await loadReview(page2, token);

      // Add a comment on page 1
      await addCommentViaUI(page1, "Comment for reply sync");

      // Wait for it to appear on page 2
      await waitForCommentCard(page2, "Comment for reply sync");

      // Add a reply on page 1
      const card1 = page1
        .locator(".comment-card")
        .filter({ hasText: "Comment for reply sync" });
      await card1.locator(".reply-input").click();
      const replyTextarea = card1.locator(".reply-textarea");
      await expect(replyTextarea).toBeVisible({ timeout: 5_000 });
      await replyTextarea.fill("Reply synced via PubSub");
      await card1.locator(".reply-form-buttons .btn-primary").click();

      // Wait for reply to appear on page 1
      await expect(
        card1.locator(".reply-body").filter({ hasText: "Reply synced via PubSub" })
      ).toBeVisible({ timeout: 5_000 });

      // Reply should also appear on page 2
      const card2 = page2
        .locator(".comment-card")
        .filter({ hasText: "Comment for reply sync" });
      await expect(
        card2.locator(".reply-body").filter({ hasText: "Reply synced via PubSub" })
      ).toBeVisible({ timeout: 10_000 });
    } finally {
      await context1.close();
      await context2.close();
    }
  });

  test("resolve on page 1 syncs to page 2 via PubSub", async ({ browser }) => {
    const context1 = await browser.newContext();
    const context2 = await browser.newContext();

    const page1 = await context1.newPage();
    const page2 = await context2.newPage();

    try {
      await loadReview(page1, token);
      await loadReview(page2, token);

      // Add a comment on page 1
      await addCommentViaUI(page1, "Resolve sync test");

      // Wait for it on page 2
      await waitForCommentCard(page2, "Resolve sync test");

      // Resolve on page 1
      const card1 = page1
        .locator(".comment-card")
        .filter({ hasText: "Resolve sync test" });
      await card1.locator(".resolve-btn").click();

      // Should show resolved state on page 1
      await expect(
        page1.locator(".comment-card.resolved-card")
      ).toBeVisible({ timeout: 5_000 });

      // Should also show resolved state on page 2
      await expect(
        page2.locator(".comment-card.resolved-card")
      ).toBeVisible({ timeout: 10_000 });
    } finally {
      await context1.close();
      await context2.close();
    }
  });
});
