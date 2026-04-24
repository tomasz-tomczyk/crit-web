import { test, expect } from "@playwright/test";
import {
  createReview,
  deleteReview,
  loadReview,
  addCommentViaUI,
} from "./helpers";

/**
 * Helper: add a comment via UI and resolve it, returning a resolved comment
 * block in the document body.
 */
async function addAndResolveComment(
  page: import("@playwright/test").Page,
  body: string,
  opts: { lineIndex?: number } = {}
) {
  await addCommentViaUI(page, body, { lineIndex: opts.lineIndex ?? 0 });

  const card = page.locator(".comment-card").filter({ hasText: body });
  await card.locator(".resolve-btn").click();

  // Wait for the resolved-card class to appear (card DOM is replaced on resolve)
  await expect(
    page.locator(".comment-card.resolved-card")
  ).toBeVisible({ timeout: 5_000 });
}

/**
 * Helper: open the Settings panel and switch to the "settings" tab.
 */
async function openSettingsPane(page: import("@playwright/test").Page) {
  await page.locator("#settingsToggle").click();
  await expect(
    page.locator("#settingsOverlay.active")
  ).toBeVisible({ timeout: 5_000 });

  await page.locator('.settings-tab[data-tab="settings"]').click();
}

test.describe("Hide Resolved", () => {
  let token: string;
  let deleteToken: string;

  test.beforeEach(async ({ page, request }) => {
    const review = await createReview(request, {
      files: [
        {
          path: "example.md",
          content:
            "# Hello\n\nLine one\nLine two\nLine three\nLine four\n",
        },
      ],
    });
    token = review.token;
    deleteToken = review.deleteToken;

    // Clear hide-resolved preference before each test
    await page.goto("/");
    await page.evaluate(() => {
      localStorage.removeItem("crit-hide-resolved");
    });
  });

  test.afterEach(async ({ request }) => {
    await deleteReview(request, deleteToken);
  });

  test("settings panel has Hide resolved toggle in Display section", async ({
    page,
  }) => {
    await loadReview(page, token);
    await openSettingsPane(page);

    const toggle = page.locator("#hideResolvedToggle");
    await expect(toggle).toBeAttached();

    // Should be unchecked by default
    await expect(toggle).not.toBeChecked();

    // Verify the label is visible
    await expect(
      page.locator(".settings-display-label", { hasText: "Hide resolved" })
    ).toBeVisible();
  });

  test("toggle hides resolved inline comments", async ({ page }) => {
    await loadReview(page, token);

    // Add a comment and resolve it
    await addAndResolveComment(page, "This is resolved");

    // The resolved comment block should be visible by default
    const resolvedBlock = page
      .locator(".comment-block:not(.panel-comment-block)")
      .filter({ has: page.locator(".resolved-card") });
    await expect(resolvedBlock).toBeVisible();

    // Enable "Hide resolved" in settings (checkbox is visually hidden behind switch)
    await openSettingsPane(page);
    const hideRow = page.locator(".settings-display-row").filter({ hasText: "Hide resolved" });
    await hideRow.locator(".comments-panel-switch-track").click();

    // Close settings to see the document
    await page.keyboard.press("Escape");
    await expect(page.locator("#settingsOverlay.active")).not.toBeVisible();

    // The resolved comment block should now be hidden
    await expect(resolvedBlock).not.toBeVisible();
  });

  test("toggle does NOT affect the side panel", async ({ page }) => {
    await loadReview(page, token);

    // Add a comment and resolve it
    await addAndResolveComment(page, "Panel visible comment");

    // Enable "Hide resolved" via keyboard shortcut for speed
    await page.keyboard.press("h");

    // Resolved inline comment should be hidden
    const resolvedInlineBlock = page
      .locator(".comment-block:not(.panel-comment-block)")
      .filter({ has: page.locator(".resolved-card") });
    await expect(resolvedInlineBlock).not.toBeVisible();

    // Open comments panel
    await page.keyboard.press("Shift+C");
    const panel = page.locator(".comments-panel");
    await expect(panel).toHaveClass(/comments-panel-open/, { timeout: 5_000 });

    // Click "Show resolved" label in the panel (checkbox is visually hidden)
    const filterLabel = panel.locator(".comments-panel-switch");
    await expect(filterLabel).toBeVisible({ timeout: 5_000 });
    await filterLabel.click();

    // The resolved comment should be visible in the side panel
    const panelComment = panel
      .locator(".panel-comment-block")
      .filter({ hasText: "Panel visible comment" });
    await expect(panelComment).toBeVisible({ timeout: 5_000 });
  });

  test("keyboard shortcut h toggles hide resolved", async ({ page }) => {
    await loadReview(page, token);

    // Add a comment and resolve it
    await addAndResolveComment(page, "Shortcut test comment");

    const resolvedBlock = page
      .locator(".comment-block:not(.panel-comment-block)")
      .filter({ has: page.locator(".resolved-card") });

    // Verify visible before toggle
    await expect(resolvedBlock).toBeVisible();

    // Press h to hide
    await page.keyboard.press("h");
    await expect(resolvedBlock).not.toBeVisible();

    // Press h again to show
    await page.keyboard.press("h");
    await expect(resolvedBlock).toBeVisible();
  });

  test("persists via localStorage across reload", async ({ page }) => {
    await loadReview(page, token);

    // Add a comment and resolve it
    await addAndResolveComment(page, "Persist test comment");

    // Enable hide resolved
    await page.keyboard.press("h");

    const resolvedBlock = page
      .locator(".comment-block:not(.panel-comment-block)")
      .filter({ has: page.locator(".resolved-card") });
    await expect(resolvedBlock).not.toBeVisible();

    // Verify localStorage was set
    const stored = await page.evaluate(() =>
      localStorage.getItem("crit-hide-resolved")
    );
    expect(stored).toBe("true");

    // Reload the page
    await loadReview(page, token);

    // The resolved comment should still be hidden after reload
    // Wait for the comment to be rendered first
    await expect(
      page.locator(".comment-card").filter({ hasText: "Persist test comment" })
    ).toBeAttached({ timeout: 10_000 });

    // The block containing the resolved card should be hidden (display: none)
    const reloadedBlock = page
      .locator(".comment-block:not(.panel-comment-block)")
      .filter({ has: page.locator(".resolved-card") });
    await expect(reloadedBlock).not.toBeVisible();
  });
});
