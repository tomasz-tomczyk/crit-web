import { test, expect } from "@playwright/test";

// /themes: flip through the bundled themes on fixed samples (crit's
// theme-preview spec, on crit-web's page).
test.describe("Theme preview page", () => {
  test("switches themes with the keyboard and saves the choice", async ({ page, context }) => {
    await page.goto("/themes#dark/dracula");
    const html = page.locator("html");
    await expect(html).toHaveAttribute("data-crit-palette", "dracula");
    await expect(html).toHaveAttribute("data-theme", "dark");
    // The sample is a real Pierre render in the chosen theme, with a comment.
    await expect(page.locator("#previewCode [data-line]").first()).toBeVisible();
    await expect(page.locator("#previewCode .comment-card")).toBeVisible();
    await expect(page.locator("#themeSamples code.crit-code span[style]").first()).toBeVisible();

    await page.locator("#themeList").focus();
    await page.keyboard.press("ArrowDown");
    await expect(html).not.toHaveAttribute("data-crit-palette", "dracula");
    const next = await html.getAttribute("data-crit-palette");
    await expect(page).toHaveURL(new RegExp(`#dark/${next}$`));
    await expect(page.locator(`#theme-${next}`)).toHaveAttribute("aria-selected", "true");

    await page.locator("#useTheme").click();
    await expect(page.locator("#useTheme")).toBeDisabled();
    const cookie = (await context.cookies()).find((c) => c.name === "crit-settings");
    expect(JSON.parse(decodeURIComponent(cookie!.value)).darkPalette).toBe(next);

    // The saved theme is applied server-side on the next page load.
    await page.goto("/themes");
    await expect(html).toHaveAttribute("data-crit-palette-dark", next!);
    expect(await page.locator("#crit-palette").textContent()).toContain("--crit-palette-bg:");
    await expect(html).toHaveAttribute("data-crit-palette-dark", next!);
  });

  test("light and dark lists only offer their own themes", async ({ page }) => {
    await page.goto("/themes#light/github-light-default");
    await expect(page.locator("html")).toHaveAttribute("data-theme", "light");
    await expect(page.locator("#theme-github-light-default")).toBeVisible();
    await expect(page.locator("#theme-dracula")).toBeHidden();
    await page.locator('[data-preview-mode="dark"]').click();
    await expect(page.locator("html")).toHaveAttribute("data-theme", "dark");
    await expect(page.locator("#theme-dracula")).toBeVisible();
    await expect(page.locator("#theme-github-light-default")).toBeHidden();
    await expect(page.locator('[data-preview-mode="dark"]')).toHaveAttribute("aria-pressed", "true");
  });

  test("follows and edits the display settings", async ({ page, context }) => {
    await page.goto("/themes#dark/tokyo-night");
    const pre = page.locator("#previewCode pre").first();
    await expect(pre).toBeVisible();
    await expect(pre).not.toHaveAttribute("data-disable-line-numbers", "");
    await page.locator("#lineNumbersSelect").selectOption("off");
    await expect(page.locator("#previewCode pre").first()).toHaveAttribute("data-disable-line-numbers", "");
    await page.locator("#codeOverflowSelect").selectOption("wrap");
    await expect(page.locator("#previewCode pre").first()).toHaveAttribute("data-overflow", "wrap");
    const settings = JSON.parse(decodeURIComponent((await context.cookies()).find((c) => c.name === "crit-settings")!.value));
    expect(settings).toMatchObject({ lineNumbers: "off", codeOverflow: "wrap" });
    await page.reload();
    await expect(page.locator("#previewCode pre").first()).toHaveAttribute("data-disable-line-numbers", "");
  });

  test("boosting syntax contrast darkens faint theme colours", async ({ page }) => {
    await page.goto("/themes#light/min-light");
    // Min Light's comments are #c2c3c5 (1.76:1 on white) as designed.
    const comment = () => page.locator("#previewCode [data-line] span", { hasText: "authMiddleware checks the API" }).first();
    await expect(comment()).toHaveCSS("color", "rgb(194, 195, 197)");
    await page.locator("#boostContrastSelect").selectOption("on");
    await expect.poll(async () => {
      const rgb = await comment().evaluate((el) => getComputedStyle(el).color.match(/\d+/g)!.map(Number));
      return rgb[0] < 120 && Math.abs(rgb[0] - rgb[2]) < 20;
    }).toBe(true);
    await page.locator("#boostContrastSelect").selectOption("off");
    await expect(comment()).toHaveCSS("color", "rgb(194, 195, 197)");
  });

  test("is not indexed", async ({ page }) => {
    await page.goto("/themes");
    await expect(page.locator('meta[name="robots"]')).toHaveAttribute("content", /noindex/);
  });
});
