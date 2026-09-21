import { test, expect } from "@playwright/test";
import {
  createMultiFileReview,
  deleteReview,
  loadReview,
} from "./helpers";

test.describe("Viewed Checkbox — Multi-File Review", () => {
  let token: string;
  let deleteToken: string;

  test.beforeAll(async ({ request }) => {
    const review = await createMultiFileReview(request);
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

  test("each file section has a viewed checkbox, unchecked by default", async ({ page }) => {
    await loadReview(page, token);

    const checkboxes = page.locator(
      '.file-header-viewed input[type="checkbox"]'
    );
    const sections = page.locator("details.file-section");
    await expect(sections).toHaveCount(3);
    await expect(checkboxes).toHaveCount(3);
    await expect
      .poll(() =>
        checkboxes.evaluateAll((elements) =>
          elements.map((element) => (element as HTMLInputElement).checked)
        )
      )
      .toEqual([false, false, false]);
  });

  test("clicking viewed checkbox marks file as viewed and persists to localStorage", async ({ page }) => {
    await loadReview(page, token);

    const mainSection = page.locator(
      'details.file-section:has(.file-header-name:has-text("main.ts"))'
    );
    const checkbox = mainSection.locator(
      '.file-header-viewed input[type="checkbox"]'
    );
    await checkbox.click();
    await expect(checkbox).toBeChecked();

    // Verify the persisted value belongs to the file that was checked.
    await expect
      .poll(() =>
        page.evaluate(() => {
          const keys = Object.keys(localStorage).filter((key) =>
            key.startsWith("crit-viewed-")
          );
          const key = keys[0];
          return keys.length === 1 && key
            ? JSON.parse(localStorage.getItem(key) || "{}")
            : null;
        })
      )
      .toEqual({ "src/main.ts": true });
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

    const filePath = "src/main.ts";

    // No viewed indicator initially
    const treeFile = page.locator(`.tree-file[data-path="${filePath}"]`);
    await expect(treeFile.locator(".tree-viewed-check")).toHaveCount(0);

    const section = page.locator(
      'details.file-section:has(.file-header-name:has-text("main.ts"))'
    );
    await section
      .locator('.file-header-viewed input[type="checkbox"]')
      .click();

    // Tree file should have viewed class and checkmark
    await expect(treeFile).toHaveClass(/viewed/);
    await expect(treeFile.locator(".tree-viewed-check")).toBeVisible();
  });
});
