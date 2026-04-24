import { test, expect } from "@playwright/test";
import {
  createReview,
  deleteReview,
  loadReview,
  seedComment,
  waitForCommentCard,
  addCommentViaUI,
} from "./helpers";

/**
 * Tests for the redesigned comments panel:
 * - Two-row header with count badge
 * - Segmented filter pill (All / Open / Resolved)
 * - Collapsible file groups
 * - Expand all / Collapse all toggle
 */
test.describe("Comments Panel — Redesigned Header & Filters", () => {
  let token: string;
  let deleteToken: string;

  test.beforeEach(async ({ request }) => {
    const review = await createReview(request, {
      files: [
        {
          path: "main.ts",
          content:
            "Line 1\nLine 2\nLine 3\nLine 4\nLine 5\nLine 6\nLine 7\nLine 8\nLine 9\nLine 10\n",
        },
      ],
    });
    token = review.token;
    deleteToken = review.deleteToken;
  });

  test.afterEach(async ({ request }) => {
    await deleteReview(request, deleteToken);
  });

  /**
   * Helper: open the comments panel and return the panel locator.
   */
  async function openPanel(page: import("@playwright/test").Page) {
    await page.locator("#comment-count").click();
    const panel = page.locator(".comments-panel");
    await expect(panel).toHaveClass(/comments-panel-open/, { timeout: 5_000 });
    return panel;
  }

  test("panel header shows correct count badge", async ({
    page,
    request,
  }) => {
    await seedComment(request, token, { body: "Comment A", startLine: 1 });
    await seedComment(request, token, { body: "Comment B", startLine: 3 });
    await seedComment(request, token, { body: "Comment C", startLine: 5 });

    await loadReview(page, token);
    await waitForCommentCard(page, "Comment A");

    const panel = await openPanel(page);

    // Count badge should show total of 3
    const badge = panel.locator("#commentsPanelCountBadge");
    await expect(badge).toHaveText("3");
  });

  test("segmented filter defaults to All with all comments shown", async ({
    page,
    request,
  }) => {
    await seedComment(request, token, { body: "Open comment", startLine: 1 });
    await seedComment(request, token, { body: "Another open", startLine: 3 });

    await loadReview(page, token);
    await waitForCommentCard(page, "Open comment");

    const panel = await openPanel(page);

    // "All" button should be active by default
    const allBtn = panel.locator('.crit-toggle-btn[data-filter="all"]');
    await expect(allBtn).toHaveClass(/crit-toggle-btn--active/);

    // Both comments should be visible in the panel
    await expect(panel).toContainText("Open comment");
    await expect(panel).toContainText("Another open");
  });

  test("segmented filter Open shows only unresolved comments", async ({
    page,
  }) => {
    await loadReview(page, token);

    // Add two comments via UI so we can resolve one
    await addCommentViaUI(page, "Will stay open", { lineIndex: 0 });
    await addCommentViaUI(page, "Will be resolved", { lineIndex: 4 });

    // Resolve the second comment
    const resolvedCard = page
      .locator(".comment-card")
      .filter({ hasText: "Will be resolved" });
    await resolvedCard.locator(".resolve-btn").click();
    await expect(resolvedCard).toHaveClass(/resolved-card/, { timeout: 5_000 });

    const panel = await openPanel(page);

    // Click "Open" filter
    const openBtn = panel.locator('.crit-toggle-btn[data-filter="open"]');
    await openBtn.click();
    await expect(openBtn).toHaveClass(/crit-toggle-btn--active/);

    // Only the open comment should be visible
    await expect(panel).toContainText("Will stay open");
    await expect(
      panel.locator(".panel-comment-block").filter({ hasText: "Will be resolved" })
    ).not.toBeVisible();
  });

  test("segmented filter Resolved shows only resolved comments", async ({
    page,
  }) => {
    await loadReview(page, token);

    await addCommentViaUI(page, "Stays open", { lineIndex: 0 });
    await addCommentViaUI(page, "Gets resolved", { lineIndex: 4 });

    // Resolve the second comment
    const card = page
      .locator(".comment-card")
      .filter({ hasText: "Gets resolved" });
    await card.locator(".resolve-btn").click();
    await expect(card).toHaveClass(/resolved-card/, { timeout: 5_000 });

    const panel = await openPanel(page);

    // Click "Resolved" filter
    const resolvedBtn = panel.locator('.crit-toggle-btn[data-filter="resolved"]');
    await resolvedBtn.click();
    await expect(resolvedBtn).toHaveClass(/crit-toggle-btn--active/);

    // Only the resolved comment should be visible
    await expect(panel).toContainText("Gets resolved");
    await expect(
      panel.locator(".panel-comment-block").filter({ hasText: "Stays open" })
    ).not.toBeVisible();
  });

  test("filter pill counts match actual comment counts", async ({
    page,
  }) => {
    await loadReview(page, token);

    // Create 3 comments, resolve 1
    await addCommentViaUI(page, "Open one", { lineIndex: 0 });
    await addCommentViaUI(page, "Open two", { lineIndex: 2 });
    await addCommentViaUI(page, "To resolve", { lineIndex: 4 });

    const card = page
      .locator(".comment-card")
      .filter({ hasText: "To resolve" });
    await card.locator(".resolve-btn").click();
    await expect(card).toHaveClass(/resolved-card/, { timeout: 5_000 });

    const panel = await openPanel(page);

    // All = 3, Open = 2, Resolved = 1
    const allCount = panel.locator('.crit-toggle-btn[data-filter="all"] .filter-count');
    const openCount = panel.locator('.crit-toggle-btn[data-filter="open"] .filter-count');
    const resolvedCount = panel.locator('.crit-toggle-btn[data-filter="resolved"] .filter-count');

    await expect(allCount).toHaveText("3");
    await expect(openCount).toHaveText("2");
    await expect(resolvedCount).toHaveText("1");
  });

  test("collapsible file groups toggle on click", async ({
    page,
    request,
  }) => {
    await seedComment(request, token, { body: "File comment", startLine: 1 });

    await loadReview(page, token);
    await waitForCommentCard(page, "File comment");

    const panel = await openPanel(page);

    // Find the file group
    const fileGroup = panel.locator(".comments-panel-file-group").first();
    const fileCards = fileGroup.locator(".comments-panel-file-cards");

    // Initially expanded — cards should be visible
    await expect(fileCards).toBeVisible();

    // Click the file group header to collapse
    const fileHeader = fileGroup.locator(".comments-panel-file-name");
    await fileHeader.click();

    // Group should now have collapsed class
    await expect(fileGroup).toHaveClass(/collapsed/);

    // Click again to expand
    await fileHeader.click();
    await expect(fileGroup).not.toHaveClass(/collapsed/);
  });

  test("Expand all / Collapse all toggles all comment cards", async ({
    page,
    request,
  }) => {
    await seedComment(request, token, { body: "Card one", startLine: 1 });
    await seedComment(request, token, { body: "Card two", startLine: 3 });

    await loadReview(page, token);
    await waitForCommentCard(page, "Card one");

    const panel = await openPanel(page);

    const expandAllBtn = panel.locator("#commentsPanelExpandAll");

    // Initially cards are expanded, so button should say "Collapse all"
    await expect(expandAllBtn).toHaveText("Collapse all");

    // Click to collapse all
    await expandAllBtn.click();

    // All panel comment cards should have the collapsed class
    const panelCards = panel.locator(".comment-card");
    const count = await panelCards.count();
    expect(count).toBeGreaterThanOrEqual(2);
    for (let i = 0; i < count; i++) {
      await expect(panelCards.nth(i)).toHaveClass(/collapsed/);
    }

    // Button label should now say "Expand all"
    await expect(expandAllBtn).toHaveText("Expand all");

    // Click to expand all again
    await expandAllBtn.click();

    for (let i = 0; i < count; i++) {
      await expect(panelCards.nth(i)).not.toHaveClass(/collapsed/);
    }
    await expect(expandAllBtn).toHaveText("Collapse all");
  });

  test("Collapse all also collapses inline comments in the document body", async ({
    page,
    request,
  }) => {
    await seedComment(request, token, { body: "Inline collapse test", startLine: 1 });

    await loadReview(page, token);
    await waitForCommentCard(page, "Inline collapse test");

    const panel = await openPanel(page);

    // Verify inline comment card in document is initially not collapsed
    const inlineCard = page
      .locator("#document-renderer .comment-card")
      .filter({ hasText: "Inline collapse test" });
    await expect(inlineCard).toBeVisible();
    await expect(inlineCard).not.toHaveClass(/collapsed/);

    // Click Collapse all in the panel
    const expandAllBtn = panel.locator("#commentsPanelExpandAll");
    await expandAllBtn.click();

    // Inline comment card should now be collapsed
    await expect(inlineCard).toHaveClass(/collapsed/);

    // Click Expand all to restore
    await expandAllBtn.click();
    await expect(inlineCard).not.toHaveClass(/collapsed/);
  });
});
