import { test, expect, type Page } from "@playwright/test";
import { createReview, deleteReview, loadReview } from "./helpers";

/**
 * Open a comment form on the first line gutter.
 */
async function openCommentForm(page: Page) {
  const gutter = page.locator(".line-gutter").first();
  await gutter.click();
  await expect(page.locator(".comment-form")).toBeVisible({ timeout: 5_000 });
}

test.describe("Comment Templates", () => {
  let token: string;
  let deleteToken: string;

  test.beforeEach(async ({ page, request }) => {
    const review = await createReview(request);
    token = review.token;
    deleteToken = review.deleteToken;

    // Clear localStorage templates before each test
    await page.goto("/");
    await page.evaluate(() => {
      localStorage.removeItem("crit-templates");
    });
  });

  test.afterEach(async ({ request }) => {
    await deleteReview(request, deleteToken);
  });

  test("no template bar visible on fresh start", async ({ page }) => {
    await loadReview(page, token);
    await openCommentForm(page);

    const bar = page.locator(".comment-template-bar");
    await expect(bar).toBeHidden();
  });

  test("+ Template button visible in actions row", async ({ page }) => {
    await loadReview(page, token);
    await openCommentForm(page);

    const saveBtn = page.locator('.comment-form-actions button', {
      hasText: "+ Template",
    });
    await expect(saveBtn).toBeVisible();
  });

  test("+ Template opens dialog with textarea content", async ({ page }) => {
    await loadReview(page, token);
    await openCommentForm(page);

    const textarea = page.locator(".comment-form textarea");
    await textarea.fill("Consider using X instead");

    await page
      .locator('.comment-form-actions button', { hasText: "+ Template" })
      .click();

    const overlay = page.locator(".save-template-overlay");
    await expect(overlay).toBeVisible();
    const input = overlay.locator(".save-template-input");
    await expect(input).toHaveValue("Consider using X instead");
  });

  test("saving template makes chip appear in template bar", async ({
    page,
  }) => {
    await loadReview(page, token);
    await openCommentForm(page);

    const textarea = page.locator(".comment-form textarea");
    await textarea.fill("Needs a test for this");

    await page
      .locator('.comment-form-actions button', { hasText: "+ Template" })
      .click();

    const overlay = page.locator(".save-template-overlay");
    await overlay.locator('button', { hasText: "Save" }).click();
    await expect(overlay).toBeHidden();

    const bar = page.locator(".comment-template-bar");
    await expect(bar).toBeVisible();
    const chip = bar.locator(".template-chip");
    await expect(chip).toHaveCount(1);
    await expect(chip.locator(".template-chip-label")).toHaveText(
      "Needs a test for this"
    );
  });

  test("clicking chip inserts text into textarea", async ({ page }) => {
    await loadReview(page, token);
    await openCommentForm(page);

    const textarea = page.locator(".comment-form textarea");
    await textarea.fill("My template text");

    // Save a template
    await page
      .locator('.comment-form-actions button', { hasText: "+ Template" })
      .click();
    await page
      .locator('.save-template-overlay button', { hasText: "Save" })
      .click();

    // Clear textarea
    await textarea.fill("");

    // Click the chip
    const chip = page.locator(".template-chip").first();
    await chip.click();

    await expect(textarea).toHaveValue("My template text");
  });

  test("deleting chip via x removes it and hides bar when empty", async ({
    page,
  }) => {
    await loadReview(page, token);
    await openCommentForm(page);

    const textarea = page.locator(".comment-form textarea");
    await textarea.fill("Temp template");

    // Save a template
    await page
      .locator('.comment-form-actions button', { hasText: "+ Template" })
      .click();
    await page
      .locator('.save-template-overlay button', { hasText: "Save" })
      .click();

    const bar = page.locator(".comment-template-bar");
    await expect(bar).toBeVisible();

    // Click x to delete chip
    const chip = bar.locator(".template-chip").first();
    const del = chip.locator(".template-chip-delete");
    await expect(del).toBeVisible();
    await del.click();

    await expect(bar).toBeHidden();
  });

  test("templates persist across form close and reopen", async ({ page }) => {
    await loadReview(page, token);
    await openCommentForm(page);

    const textarea = page.locator(".comment-form textarea");
    await textarea.fill("Persistent template");

    // Save template
    await page
      .locator('.comment-form-actions button', { hasText: "+ Template" })
      .click();
    await page
      .locator('.save-template-overlay button', { hasText: "Save" })
      .click();

    // Cancel form
    await page
      .locator('.comment-form-actions button', { hasText: "Cancel" })
      .click();
    await expect(page.locator(".comment-form")).not.toBeVisible();

    // Reopen form
    await openCommentForm(page);

    // Template bar should still have the chip
    const bar = page.locator(".comment-template-bar");
    await expect(bar).toBeVisible();
    await expect(bar.locator(".template-chip")).toHaveCount(1);
    await expect(bar.locator(".template-chip-label").first()).toHaveText(
      "Persistent template"
    );
  });

  test("save dialog does nothing when textarea is empty", async ({ page }) => {
    await loadReview(page, token);
    await openCommentForm(page);

    // Textarea is empty by default
    await page
      .locator('.comment-form-actions button', { hasText: "+ Template" })
      .click();

    // Dialog should not appear
    const overlay = page.locator(".save-template-overlay");
    await expect(overlay).toBeHidden();
  });

  test("save dialog can be cancelled", async ({ page }) => {
    await loadReview(page, token);
    await openCommentForm(page);

    const textarea = page.locator(".comment-form textarea");
    await textarea.fill("Cancel me");

    await page
      .locator('.comment-form-actions button', { hasText: "+ Template" })
      .click();

    const overlay = page.locator(".save-template-overlay");
    await expect(overlay).toBeVisible();

    await overlay.locator('button', { hasText: "Cancel" }).click();
    await expect(overlay).toBeHidden();

    // No template bar should appear
    const bar = page.locator(".comment-template-bar");
    await expect(bar).toBeHidden();
  });
});
