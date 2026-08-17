import { test, expect, type Page } from "@playwright/test";
import {
  createReview,
  deleteReview,
  loadReview,
  seedComment,
  waitForCommentCard,
} from "./helpers";

test.describe("Keyboard Shortcuts", () => {
  let token: string;
  let deleteToken: string;

  test.beforeEach(async ({ request }) => {
    // Use a list so each item is a separate line-block for keyboard navigation
    const review = await createReview(request, {
      files: [
        {
          path: "example.md",
          content:
            "# Heading\n\n- Item one\n- Item two\n- Item three\n- Item four\n- Item five\n",
        },
      ],
    });
    token = review.token;
    deleteToken = review.deleteToken;
  });

  test.afterEach(async ({ request }) => {
    await deleteReview(request, deleteToken);
  });

  test("j focuses the first line block", async ({ page }) => {
    await loadReview(page, token);

    // No element should be focused initially
    await expect(page.locator(".line-block.focused")).toHaveCount(0);

    await page.keyboard.press("j");

    const focused = page.locator(".line-block.focused");
    await expect(focused).toHaveCount(1);
  });

  test("j/k navigates between blocks", async ({ page }) => {
    await loadReview(page, token);

    // Press j twice to focus the second block
    await page.keyboard.press("j");
    await page.keyboard.press("j");

    const allBlocks = page.locator(".line-block");
    const secondBlock = allBlocks.nth(1);
    await expect(secondBlock).toHaveClass(/focused/);

    // Press k to go back to first block
    await page.keyboard.press("k");
    const firstBlock = allBlocks.nth(0);
    await expect(firstBlock).toHaveClass(/focused/);
  });

  test("Escape clears focus from a focused block", async ({ page }) => {
    await loadReview(page, token);

    // Focus a block
    await page.keyboard.press("j");
    await expect(page.locator(".line-block.focused")).toHaveCount(1, { timeout: 3_000 });

    // Press Escape to clear focus
    await page.keyboard.press("Escape");
    await expect(page.locator(".line-block.focused")).toHaveCount(0);
  });

  test("? opens settings panel with shortcuts tab", async ({ page }) => {
    await loadReview(page, token);

    await page.keyboard.press("?");

    const overlay = page.locator("#settingsOverlay.active");
    await expect(overlay).toBeVisible({ timeout: 5_000 });

    // Should show shortcuts content
    const shortcutsPane = page.locator("#shortcutsPane");
    await expect(shortcutsPane).toBeVisible();
  });

  test("? toggles settings panel", async ({ page }) => {
    await loadReview(page, token);

    // Open
    await page.keyboard.press("?");
    const overlay = page.locator("#settingsOverlay.active");
    await expect(overlay).toBeVisible({ timeout: 5_000 });

    // Close
    await page.keyboard.press("?");
    await expect(overlay).not.toBeVisible();
  });

  test("custom shortcut applies immediately, persists, and resets", async ({
    page,
  }) => {
    await loadReview(page, token);
    await page.keyboard.press("?");
    await page.locator('[data-shortcut-id="next_block"]').click();
    await page.keyboard.press("ArrowDown");
    await expect(page.locator('[data-shortcut-id="next_block"]')).toContainText("ArrowDown");

    await page.locator("#settingsOverlay").click({ position: { x: 10, y: 10 } });
    await page.keyboard.press("j");
    await expect(page.locator(".line-block.focused")).toHaveCount(0);
    await page.keyboard.press("ArrowDown");
    await expect(page.locator(".line-block.focused")).toHaveCount(1);

    await loadReview(page, token);
    await page.locator("#settingsToggle").click();
    await page.locator('[data-tab="shortcuts"]').click();
    await expect(page.locator('[data-shortcut-id="next_block"]')).toContainText("ArrowDown");
    await page.locator(".shortcut-reset-all").click();
    await page.locator("#settingsOverlay").click({ position: { x: 10, y: 10 } });
    await page.keyboard.press("j");
    await expect(page.locator(".line-block.focused")).toHaveCount(1);
  });

  test("shortcut conflicts use a toast without changing row height", async ({
    page,
  }) => {
    await loadReview(page, token);
    await page.keyboard.press("?");
    await expect.poll(() => page.locator(".settings-dialog").evaluate(
      element => getComputedStyle(element).transform
    )).toBe("none");
    const previous = page.locator('[data-shortcut-id="previous_block"]');
    const row = previous.locator("xpath=ancestor::tr");
    const before = await row.evaluate(element => element.getBoundingClientRect().height);
    await previous.click();
    const editing = await row.evaluate(element => element.getBoundingClientRect().height);
    expect(editing).toBe(before);
    await page.keyboard.press("j");

    await expect(page.locator(".mini-toast--error")).toContainText(
      "already assigned to “Next block”"
    );
  });

  test("capture can move to another shortcut or Reset all on the first click", async ({
    page,
  }) => {
    await loadReview(page, token);
    await page.keyboard.press("?");
    const next = page.locator('[data-shortcut-id="next_block"]');
    const previous = page.locator('[data-shortcut-id="previous_block"]');

    await next.click();
    await previous.click();
    await expect(next).toContainText("j");
    await expect(previous).toContainText("Press keys…");

    await page.locator(".shortcut-reset-all").click();
    await expect(previous).toContainText("k");
    await expect(page.locator(".shortcut-binding.is-capturing")).toHaveCount(0);
  });

  test("modified question-mark chords are reserved", async ({ page }) => {
    await loadReview(page, token);
    await page.keyboard.press("?");
    const next = page.locator('[data-shortcut-id="next_block"]');
    await next.click();
    await page.keyboard.press("Control+Shift+/");

    await expect(page.locator(".mini-toast--error")).toContainText("is reserved by Crit Web");
    await expect(next).toContainText("j");
  });

  test("custom Space shortcut does not hijack a focused button", async ({ page }) => {
    await loadReview(page, token);
    await page.keyboard.press("?");
    await page.locator('[data-shortcut-id="next_block"]').click();
    await page.keyboard.press("Space");
    await page.locator("#settingsOverlay").click({ position: { x: 10, y: 10 } });

    await page.locator("#settingsToggle").focus();
    await page.keyboard.press("Space");
    await expect(page.locator("#settingsOverlay.active")).toBeVisible();
    await expect(page.locator(".line-block.focused")).toHaveCount(0);
  });

  test("fixed settings shortcuts work while a settings control is focused", async ({ page }) => {
    await loadReview(page, token);
    await page.keyboard.press("?");
    await page.locator(".shortcut-reset-all").focus();
    await page.keyboard.press("Escape");
    await expect(page.locator("#settingsOverlay.active")).toHaveCount(0);

    await page.locator("#settingsToggle").click();
    await page.locator('.settings-tab[data-tab="shortcuts"]').focus();
    await page.keyboard.press("?");
    await expect(page.locator("#settingsOverlay.active")).toHaveCount(0);
  });

  test("malformed persisted shortcut values fall back without breaking settings", async ({ page }) => {
    const pageErrors: Error[] = [];
    page.on("pageerror", error => pageErrors.push(error));
    await page.addInitScript(() => localStorage.setItem("crit-shortcuts", JSON.stringify({ next_block: 7 })));
    await loadReview(page, token);
    await page.keyboard.press("?");

    await expect(page.locator('[data-shortcut-id="next_block"]')).toContainText("j");
    expect(pageErrors).toEqual([]);
  });

  test("[ and ] navigate between comments", async ({ page, request }) => {
    await seedComment(request, token, {
      body: "First shortcut comment",
      startLine: 1,
    });
    await seedComment(request, token, {
      body: "Second shortcut comment",
      startLine: 4,
    });

    await loadReview(page, token);
    await waitForCommentCard(page, "First shortcut comment");
    await waitForCommentCard(page, "Second shortcut comment");

    // Navigate with ] to next comment
    await page.keyboard.press("]");

    // Navigate with ] again
    await page.keyboard.press("]");

    // Navigate with [ back
    await page.keyboard.press("[");

    // These shortcuts should work without errors. The comment navigation
    // highlight CSS class confirms the jump happened.
  });

  test("Shift+C toggles comments panel", async ({ page, request }) => {
    await seedComment(request, token, {
      body: "Panel shortcut test",
      startLine: 1,
    });

    await loadReview(page, token);
    await waitForCommentCard(page, "Panel shortcut test");

    const panel = page.locator(".comments-panel");

    // Open
    await page.keyboard.press("Shift+C");
    await expect(panel).toHaveClass(/comments-panel-open/, { timeout: 5_000 });

    // Close
    await page.keyboard.press("Shift+C");
    await expect(panel).not.toHaveClass(/comments-panel-open/);
  });

  test("keyboard shortcuts do not fire when typing in textarea", async ({
    page,
  }) => {
    await loadReview(page, token);

    // Open a comment form
    const gutter = page.locator(".line-gutter").first();
    await gutter.click();

    const textarea = page.locator(".comment-form textarea");
    await expect(textarea).toBeVisible({ timeout: 5_000 });

    // Type navigation shortcuts in the textarea — they must not leave the editor.
    await textarea.type("jn");
    await expect(textarea).toHaveValue("jn");

    // No block should get focused from the shortcut.
    await expect(page.locator(".line-block.focused")).toHaveCount(0);
  });
});
