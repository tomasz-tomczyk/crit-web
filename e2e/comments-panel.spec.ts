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
 * Comments panel — merged spec covering:
 * 1. Toggle & visibility (open/close, panel rendering, scroll-to-comment)
 * 2. Filter & grouping (segmented filter pill, count badge, file groups,
 *    expand/collapse all)
 *
 * The redundant "Show resolved filter" test from the legacy detail spec is
 * dropped — coverage lives in the segmented-filter tests below.
 */

test.describe("Comments Panel — Toggle & visibility", () => {
  let token: string;
  let deleteToken: string;

  test.beforeEach(async ({ request }) => {
    const review = await createReview(request, {
      files: [
        {
          path: "example.md",
          content:
            "Line 1\nLine 2\nLine 3\nLine 4\nLine 5\nLine 6\nLine 7\nLine 8\nLine 9\nLine 10\n" +
            "Line 11\nLine 12\nLine 13\nLine 14\nLine 15\nLine 16\nLine 17\nLine 18\nLine 19\nLine 20\n",
        },
      ],
    });
    token = review.token;
    deleteToken = review.deleteToken;
  });

  test.afterEach(async ({ request }) => {
    await deleteReview(request, deleteToken);
  });

  test("panel shows all comments", async ({ page, request }) => {
    await seedComment(request, token, {
      body: "First panel comment",
      startLine: 1,
    });
    await seedComment(request, token, {
      body: "Second panel comment",
      startLine: 5,
    });

    await loadReview(page, token);
    await waitForCommentCard(page, "First panel comment");

    await page.locator("#comment-count").click();
    const panel = page.locator(".comments-panel");
    await expect(panel).toBeVisible({ timeout: 5_000 });

    await expect(panel).toContainText("First panel comment");
    await expect(panel).toContainText("Second panel comment");
  });

  test("Shift+C toggles panel open and closed", async ({ page, request }) => {
    await seedComment(request, token, {
      body: "Toggle test",
      startLine: 1,
    });

    await loadReview(page, token);
    await waitForCommentCard(page, "Toggle test");

    const panel = page.locator(".comments-panel");

    await page.keyboard.press("Shift+C");
    await expect(panel).toHaveClass(/comments-panel-open/, { timeout: 5_000 });

    await page.keyboard.press("Shift+C");
    await expect(panel).not.toHaveClass(/comments-panel-open/);
  });

  test("close button hides panel", async ({ page, request }) => {
    await seedComment(request, token, {
      body: "Close button test",
      startLine: 1,
    });

    await loadReview(page, token);
    await waitForCommentCard(page, "Close button test");

    await page.locator("#comment-count").click();
    const panel = page.locator(".comments-panel");
    await expect(panel).toHaveClass(/comments-panel-open/, { timeout: 5_000 });

    await panel.locator(".comments-panel-close").click();
    await expect(panel).not.toHaveClass(/comments-panel-open/);
  });

  test("clicking a comment in panel scrolls to inline comment", async ({
    page,
    request,
  }) => {
    await seedComment(request, token, {
      body: "Bottom comment to scroll to",
      startLine: 18,
    });

    await loadReview(page, token);
    await waitForCommentCard(page, "Bottom comment to scroll to");

    await page.locator("#comment-count").click();
    const panel = page.locator(".comments-panel");
    await expect(panel).toHaveClass(/comments-panel-open/, { timeout: 5_000 });

    const panelComment = panel.locator(".panel-comment-block").first();
    await panelComment.click();

    const inlineCard = page
      .locator("#document-renderer .comment-card")
      .filter({ hasText: "Bottom comment to scroll to" });
    await expect(inlineCard).toBeVisible({ timeout: 5_000 });
  });
});

test.describe("Comments Panel — Filter & grouping", () => {
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

    const allBtn = panel.locator('.crit-toggle-btn[data-filter="all"]');
    await expect(allBtn).toHaveClass(/crit-toggle-btn--active/);

    await expect(panel).toContainText("Open comment");
    await expect(panel).toContainText("Another open");
  });

  test("segmented filter Open shows only unresolved comments", async ({
    page,
  }) => {
    await loadReview(page, token);

    await addCommentViaUI(page, "Will stay open", { lineIndex: 0 });
    await addCommentViaUI(page, "Will be resolved", { lineIndex: 4 });

    const resolvedCard = page
      .locator(".comment-card")
      .filter({ hasText: "Will be resolved" });
    await resolvedCard.locator(".resolve-btn").click();
    await expect(resolvedCard).toHaveClass(/resolved-card/, { timeout: 5_000 });

    const panel = await openPanel(page);

    const openBtn = panel.locator('.crit-toggle-btn[data-filter="open"]');
    await openBtn.click();
    await expect(openBtn).toHaveClass(/crit-toggle-btn--active/);

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

    const card = page
      .locator(".comment-card")
      .filter({ hasText: "Gets resolved" });
    await card.locator(".resolve-btn").click();
    await expect(card).toHaveClass(/resolved-card/, { timeout: 5_000 });

    const panel = await openPanel(page);

    const resolvedBtn = panel.locator('.crit-toggle-btn[data-filter="resolved"]');
    await resolvedBtn.click();
    await expect(resolvedBtn).toHaveClass(/crit-toggle-btn--active/);

    await expect(panel).toContainText("Gets resolved");
    await expect(
      panel.locator(".panel-comment-block").filter({ hasText: "Stays open" })
    ).not.toBeVisible();
  });

  test("filter pill counts match actual comment counts", async ({ page }) => {
    await loadReview(page, token);

    await addCommentViaUI(page, "Open one", { lineIndex: 0 });
    await addCommentViaUI(page, "Open two", { lineIndex: 2 });
    await addCommentViaUI(page, "To resolve", { lineIndex: 4 });

    const card = page
      .locator(".comment-card")
      .filter({ hasText: "To resolve" });
    await card.locator(".resolve-btn").click();
    await expect(card).toHaveClass(/resolved-card/, { timeout: 5_000 });

    const panel = await openPanel(page);

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
    const multiFileReview = await createReview(request, {
      files: [
        { path: "alpha.ts", content: "Line 1\nLine 2\nLine 3\n" },
        { path: "beta.ts", content: "Line 1\nLine 2\nLine 3\n" },
      ],
    });
    const mfToken = multiFileReview.token;

    await seedComment(request, mfToken, { body: "File comment", startLine: 1, file: "alpha.ts" });

    await loadReview(page, mfToken);
    await waitForCommentCard(page, "File comment");

    const panel = await openPanel(page);

    const fileGroup = panel.locator(".comments-panel-file-group").first();
    const fileCards = fileGroup.locator(".comments-panel-file-cards");

    await expect(fileCards).toBeVisible();

    const fileHeader = fileGroup.locator(".comments-panel-file-name");
    await fileHeader.click();
    await expect(fileGroup).toHaveClass(/collapsed/);

    await fileHeader.click();
    await expect(fileGroup).not.toHaveClass(/collapsed/);

    await deleteReview(request, multiFileReview.deleteToken);
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

    await expect(expandAllBtn).toHaveText("Collapse all");

    await expandAllBtn.click();

    const panelCards = panel.locator(".comment-card");
    const count = await panelCards.count();
    expect(count).toBeGreaterThanOrEqual(2);
    for (let i = 0; i < count; i++) {
      await expect(panelCards.nth(i)).toHaveClass(/collapsed/);
    }

    await expect(expandAllBtn).toHaveText("Expand all");

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

    const inlineCard = page
      .locator("#document-renderer .comment-card")
      .filter({ hasText: "Inline collapse test" });
    await expect(inlineCard).toBeVisible();
    await expect(inlineCard).not.toHaveClass(/collapsed/);

    const expandAllBtn = panel.locator("#commentsPanelExpandAll");
    await expandAllBtn.click();

    await expect(inlineCard).toHaveClass(/collapsed/);

    await expandAllBtn.click();
    await expect(inlineCard).not.toHaveClass(/collapsed/);
  });
});
