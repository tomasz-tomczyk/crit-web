import { test, expect } from "@playwright/test";
import {
  createMultiFileReview,
  deleteReview,
  loadReview,
  seedComment,
} from "./helpers";

test.describe("Multi-File Review", () => {
  let token: string;
  let deleteToken: string;

  test.beforeEach(async ({ request }) => {
    const review = await createMultiFileReview(request);
    token = review.token;
    deleteToken = review.deleteToken;
  });

  test.afterEach(async ({ request }) => {
    await deleteReview(request, deleteToken);
  });

  test("renders the file tree and matching file sections", async ({ page }) => {
    await loadReview(page, token);

    const fileTreePanel = page.locator("#fileTreePanel");
    await expect(fileTreePanel).toBeVisible({ timeout: 10_000 });

    await expect(page.locator(".tree-file")).toHaveCount(3);
    await expect(page.locator("details.file-section")).toHaveCount(3);

    for (const fileName of ["main.ts", "utils.ts", "README.md"]) {
      await expect(
        page.locator(".tree-file-name", { hasText: fileName })
      ).toBeVisible();
      await expect(
        page.locator(".file-header-name", { hasText: fileName })
      ).toBeVisible();
    }
  });

  test("clicking a file in the tree expands and scrolls to it", async ({
    page,
  }) => {
    await loadReview(page, token);

    const utilsSection = page.locator(
      'details.file-section:has(.file-header-name:has-text("utils.ts"))'
    );
    await utilsSection.locator("summary.file-header").click();
    await expect(utilsSection).not.toHaveAttribute("open", "");
    const utilsHeader = utilsSection.locator("summary.file-header");

    // Playwright scrolls elements into view before clicking them, so reset the
    // page and prove the tree click itself moves this off-screen target.
    await page.evaluate(() => window.scrollTo(0, 0));
    await expect
      .poll(() =>
        utilsHeader.evaluate(
          (header) => header.getBoundingClientRect().top > window.innerHeight
        )
      )
      .toBe(true);

    await page.locator('.tree-file[data-path="src/utils.ts"]').click();

    await expect(utilsSection).toHaveAttribute("open", "");
    await expect
      .poll(() => page.evaluate(() => window.scrollY))
      .toBeGreaterThan(0);
    await expect(utilsHeader).toBeInViewport();
    await expect
      .poll(() =>
        utilsHeader.evaluate((header) => {
          const { top } = header.getBoundingClientRect();
          return top >= 0 && top < 200;
        })
      )
      .toBe(true);
  });

  test("can add comments to different files", async ({ page, request }) => {
    // Seed comments on different files
    await seedComment(request, token, {
      body: "Fix the main function",
      startLine: 1,
      file: "src/main.ts",
    });
    await seedComment(request, token, {
      body: "Update the readme",
      startLine: 1,
      file: "README.md",
    });

    await loadReview(page, token);

    // Both comments should be visible
    await expect(
      page.locator(".comment-card").filter({ hasText: "Fix the main function" })
    ).toBeVisible({ timeout: 10_000 });
    await expect(
      page.locator(".comment-card").filter({ hasText: "Update the readme" })
    ).toBeVisible({ timeout: 10_000 });

    // Total comment count should be 2
    await expect(page.locator("#commentCountNumber")).toHaveText("2");
  });

  test("creates file- and review-level comments via the UI", async ({ page }) => {
    await loadReview(page, token);

    const reviewConversation = page.locator("#reviewConversation");
    await reviewConversation
      .getByRole("button", { name: "Add comment" })
      .click();
    const reviewTextarea = reviewConversation.locator(".comment-form textarea");
    await reviewTextarea.fill("Review-wide feedback");
    await reviewTextarea.press("Control+Enter");
    await expect(
      reviewConversation.locator(".comment-card", {
        hasText: "Review-wide feedback",
      })
    ).toBeVisible();

    const mainSection = page.locator(
      'details.file-section:has(.file-header-name:has-text("main.ts"))'
    );
    await mainSection.getByTitle("Add file comment").click();
    const fileTextarea = mainSection.locator(".file-comment-form textarea");
    await fileTextarea.fill("Main file feedback");
    await fileTextarea.press("Control+Enter");
    await expect(
      mainSection.locator(".file-comments .comment-card", {
        hasText: "Main file feedback",
      })
    ).toBeVisible();

    await expect(page.locator("#commentCountNumber")).toHaveText("2");
  });
});
