import { test, expect } from "@playwright/test";
import {
  createReview,
  deleteReview,
  loadReview,
  seedComment,
  waitForCommentCard,
} from "./helpers";

test.describe("Comments — Seed & Display", () => {
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

  test("displays a seeded comment on load", async ({ page, request }) => {
    // Seed a comment via the API before loading the page
    await seedComment(request, token, {
      body: "This needs revision",
      startLine: 1,
    });

    await loadReview(page, token);
    await waitForCommentCard(page, "This needs revision");

    // The comment count should show 1
    await expect(page.locator("#commentCountNumber")).toHaveText("1");
  });

  test("displays multiple comments", async ({ page, request }) => {
    await seedComment(request, token, {
      body: "First comment",
      startLine: 1,
    });
    await seedComment(request, token, {
      body: "Second comment",
      startLine: 3,
    });

    await loadReview(page, token);
    await waitForCommentCard(page, "First comment");
    await waitForCommentCard(page, "Second comment");

    await expect(page.locator("#commentCountNumber")).toHaveText("2");
  });
});

test.describe("Comments — Add via UI", () => {
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

  test("adds a comment by clicking the gutter and submitting", async ({
    page,
  }) => {
    await loadReview(page, token);

    // Click on the comment gutter of the first line to start selection,
    // then mouseup triggers comment form
    const firstGutter = page.locator(".line-gutter").first();
    await firstGutter.click();

    // The comment form should appear
    const commentForm = page.locator(".comment-form");
    await expect(commentForm).toBeVisible({ timeout: 5_000 });

    // Type into the textarea
    const textarea = commentForm.locator("textarea");
    await textarea.fill("New comment from E2E test");

    // Click Comment
    await commentForm.locator('button:has-text("Comment")').click();

    // The comment card should appear
    await waitForCommentCard(page, "New comment from E2E test");

    // Comment count should be 1
    await expect(page.locator("#commentCountNumber")).toHaveText("1");
  });

  test("adds a comment with Ctrl+Enter", async ({ page }) => {
    await loadReview(page, token);

    const firstGutter = page.locator(".line-gutter").first();
    await firstGutter.click();

    const textarea = page.locator(".comment-form textarea");
    await expect(textarea).toBeVisible({ timeout: 5_000 });
    await textarea.fill("Ctrl+Enter comment");

    // Submit with Ctrl+Enter
    await textarea.press("Control+Enter");

    await waitForCommentCard(page, "Ctrl+Enter comment");
  });

  test("opening a new comment form closes existing empty form", async ({ page }) => {
    await loadReview(page, token);

    // Open form on first line (leave empty)
    await page.locator(".line-gutter").first().click();
    await expect(page.locator(".comment-form")).toBeVisible({ timeout: 5_000 });

    // Open form on a different line without filling first
    await page.locator(".line-gutter").nth(2).click();

    // Only one form should remain (the new one); the empty first form was closed
    await expect(page.locator(".comment-form")).toHaveCount(1);
  });

  test("opening a new comment form keeps existing form with text", async ({ page }) => {
    await loadReview(page, token);

    await page.locator(".line-gutter").first().click();
    const firstTextarea = page.locator(".comment-form textarea");
    await expect(firstTextarea).toBeVisible({ timeout: 5_000 });
    await firstTextarea.fill("draft text");

    // Open form on a different line
    await page.locator(".line-gutter").nth(2).click();

    // Both forms should remain; first retains text
    await expect(page.locator(".comment-form")).toHaveCount(2);
    await expect(page.locator('.comment-form textarea').first()).toHaveValue("draft text");
  });

  test("Escape on empty comment form closes silently", async ({ page }) => {
    await loadReview(page, token);

    await page.locator(".line-gutter").first().click();
    const textarea = page.locator(".comment-form textarea");
    await expect(textarea).toBeVisible({ timeout: 5_000 });

    // No content -> no confirm dialog, form just closes
    await textarea.press("Escape");

    await expect(page.locator(".comment-form")).not.toBeVisible();
    expect(await page.locator(".comment-card").count()).toBe(0);
  });

  test("Escape on non-empty comment form prompts confirm; OK discards", async ({ page }) => {
    await loadReview(page, token);

    await page.locator(".line-gutter").first().click();
    const textarea = page.locator(".comment-form textarea");
    await expect(textarea).toBeVisible({ timeout: 5_000 });
    await textarea.fill("Detailed draft we don't want to lose by accident");

    // Accept the confirm dialog -> discard
    page.once("dialog", (dialog) => {
      expect(dialog.type()).toBe("confirm");
      expect(dialog.message()).toMatch(/discard/i);
      dialog.accept();
    });
    await textarea.press("Escape");

    await expect(page.locator(".comment-form")).not.toBeVisible();
    expect(await page.locator(".comment-card").count()).toBe(0);
  });

  test("Escape on non-empty comment form prompts confirm; Cancel keeps draft", async ({ page }) => {
    await loadReview(page, token);

    await page.locator(".line-gutter").first().click();
    const textarea = page.locator(".comment-form textarea");
    await expect(textarea).toBeVisible({ timeout: 5_000 });
    const draft = "Detailed draft we don't want to lose by accident";
    await textarea.fill(draft);

    // Dismiss the confirm dialog -> keep the form with content
    page.once("dialog", (dialog) => {
      expect(dialog.type()).toBe("confirm");
      dialog.dismiss();
    });
    await textarea.press("Escape");

    await expect(page.locator(".comment-form textarea")).toBeVisible();
    await expect(page.locator(".comment-form textarea")).toHaveValue(draft);
  });

  test("Cancel button on non-empty comment form discards immediately (no confirm)", async ({ page }) => {
    await loadReview(page, token);

    await page.locator(".line-gutter").first().click();
    const textarea = page.locator(".comment-form textarea");
    await expect(textarea).toBeVisible({ timeout: 5_000 });
    await textarea.fill("Important draft");

    // Cancel is an explicit, labeled discard — no confirm should appear.
    let dialogShown = false;
    page.on("dialog", (dialog) => {
      dialogShown = true;
      dialog.dismiss();
    });

    await page.locator(".comment-form").getByRole("button", { name: "Cancel" }).click();
    await expect(page.locator(".comment-form")).not.toBeVisible();
    expect(dialogShown).toBe(false);
  });
});

/**
 * Helper: add a comment via the UI (click gutter, type, submit).
 * This ensures the comment is owned by the current session identity,
 * so Resolve / Edit / Delete buttons are visible.
 */
async function addCommentViaUI(page: import("@playwright/test").Page, body: string) {
  const gutter = page.locator(".line-gutter").first();
  await gutter.click();

  const textarea = page.locator(".comment-form textarea");
  await expect(textarea).toBeVisible({ timeout: 5_000 });
  await textarea.fill(body);
  await textarea.press("Control+Enter");

  await waitForCommentCard(page, body);
}

test.describe("Comments — Resolve", () => {
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

  test("can resolve a comment", async ({ page }) => {
    await loadReview(page, token);

    // Add a comment via the UI so it is owned by this session
    await addCommentViaUI(page, "Resolve me");

    // Find the resolve button on the comment card
    const card = page.locator(".comment-card").filter({ hasText: "Resolve me" });
    const resolveBtn = card.locator(".resolve-btn");
    await resolveBtn.click();

    // After resolving, the comment card should have the resolved-card class
    await expect(
      page.locator(".comment-card.resolved-card")
    ).toBeVisible({ timeout: 5_000 });

    // The Unresolve button should be visible on the resolved card
    await expect(
      page.locator(".resolve-btn--active")
    ).toBeVisible();
  });
});

test.describe("Comments — Delete", () => {
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

  test("can delete a comment", async ({ page }) => {
    await loadReview(page, token);

    // Add a comment via the UI so it is owned by this session
    await addCommentViaUI(page, "Delete me");

    // Click the delete button on the comment card
    const card = page.locator(".comment-card").filter({ hasText: "Delete me" });
    const deleteBtn = card.locator(".delete-btn");
    await deleteBtn.click();

    // The comment should disappear
    await expect(
      page.locator(".comment-card").filter({ hasText: "Delete me" })
    ).not.toBeVisible({ timeout: 5_000 });
  });
});
