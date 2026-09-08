import { test, expect } from "@playwright/test";
import { createReview, deleteReview, loadReview, openSettingsPane } from "./helpers";

test.describe("Theme Switching", () => {
  let token: string;
  let deleteToken: string;

  test.beforeEach(async ({ page, request }) => {
    const review = await createReview(request);
    token = review.token;
    deleteToken = review.deleteToken;

    // Clear theme preference
    await page.goto("/");
    await page.evaluate(() => {
      localStorage.removeItem("phx:theme");
    });
  });

  test.afterEach(async ({ request }) => {
    await deleteReview(request, deleteToken);
  });

  test("theme buttons set data-theme on <html> (light, dark, system)", async ({
    page,
  }) => {
    await loadReview(page, token);
    await openSettingsPane(page);

    const html = page.locator("html");

    await page.locator('[data-settings-theme="light"]').click();
    await expect(html).toHaveAttribute("data-theme", "light");

    await page.locator('[data-settings-theme="dark"]').click();
    await expect(html).toHaveAttribute("data-theme", "dark");

    // System mode removes the explicit attribute entirely
    await page.locator('[data-settings-theme="system"]').click();
    await expect
      .poll(async () => await html.getAttribute("data-theme"))
      .toBeNull();
  });

  test("theme persists across page reload", async ({ page }) => {
    await loadReview(page, token);
    await openSettingsPane(page);

    await page.locator('[data-settings-theme="dark"]').click();
    await expect(page.locator("html")).toHaveAttribute("data-theme", "dark");

    // Reload the page
    await loadReview(page, token);

    // Should still be dark
    await expect(page.locator("html")).toHaveAttribute("data-theme", "dark");
  });

  test("theme pill indicator moves when theme changes", async ({ page }) => {
    await loadReview(page, token);
    await openSettingsPane(page);

    const indicator = page.locator("#settingsThemeIndicator");

    // Switch to light: indicator should move
    await page.locator('[data-settings-theme="light"]').click();
    await expect
      .poll(() =>
        indicator.evaluate((el) => parseFloat((el as HTMLElement).style.left))
      )
      .toBeCloseTo(33.333, 0);

    // Switch to dark: indicator should move further
    await page.locator('[data-settings-theme="dark"]').click();
    await expect
      .poll(() =>
        indicator.evaluate((el) => parseFloat((el as HTMLElement).style.left))
      )
      .toBeCloseTo(66.666, 0);
  });
});
