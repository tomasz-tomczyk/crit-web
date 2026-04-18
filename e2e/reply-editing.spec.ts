import { test, expect, type Page } from "@playwright/test";
import {
  createReview,
  deleteReview,
  loadReview,
  seedComment,
  waitForCommentCard,
} from "./helpers";

/**
 * Add a comment via the UI so it is owned by the current session identity.
 */
async function addCommentViaUI(page: Page, body: string) {
  const gutter = page.locator(".line-gutter").first();
  await gutter.click();

  const textarea = page.locator(".comment-form textarea");
  await expect(textarea).toBeVisible({ timeout: 5_000 });
  await textarea.fill(body);
  await textarea.press("Control+Enter");

  await waitForCommentCard(page, body);
}

/**
 * Add a reply to the first comment card via the UI.
 */
async function addReplyViaUI(page: Page, commentBody: string, replyBody: string) {
  const card = page.locator(".comment-card").filter({ hasText: commentBody });
  await card.locator(".reply-input").click();

  const replyTextarea = card.locator(".reply-textarea");
  await expect(replyTextarea).toBeVisible({ timeout: 5_000 });
  await replyTextarea.fill(replyBody);

  await card.locator(".reply-form-buttons .btn-primary").click();

  // Wait for the reply to appear
  await expect(card.locator(".reply-body").filter({ hasText: replyBody })).toBeVisible({
    timeout: 5_000,
  });
}

test.describe("Reply Editing", () => {
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

  test("edit button on reply opens editor with existing text", async ({ page }) => {
    await loadReview(page, token);
    await addCommentViaUI(page, "Parent comment");
    await addReplyViaUI(page, "Parent comment", "Reply to edit");

    const card = page.locator(".comment-card").filter({ hasText: "Parent comment" });
    const reply = card.locator(".comment-reply");

    // Click Edit button on the reply
    await reply.locator('button[title="Edit"]').click();

    // The editReply function replaces .reply-body with a textarea inside .comment-reply
    const textarea = reply.locator("textarea.comment-textarea");
    await expect(textarea).toBeVisible({ timeout: 5_000 });
    await expect(textarea).toHaveValue("Reply to edit");
  });

  test("editing a reply saves updated text", async ({ page }) => {
    await loadReview(page, token);
    await addCommentViaUI(page, "Parent for edit test");
    await addReplyViaUI(page, "Parent for edit test", "Original reply");

    const card = page.locator(".comment-card").filter({ hasText: "Parent for edit test" });
    const reply = card.locator(".comment-reply");

    // Click Edit
    await reply.locator('button[title="Edit"]').click();

    const textarea = reply.locator("textarea.comment-textarea");
    await expect(textarea).toBeVisible({ timeout: 5_000 });
    await textarea.clear();
    await textarea.fill("Updated reply text");

    // Click Save
    await reply.locator(".reply-edit-actions .btn-primary").click();

    // Reload the page to confirm persistence (the reply_updated event saves to DB)
    await loadReview(page, token);
    await waitForCommentCard(page, "Parent for edit test");

    // The reply should show updated text after reload
    const reloadedCard = page.locator(".comment-card").filter({ hasText: "Parent for edit test" });
    await expect(
      reloadedCard.locator(".reply-body").filter({ hasText: "Updated reply text" })
    ).toBeVisible({ timeout: 5_000 });
  });

  test("cancelling reply edit preserves original text", async ({ page }) => {
    await loadReview(page, token);
    await addCommentViaUI(page, "Parent for cancel test");
    await addReplyViaUI(page, "Parent for cancel test", "Keep this reply");

    const card = page.locator(".comment-card").filter({ hasText: "Parent for cancel test" });
    const reply = card.locator(".comment-reply");

    // Click Edit
    await reply.locator('button[title="Edit"]').click();

    const textarea = reply.locator("textarea.comment-textarea");
    await expect(textarea).toBeVisible({ timeout: 5_000 });
    await textarea.clear();
    await textarea.fill("This should be discarded");

    // Click Cancel (the non-primary button in reply-edit-actions)
    await reply.locator(".reply-edit-actions .btn:not(.btn-primary)").click();

    // Original text should still be visible after re-render
    await expect(
      card.locator(".reply-body").filter({ hasText: "Keep this reply" })
    ).toBeVisible({ timeout: 5_000 });
  });

  test("Ctrl+Enter submits reply edit", async ({ page }) => {
    await loadReview(page, token);
    await addCommentViaUI(page, "Parent for Ctrl+Enter");
    await addReplyViaUI(page, "Parent for Ctrl+Enter", "Edit me with shortcut");

    const card = page.locator(".comment-card").filter({ hasText: "Parent for Ctrl+Enter" });
    const reply = card.locator(".comment-reply");

    await reply.locator('button[title="Edit"]').click();

    const textarea = reply.locator("textarea.comment-textarea");
    await expect(textarea).toBeVisible({ timeout: 5_000 });
    await textarea.clear();
    await textarea.fill("Shortcut edited reply");
    await textarea.press("Control+Enter");

    // Reload to confirm persistence
    await loadReview(page, token);
    await waitForCommentCard(page, "Parent for Ctrl+Enter");

    const reloadedCard = page.locator(".comment-card").filter({ hasText: "Parent for Ctrl+Enter" });
    await expect(
      reloadedCard.locator(".reply-body").filter({ hasText: "Shortcut edited reply" })
    ).toBeVisible({ timeout: 5_000 });
  });
});

test.describe("Reply Deletion", () => {
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

  test("delete button removes a reply", async ({ page }) => {
    await loadReview(page, token);
    await addCommentViaUI(page, "Parent with reply to delete");
    await addReplyViaUI(page, "Parent with reply to delete", "Delete this reply");

    const card = page.locator(".comment-card").filter({ hasText: "Parent with reply to delete" });
    const reply = card.locator(".comment-reply").filter({ hasText: "Delete this reply" });

    // Click the delete button on the reply
    await reply.locator(".delete-btn").click();

    // The reply should disappear
    await expect(
      card.locator(".comment-reply").filter({ hasText: "Delete this reply" })
    ).not.toBeVisible({ timeout: 5_000 });

    // Parent comment should still be visible
    await waitForCommentCard(page, "Parent with reply to delete");
  });

  test("deleting one reply preserves other replies", async ({ page }) => {
    await loadReview(page, token);
    await addCommentViaUI(page, "Multi reply parent");
    await addReplyViaUI(page, "Multi reply parent", "Reply one");
    await addReplyViaUI(page, "Multi reply parent", "Reply two");

    const card = page.locator(".comment-card").filter({ hasText: "Multi reply parent" });

    // Verify both replies exist
    await expect(card.locator(".comment-reply")).toHaveCount(2);

    // Delete the first reply
    const firstReply = card.locator(".comment-reply").filter({ hasText: "Reply one" });
    await firstReply.locator(".delete-btn").click();

    // Only second reply should remain
    await expect(
      card.locator(".comment-reply").filter({ hasText: "Reply one" })
    ).not.toBeVisible({ timeout: 5_000 });
    await expect(
      card.locator(".reply-body").filter({ hasText: "Reply two" })
    ).toBeVisible();
  });
});
