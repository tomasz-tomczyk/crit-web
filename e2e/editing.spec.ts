import { test, expect } from "@playwright/test";
import {
  createReview,
  deleteReview,
  loadReview,
  waitForCommentCard,
  addCommentViaUI,
} from "./helpers";

test.describe("Comment Editing", () => {
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

  test("edit button opens editor with existing text", async ({ page }) => {
    await loadReview(page, token);
    await addCommentViaUI(page, "Original comment text");

    // Click Edit button on the comment card
    const card = page
      .locator(".comment-card")
      .filter({ hasText: "Original comment text" });
    const editBtn = card.locator('button[title="Edit"]');
    await editBtn.click();

    // Editor should open with existing text
    const textarea = page.locator(".comment-form textarea");
    await expect(textarea).toBeVisible({ timeout: 5_000 });
    await expect(textarea).toHaveValue("Original comment text");
  });

  test("editing a comment saves updated text", async ({ page }) => {
    await loadReview(page, token);
    await addCommentViaUI(page, "Before edit");

    // Click Edit
    const card = page
      .locator(".comment-card")
      .filter({ hasText: "Before edit" });
    await card.locator('button[title="Edit"]').click();

    // Clear and type new text
    const textarea = page.locator(".comment-form textarea");
    await expect(textarea).toBeVisible({ timeout: 5_000 });
    await textarea.clear();
    await textarea.fill("After edit");

    // Click Update button
    await page.locator(".comment-form .btn-primary").click();

    // The comment should show updated text
    await waitForCommentCard(page, "After edit");

    // Original text should be gone
    await expect(
      page.locator(".comment-card").filter({ hasText: "Before edit" })
    ).not.toBeVisible();
  });

  test("edited comment persists after page reload", async ({ page }) => {
    await loadReview(page, token);
    await addCommentViaUI(page, "Will be edited");

    // Edit the comment
    const card = page
      .locator(".comment-card")
      .filter({ hasText: "Will be edited" });
    await card.locator('button[title="Edit"]').click();

    const textarea = page.locator(".comment-form textarea");
    await expect(textarea).toBeVisible({ timeout: 5_000 });
    await textarea.clear();
    await textarea.fill("Persisted edit");
    await page.locator(".comment-form .btn-primary").click();

    await waitForCommentCard(page, "Persisted edit");

    // Reload and verify persistence
    await loadReview(page, token);
    await waitForCommentCard(page, "Persisted edit");
  });

  test("cancelling edit preserves original text", async ({ page }) => {
    await loadReview(page, token);
    await addCommentViaUI(page, "Do not change me");

    // Click Edit
    const card = page
      .locator(".comment-card")
      .filter({ hasText: "Do not change me" });
    await card.locator('button[title="Edit"]').click();

    const textarea = page.locator(".comment-form textarea");
    await expect(textarea).toBeVisible({ timeout: 5_000 });
    await textarea.clear();
    await textarea.fill("This should be discarded");

    // Click Cancel
    await page.locator(".comment-form .btn-sm:not(.btn-primary)").filter({ hasText: "Cancel" }).click();

    // Original text should still be visible
    await waitForCommentCard(page, "Do not change me");
  });

  test("Ctrl+Enter submits edit", async ({ page }) => {
    await loadReview(page, token);
    await addCommentViaUI(page, "Edit with shortcut");

    const card = page
      .locator(".comment-card")
      .filter({ hasText: "Edit with shortcut" });
    await card.locator('button[title="Edit"]').click();

    const textarea = page.locator(".comment-form textarea");
    await expect(textarea).toBeVisible({ timeout: 5_000 });
    await textarea.clear();
    await textarea.fill("Updated via Ctrl+Enter");
    await textarea.press("Control+Enter");

    await waitForCommentCard(page, "Updated via Ctrl+Enter");
  });

  test("edit form header shows 'Editing comment' text", async ({ page }) => {
    await loadReview(page, token);
    await addCommentViaUI(page, "Check header");

    const card = page
      .locator(".comment-card")
      .filter({ hasText: "Check header" });
    await card.locator('button[title="Edit"]').click();

    const header = page.locator(".comment-form-header");
    await expect(header).toBeVisible({ timeout: 5_000 });
    await expect(header).toContainText("Editing comment");
  });
});
