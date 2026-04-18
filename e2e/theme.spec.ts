import { test, expect } from "@playwright/test";
import { createReview, deleteReview, loadReview } from "./helpers";

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

  test("clicking light theme sets data-theme='light' on <html>", async ({
    page,
  }) => {
    await loadReview(page, token);

    // Open settings panel
    await page.locator("#settingsToggle").click();
    const overlay = page.locator("#settingsOverlay.active");
    await expect(overlay).toBeVisible({ timeout: 5_000 });

    // Switch to settings tab if not already active
    const settingsTab = page.locator('.settings-tab[data-tab="settings"]');
    await settingsTab.click();

    // Click light theme button
    await page.locator('[data-settings-theme="light"]').click();

    const dataTheme = await page.locator("html").getAttribute("data-theme");
    expect(dataTheme).toBe("light");
  });

  test("clicking dark theme sets data-theme='dark' on <html>", async ({
    page,
  }) => {
    await loadReview(page, token);

    await page.locator("#settingsToggle").click();
    const overlay = page.locator("#settingsOverlay.active");
    await expect(overlay).toBeVisible({ timeout: 5_000 });

    const settingsTab = page.locator('.settings-tab[data-tab="settings"]');
    await settingsTab.click();

    await page.locator('[data-settings-theme="dark"]').click();

    const dataTheme = await page.locator("html").getAttribute("data-theme");
    expect(dataTheme).toBe("dark");
  });

  test("clicking system theme removes explicit data-theme", async ({
    page,
  }) => {
    await loadReview(page, token);

    // First set to dark
    await page.locator("#settingsToggle").click();
    const overlay = page.locator("#settingsOverlay.active");
    await expect(overlay).toBeVisible({ timeout: 5_000 });

    const settingsTab = page.locator('.settings-tab[data-tab="settings"]');
    await settingsTab.click();

    await page.locator('[data-settings-theme="dark"]').click();
    expect(await page.locator("html").getAttribute("data-theme")).toBe("dark");

    // Switch to system
    await page.locator('[data-settings-theme="system"]').click();

    // data-theme should be removed (null) or set to system behavior
    const dataTheme = await page.locator("html").getAttribute("data-theme");
    // System mode: the theme attribute is removed entirely
    expect(dataTheme).toBeNull();
  });

  test("theme persists across page reload", async ({ page }) => {
    await loadReview(page, token);

    // Set dark theme
    await page.locator("#settingsToggle").click();
    await expect(
      page.locator("#settingsOverlay.active")
    ).toBeVisible({ timeout: 5_000 });

    await page.locator('.settings-tab[data-tab="settings"]').click();
    await page.locator('[data-settings-theme="dark"]').click();
    expect(await page.locator("html").getAttribute("data-theme")).toBe("dark");

    // Reload the page
    await loadReview(page, token);

    // Should still be dark
    const dataTheme = await page.locator("html").getAttribute("data-theme");
    expect(dataTheme).toBe("dark");
  });

  test("theme pill indicator moves when theme changes", async ({ page }) => {
    await loadReview(page, token);

    await page.locator("#settingsToggle").click();
    await expect(
      page.locator("#settingsOverlay.active")
    ).toBeVisible({ timeout: 5_000 });

    await page.locator('.settings-tab[data-tab="settings"]').click();

    const indicator = page.locator("#settingsThemeIndicator");

    // Switch to light: indicator should move
    await page.locator('[data-settings-theme="light"]').click();
    const lightLeft = await indicator.evaluate(
      (el) => parseFloat((el as HTMLElement).style.left)
    );
    expect(lightLeft).toBeCloseTo(33.333, 0);

    // Switch to dark: indicator should move further
    await page.locator('[data-settings-theme="dark"]').click();
    const darkLeft = await indicator.evaluate(
      (el) => parseFloat((el as HTMLElement).style.left)
    );
    expect(darkLeft).toBeCloseTo(66.666, 0);
  });
});
