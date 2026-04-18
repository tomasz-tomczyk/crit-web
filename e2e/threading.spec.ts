import { test, expect } from "@playwright/test";
import {
  createReview,
  deleteReview,
  loadReview,
  seedComment,
  waitForCommentCard,
} from "./helpers";

test.describe("Comment Threading", () => {
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

  test("reply input is visible on a comment card", async ({
    page,
    request,
  }) => {
    await seedComment(request, token, {
      body: "Please fix this",
      startLine: 1,
    });

    await loadReview(page, token);
    await waitForCommentCard(page, "Please fix this");

    // The reply input should be visible on the comment card
    const card = page
      .locator(".comment-card")
      .filter({ hasText: "Please fix this" });
    const replyInput = card.locator(".reply-input");
    await expect(replyInput).toBeVisible();
  });

  test("can expand reply form and submit a reply", async ({
    page,
    request,
  }) => {
    await seedComment(request, token, {
      body: "Needs work",
      startLine: 1,
    });

    await loadReview(page, token);
    await waitForCommentCard(page, "Needs work");

    const card = page
      .locator(".comment-card")
      .filter({ hasText: "Needs work" });

    // Click the reply input to expand
    await card.locator(".reply-input").click();

    // The reply textarea should appear
    const replyTextarea = card.locator(".reply-textarea");
    await expect(replyTextarea).toBeVisible({ timeout: 5_000 });

    // Type a reply
    await replyTextarea.fill("Done, fixed it");

    // Click the submit button
    await card.locator(".reply-form-buttons .btn-primary").click();

    // The reply should appear
    await expect(card.locator(".comment-reply")).toBeVisible({
      timeout: 5_000,
    });
    await expect(card.locator(".reply-body")).toContainText("Done, fixed it");
  });

  test("reply form Cancel collapses without submitting", async ({
    page,
    request,
  }) => {
    await seedComment(request, token, {
      body: "Check this",
      startLine: 1,
    });

    await loadReview(page, token);
    await waitForCommentCard(page, "Check this");

    const card = page
      .locator(".comment-card")
      .filter({ hasText: "Check this" });

    // Expand the reply input
    await card.locator(".reply-input").click();
    const replyTextarea = card.locator(".reply-textarea");
    await expect(replyTextarea).toBeVisible({ timeout: 5_000 });
    await replyTextarea.fill("draft text");

    // Click Cancel
    await card
      .locator(".reply-form-buttons .btn:not(.btn-primary)")
      .click();

    // Should collapse back, no reply added
    await expect(card.locator(".reply-textarea")).not.toBeVisible();
    expect(await card.locator(".comment-reply").count()).toBe(0);
  });
});
