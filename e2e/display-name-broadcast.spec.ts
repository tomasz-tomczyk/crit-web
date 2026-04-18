import { test, expect, type Page } from "@playwright/test";
import {
  createReview,
  deleteReview,
  loadReview,
  waitForCommentCard,
} from "./helpers";

/**
 * Set a display name on the given page via the name pill.
 */
async function setDisplayName(page: Page, name: string) {
  const nameBtn = page.locator("#name-pill-btn");
  await expect(nameBtn).toBeVisible();
  await nameBtn.click();

  const nameInput = page.locator("#name-input");
  await expect(nameInput).toBeVisible();
  await nameInput.fill(name);

  await page.locator(".crit-name-save").click();

  // Wait for the name to appear in the button
  await expect(nameBtn).toContainText(name);
}

test.describe("Display Name Broadcast", () => {
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

  test("setting display name updates comment author badge on other tab", async ({
    browser,
  }) => {
    // Use two separate browser contexts to simulate two users
    const context1 = await browser.newContext();
    const context2 = await browser.newContext();

    const page1 = await context1.newPage();
    const page2 = await context2.newPage();

    try {
      await loadReview(page1, token);
      await loadReview(page2, token);

      // Page 1 sets a display name
      await setDisplayName(page1, "Alice");

      // Page 1 adds a comment (should have author badge "Alice")
      const gutter = page1.locator(".line-gutter").first();
      await gutter.click();
      const textarea = page1.locator(".comment-form textarea");
      await expect(textarea).toBeVisible({ timeout: 5_000 });
      await textarea.fill("Comment from Alice");
      await textarea.press("Control+Enter");
      await waitForCommentCard(page1, "Comment from Alice");

      // Page 2 should see the comment with author badge
      await waitForCommentCard(page2, "Comment from Alice");

      // The comment on page 2 should show the author name
      const card2 = page2
        .locator(".comment-card")
        .filter({ hasText: "Comment from Alice" });
      await expect(
        card2.locator(".comment-author-badge")
      ).toContainText("Alice", { timeout: 5_000 });
    } finally {
      await context1.close();
      await context2.close();
    }
  });

  test("display name set on page persists in the pill button", async ({
    page,
  }) => {
    await loadReview(page, token);

    await setDisplayName(page, "TestReviewer");

    // Verify it shows in the button
    await expect(page.locator("#name-pill-btn")).toContainText("TestReviewer");
  });
});
