import { test, expect } from "@playwright/test";
import { createReview, deleteReview, loadReview, seedComment } from "./helpers";

test.describe("Multi-File Review", () => {
  let token: string;
  let deleteToken: string;

  test.beforeEach(async ({ request }) => {
    const review = await createReview(request, {
      files: [
        {
          path: "src/main.ts",
          content: "export function main() {\n  console.log('hello')\n}\n",
        },
        {
          path: "src/utils.ts",
          content:
            "export function add(a: number, b: number) {\n  return a + b\n}\n",
        },
        {
          path: "README.md",
          content: "# My Project\n\nA sample project.\n",
        },
      ],
    });
    token = review.token;
    deleteToken = review.deleteToken;
  });

  test.afterEach(async ({ request }) => {
    await deleteReview(request, deleteToken);
  });

  test("shows the file tree panel for multi-file reviews", async ({
    page,
  }) => {
    await loadReview(page, token);

    // The file tree panel should be visible for multi-file reviews
    const fileTreePanel = page.locator("#fileTreePanel");
    await expect(fileTreePanel).toBeVisible({ timeout: 10_000 });
  });

  test("file tree lists all files", async ({ page }) => {
    await loadReview(page, token);

    const fileTreePanel = page.locator("#fileTreePanel");
    await expect(fileTreePanel).toBeVisible({ timeout: 10_000 });

    // All three files should appear in the tree
    await expect(page.locator(".tree-file")).toHaveCount(3);
    await expect(
      page.locator('.tree-file-name:has-text("main.ts")')
    ).toBeVisible();
    await expect(
      page.locator('.tree-file-name:has-text("utils.ts")')
    ).toBeVisible();
    await expect(
      page.locator('.tree-file-name:has-text("README.md")')
    ).toBeVisible();
  });

  test("clicking a file in the tree scrolls to it", async ({ page }) => {
    await loadReview(page, token);

    const fileTreePanel = page.locator("#fileTreePanel");
    await expect(fileTreePanel).toBeVisible({ timeout: 10_000 });

    // Click the README.md entry in the file tree
    await page
      .locator('.tree-file:has-text("README.md")')
      .click();

    // The corresponding file section should be scrolled into view.
    // Use the file-header-name that contains the filename text.
    const readmeSection = page.locator(
      'details.file-section:has(.file-header-name:text("README.md"))'
    );
    await expect(readmeSection).toBeVisible();
  });

  test("renders file sections with correct headers", async ({ page }) => {
    await loadReview(page, token);

    // Each file should have its own details/summary section
    const fileSections = page.locator("details.file-section");
    await expect(fileSections).toHaveCount(3, { timeout: 10_000 });
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
});
