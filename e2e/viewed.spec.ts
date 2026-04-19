import { test, expect } from "@playwright/test";
import { createReview, deleteReview, loadReview } from "./helpers";

test.describe("Viewed Checkbox — Multi-File Review", () => {
  let token: string;
  let deleteToken: string;

  test.beforeAll(async ({ request }) => {
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

  test.beforeEach(async ({ page }) => {
    // Clear any persisted viewed state before each test
    await page.goto("/");
    await page.evaluate(() => {
      for (let i = localStorage.length - 1; i >= 0; i--) {
        const key = localStorage.key(i);
        if (key && key.startsWith("crit-viewed-")) localStorage.removeItem(key);
      }
    });
  });

  test.afterAll(async ({ request }) => {
    await deleteReview(request, deleteToken);
  });

  test("each file section has a viewed checkbox", async ({ page }) => {
    await loadReview(page, token);

    const checkboxes = page.locator(
      '.file-header-viewed input[type="checkbox"]'
    );
    const sections = page.locator("details.file-section");
    const sectionCount = await sections.count();
    expect(sectionCount).toBe(3);
    await expect(checkboxes).toHaveCount(sectionCount);
  });

  test("viewed checkbox starts unchecked", async ({ page }) => {
    await loadReview(page, token);

    const checkbox = page
      .locator('.file-header-viewed input[type="checkbox"]')
      .first();
    await expect(checkbox).not.toBeChecked();
  });

  test("clicking viewed checkbox marks file as viewed", async ({ page }) => {
    await loadReview(page, token);

    const checkbox = page
      .locator('.file-header-viewed input[type="checkbox"]')
      .first();
    await checkbox.click();
    await expect(checkbox).toBeChecked();
  });

  test("checking viewed collapses the file section", async ({ page }) => {
    await loadReview(page, token);

    const section = page.locator("details.file-section").first();
    await expect(section).toHaveAttribute("open", "");

    const checkbox = section.locator(
      '.file-header-viewed input[type="checkbox"]'
    );
    await checkbox.click();

    await expect(section).not.toHaveAttribute("open", "");
  });

  test("viewed state persists in localStorage", async ({ page }) => {
    await loadReview(page, token);

    const checkbox = page
      .locator('.file-header-viewed input[type="checkbox"]')
      .first();
    await checkbox.click();
    await expect(checkbox).toBeChecked();

    // Verify localStorage was updated
    const hasViewed = await page.evaluate(() => {
      const keys = Object.keys(localStorage).filter((k) =>
        k.startsWith("crit-viewed-")
      );
      return keys.length > 0;
    });
    expect(hasViewed).toBe(true);
  });

  test("viewed state persists across page reload", async ({ page }) => {
    await loadReview(page, token);

    const checkbox = page
      .locator('.file-header-viewed input[type="checkbox"]')
      .first();
    await checkbox.click();
    await expect(checkbox).toBeChecked();

    // Reload the page — use goto directly since loadReview waits for
    // visible .line-block elements, but viewed files collapse their sections
    await page.goto(`/r/${token}`);
    // Wait for the file sections to render
    await page.waitForSelector("details.file-section", { timeout: 15_000 });

    // Checkbox should still be checked
    const reloadedCheckbox = page
      .locator('.file-header-viewed input[type="checkbox"]')
      .first();
    await expect(reloadedCheckbox).toBeChecked({ timeout: 5_000 });
  });

  test("viewed checkbox updates the tree indicator", async ({ page }) => {
    await loadReview(page, token);

    const section = page.locator("details.file-section").first();
    const checkbox = section.locator(
      '.file-header-viewed input[type="checkbox"]'
    );

    // No viewed indicator initially
    const treeFile = page.locator(".tree-file").first();
    await expect(treeFile.locator(".tree-viewed-check")).toHaveCount(0);

    await checkbox.click();

    // Tree file should have viewed class and checkmark
    await expect(treeFile).toHaveClass(/viewed/);
    await expect(treeFile.locator(".tree-viewed-check")).toBeVisible();
  });
});
