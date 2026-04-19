import { test, expect } from "@playwright/test";
import {
  createReview,
  deleteReview,
  loadReview,
  waitForCommentCard,
} from "./helpers";

test.describe("Draft Autosave", () => {
  let token: string;
  let deleteToken: string;

  test.beforeEach(async ({ page, request }) => {
    const review = await createReview(request);
    token = review.token;
    deleteToken = review.deleteToken;

    // Clear any existing drafts from localStorage before each test
    await page.goto("/");
    await page.evaluate(() => {
      const keys = Object.keys(localStorage).filter((k) =>
        k.startsWith("crit-draft-")
      );
      keys.forEach((k) => localStorage.removeItem(k));
    });
  });

  test.afterEach(async ({ request }) => {
    await deleteReview(request, deleteToken);
  });

  test("typing in comment form saves draft to localStorage", async ({
    page,
  }) => {
    await loadReview(page, token);

    const gutter = page.locator(".line-gutter").first();
    await gutter.click();

    const textarea = page.locator(".comment-form textarea");
    await expect(textarea).toBeVisible({ timeout: 5_000 });
    await textarea.fill("Draft comment text");

    // Poll for debounced save to localStorage (500ms debounce + buffer)
    await expect(async () => {
      const keys = await page.evaluate(() =>
        Object.keys(localStorage).filter((k) => k.startsWith("crit-draft-"))
      );
      expect(keys.length).toBeGreaterThan(0);
    }).toPass({ timeout: 3_000 });

    // Check localStorage content
    const draft = await page.evaluate(() => {
      const keys = Object.keys(localStorage).filter((k) =>
        k.startsWith("crit-draft-")
      );
      if (keys.length === 0) return null;
      return JSON.parse(localStorage.getItem(keys[0])!);
    });

    expect(draft).not.toBeNull();
    expect(draft.body).toBe("Draft comment text");
    expect(draft.savedAt).toBeGreaterThan(0);
  });

  test("draft is restored on page reload", async ({ page }) => {
    await loadReview(page, token);

    // Open comment form and type
    const gutter = page.locator(".line-gutter").first();
    await gutter.click();

    const textarea = page.locator(".comment-form textarea");
    await expect(textarea).toBeVisible({ timeout: 5_000 });
    await textarea.fill("Saved draft for reload");

    // Wait for debounced save
    await expect(async () => {
      const keys = await page.evaluate(() =>
        Object.keys(localStorage).filter((k) => k.startsWith("crit-draft-"))
      );
      expect(keys.length).toBeGreaterThan(0);
    }).toPass({ timeout: 3_000 });

    // Reload the page
    await loadReview(page, token);

    // The comment form should be restored with the draft text
    const restoredTextarea = page.locator(".comment-form textarea");
    await expect(restoredTextarea).toBeVisible({ timeout: 5_000 });
    await expect(restoredTextarea).toHaveValue("Saved draft for reload");
  });

  test("submitting comment clears the draft", async ({ page }) => {
    await loadReview(page, token);

    const gutter = page.locator(".line-gutter").first();
    await gutter.click();

    const textarea = page.locator(".comment-form textarea");
    await expect(textarea).toBeVisible({ timeout: 5_000 });
    await textarea.fill("Will be submitted");

    // Wait for draft to save
    await expect(async () => {
      const count = await page.evaluate(
        () =>
          Object.keys(localStorage).filter((k) => k.startsWith("crit-draft-"))
            .length
      );
      expect(count).toBe(1);
    }).toPass({ timeout: 3_000 });

    // Submit the comment
    await page.locator('.comment-form button:has-text("Submit")').click();
    await waitForCommentCard(page, "Will be submitted");

    // Draft should be cleared
    const draftCount = await page.evaluate(
      () =>
        Object.keys(localStorage).filter((k) => k.startsWith("crit-draft-"))
          .length
    );
    expect(draftCount).toBe(0);
  });

  test("cancelling comment form preserves the draft for later restoration", async ({ page }) => {
    await loadReview(page, token);

    const gutter = page.locator(".line-gutter").first();
    await gutter.click();

    const textarea = page.locator(".comment-form textarea");
    await expect(textarea).toBeVisible({ timeout: 5_000 });
    await textarea.fill("Will be cancelled but saved");

    // Wait for draft to save
    await expect(async () => {
      const count = await page.evaluate(
        () =>
          Object.keys(localStorage).filter((k) => k.startsWith("crit-draft-"))
            .length
      );
      expect(count).toBe(1);
    }).toPass({ timeout: 3_000 });

    // Cancel via Escape
    await textarea.press("Escape");
    await expect(page.locator(".comment-form")).not.toBeVisible();

    // Draft should still exist in localStorage (cancel preserves draft for restoration)
    const draftCount = await page.evaluate(
      () =>
        Object.keys(localStorage).filter((k) => k.startsWith("crit-draft-"))
          .length
    );
    expect(draftCount).toBe(1);

    // Reopen the form on the same line — draft should be restored
    await gutter.click();
    const restoredTextarea = page.locator(".comment-form textarea");
    await expect(restoredTextarea).toBeVisible({ timeout: 5_000 });
    await expect(restoredTextarea).toHaveValue("Will be cancelled but saved");
  });

  test("stale drafts older than 24 hours are discarded", async ({ page }) => {
    // Inject a stale draft before loading the page
    await page.addInitScript(
      (reviewToken) => {
        localStorage.setItem(
          `crit-draft-${reviewToken}-1-1`,
          JSON.stringify({
            body: "Old stale draft",
            savedAt: Date.now() - 25 * 60 * 60 * 1000, // 25 hours ago
            startLine: 1,
            endLine: 1,
            filePath: null,
          })
        );
      },
      token
    );

    await loadReview(page, token);

    // Comment form should NOT be open (stale draft discarded)
    // Give it a moment to ensure the renderer has finished restoring any drafts
    await page.waitForSelector("#document-renderer .line-block", {
      timeout: 15_000,
    });

    // The stale draft should have been removed
    const draftCount = await page.evaluate(
      () =>
        Object.keys(localStorage).filter((k) => k.startsWith("crit-draft-"))
          .length
    );
    expect(draftCount).toBe(0);
  });
});
