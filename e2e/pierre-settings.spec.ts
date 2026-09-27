import { test, expect, Page } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";
import {
  codeFile,
  codeLine,
  createPreviewReview,
  createReview,
  deleteReview,
  hoverCodeLine,
  loadPreview,
  loadReview,
} from "./helpers";

// Code display and theme settings (crit's pierre-settings spec, for the
// settings that apply to crit-web's files and preview modes). They live in the
// `crit-settings` cookie with crit's key names; the server applies the chosen
// palette before first paint.

const pre = (page: Page, path: string) => codeFile(page, path).locator("pre").first();

async function openSettings(page: Page) {
  await page.locator("#settingsToggle").click();
  await expect(page.locator("#settingsOverlay.active")).toBeVisible();
}

async function settingsCookie(page: Page) {
  const cookie = (await page.context().cookies()).find((c) => c.name === "crit-settings");
  return cookie ? JSON.parse(decodeURIComponent(cookie.value)) : {};
}

test.describe("Code display and theme settings", () => {
  let token: string;
  let deleteToken: string;

  test.beforeEach(async ({ request, page }) => {
    const review = await createReview(request, {
      files: [
        { path: "server.go", content: "package main\n\n// " + "long ".repeat(60) + "comment\nfunc main() {}\n" },
        { path: "plan.md", content: "# Plan\n\n```go\nfunc main() {}\n// " + "wide ".repeat(80) + "\n```\n\n```mermaid\ngraph TD; A-->B;\n```\n" },
      ],
    });
    token = review.token;
    deleteToken = review.deleteToken;
    await page.emulateMedia({ colorScheme: "dark" });
    await loadReview(page, token);
    await expect(codeLine(page, "server.go", 1)).toBeVisible();
  });

  test.afterEach(async ({ request }) => {
    await deleteReview(request, deleteToken);
  });

  test("files mode offers the settings that apply to a file review", async ({ page }) => {
    await openSettings(page);
    for (const id of ["lineNumbersSelect", "lightPaletteSelect", "darkPaletteSelect", "boostContrastSelect", "codeOverflowSelect"]) {
      await expect(page.locator("#" + id)).toBeVisible();
    }
    // Diff-only settings have no surface in crit-web.
    for (const id of ["inlineDiffSelect", "changeIndicatorsSelect", "unchangedContextSelect"]) {
      await expect(page.locator("#" + id)).toHaveCount(0);
    }
    await expect.poll(() => page.locator("#darkPaletteSelect option").count()).toBeGreaterThan(20);
    await expect(page.getByRole("link", { name: "Preview all themes" })).toHaveAttribute("href", "/themes");
  });

  test("a dark theme re-themes the page, code and fences, and persists", async ({ page }) => {
    const html = page.locator("html");
    await expect(html).toHaveAttribute("data-crit-palette", "tokyo-night");
    const tokenStyle = () => codeLine(page, "server.go", 1).locator("span[style]").first().getAttribute("style");
    const before = await tokenStyle();

    await openSettings(page);
    const dark = page.locator("#darkPaletteSelect");
    await dark.selectOption("nord");
    await expect(dark).toBeEnabled();
    await expect(html).toHaveAttribute("data-crit-palette", "nord");
    await expect(html).toHaveAttribute("data-crit-palette-dark", "nord");
    await expect.poll(tokenStyle).not.toBe(before);
    const fence = page.locator('.line-block[data-file-path="plan.md"] code.crit-code span[style]').first();
    await expect.poll(() => fence.getAttribute("style")).toContain("--diffs-token-dark:");
    expect(await page.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue("--crit-palette-bg").trim())).toBe("#2e3440");
    expect((await settingsCookie(page)).darkPalette).toBe("nord");

    // Server-rendered on the next visit: no flash of the default theme.
    await loadReview(page, token);
    await expect(html).toHaveAttribute("data-crit-palette-dark", "nord");
    const css = await page.locator("#crit-palette").textContent();
    expect(css).toContain("--crit-palette-bg:#2e3440");
    await openSettings(page);
    await expect(page.locator("#darkPaletteSelect")).toHaveValue("nord");
  });

  test("paired palettes follow explicit and system mode", async ({ page }) => {
    await openSettings(page);
    await page.locator("#darkPaletteSelect").selectOption("nord");
    await expect(page.locator("#darkPaletteSelect")).toBeEnabled();
    await page.locator("#lightPaletteSelect").selectOption("catppuccin-latte");
    await expect(page.locator("#lightPaletteSelect")).toBeEnabled();
    const html = page.locator("html");
    await expect(html).toHaveAttribute("data-crit-palette", "nord");
    await page.locator('[data-settings-theme="light"]').click();
    await expect(html).toHaveAttribute("data-crit-palette", "catppuccin-latte");
    await page.locator('[data-settings-theme="system"]').click();
    await expect(html).toHaveAttribute("data-crit-palette", "nord");
    await page.emulateMedia({ colorScheme: "light" });
    await expect(html).toHaveAttribute("data-crit-palette", "catppuccin-latte");
    // The stylesheet itself switches halves with the OS: no script needed.
    const bg = await page.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue("--crit-palette-bg").trim());
    expect(bg).toBe("#eff1f5");
  });

  test("line numbers can be hidden and the setting survives a reload", async ({ page }) => {
    await openSettings(page);
    await page.locator("#lineNumbersSelect").selectOption("off");
    await page.keyboard.press("Escape");
    await expect(pre(page, "server.go")).toHaveAttribute("data-disable-line-numbers", "");
    await loadReview(page, token);
    await expect(pre(page, "server.go")).toHaveAttribute("data-disable-line-numbers", "");
    await openSettings(page);
    await expect(page.locator("#lineNumbersSelect")).toHaveValue("off");
    await page.locator("#lineNumbersSelect").selectOption("on");
    await page.keyboard.press("Escape");
    await expect(pre(page, "server.go")).not.toHaveAttribute("data-disable-line-numbers", "");
  });

  test("long code lines scroll or wrap", async ({ page }) => {
    await expect(pre(page, "server.go")).toHaveAttribute("data-overflow", "scroll");
    const height = () => codeLine(page, "server.go", 3).evaluate((el) => el.getBoundingClientRect().height);
    const single = await height();
    await openSettings(page);
    await page.locator("#codeOverflowSelect").selectOption("wrap");
    await page.keyboard.press("Escape");
    await expect(pre(page, "server.go")).toHaveAttribute("data-overflow", "wrap");
    await expect.poll(height).toBeGreaterThan(single * 1.5);
    expect((await settingsCookie(page)).codeOverflow).toBe("wrap");
  });

  test("syntax contrast raises faint theme colours", async ({ page }) => {
    await openSettings(page);
    await page.locator("#lightPaletteSelect").selectOption("min-light");
    await expect(page.locator("#lightPaletteSelect")).toBeEnabled();
    await page.locator('[data-settings-theme="light"]').click();
    await page.keyboard.press("Escape");
    // Min Light's comments are #c2c3c5 (1.76:1 on white) as designed.
    const comment = codeLine(page, "server.go", 3).locator("span[style]").first();
    await expect(comment).toHaveCSS("color", "rgb(194, 195, 197)");
    await openSettings(page);
    await page.locator("#boostContrastSelect").selectOption("on");
    await expect(page.locator("#boostContrastSelect")).toBeEnabled();
    await expect.poll(async () => {
      const rgb = await codeLine(page, "server.go", 3).locator("span[style]").first()
        .evaluate((el) => getComputedStyle(el).color.match(/\d+/g)!.map(Number));
      return rgb[0] < 120 && Math.abs(rgb[0] - rgb[2]) < 20;
    }).toBe(true);
  });

  test("the comment + follows the theme accent", async ({ page }) => {
    await openSettings(page);
    await page.locator("#darkPaletteSelect").selectOption("monokai");
    await expect(page.locator("#darkPaletteSelect")).toBeEnabled();
    await page.keyboard.press("Escape");
    await hoverCodeLine(page, "server.go", 4);
    const utility = codeFile(page, "server.go").locator("[data-utility-button]");
    await expect(utility).toBeVisible();
    expect(await utility.evaluate((el) => {
      const probe = document.createElement("span");
      probe.style.color = getComputedStyle(document.documentElement).getPropertyValue("--crit-palette-accent");
      return getComputedStyle(el).backgroundColor === probe.style.color;
    })).toBe(true);
  });

  test("review chrome and settings keep contrast in both modes", async ({ page }) => {
    await openSettings(page);
    await page.addStyleTag({ content: "* { transition: none !important; animation: none !important; }" });
    for (const mode of ["dark", "light"]) {
      await page.locator(`[data-settings-theme="${mode}"]`).click();
      const result = await new AxeBuilder({ page }).include(".crit-header").include("#settingsOverlay").withRules(["color-contrast"]).analyze();
      expect(result.violations).toEqual([]);
    }
  });

  test("a worker failure still paints highlighted code", async ({ page }) => {
    await page.addInitScript(() => {
      window.Worker = class { constructor() { throw new Error("Worker blocked for resilience test"); } } as unknown as typeof Worker;
    });
    await loadReview(page, token);
    await expect(codeLine(page, "server.go", 4)).toContainText("func main");
  });
});

test.describe("Display settings in rendered markdown", () => {
  let token: string;
  let deleteToken: string;

  test.beforeEach(async ({ request }) => {
    const review = await createReview(request, {
      files: [{ path: "plan.md", content: "# Plan\n\n```go\n// " + "wide ".repeat(80) + "\nfunc main() {}\n```\n" }],
    });
    token = review.token;
    deleteToken = review.deleteToken;
  });

  test.afterEach(async ({ request }) => {
    await deleteReview(request, deleteToken);
  });

  test("line numbers hide in the markdown gutter, which keeps its + and width", async ({ page }) => {
    await loadReview(page, token);
    const num = page.locator('.line-block[data-start-line="1"] .line-num');
    await expect(num).toBeVisible();
    const gutterWidth = () => page.locator('.line-block[data-start-line="1"] .line-gutter').evaluate((el) => el.getBoundingClientRect().width);
    const before = await gutterWidth();
    await openSettings(page);
    await expect(page.locator('label[for="lineNumbersSelect"]')).toHaveText("Line numbers");
    await page.locator("#lineNumbersSelect").selectOption("off");
    await page.keyboard.press("Escape");
    await expect(page.locator("html")).toHaveAttribute("data-line-numbers", "off");
    await expect(num).toBeHidden();
    expect(await gutterWidth()).toBe(before);
    // Commenting from the gutter still works.
    await page.locator('.line-block[data-start-line="1"] .line-gutter').click();
    await expect(page.locator(".comment-form textarea")).toBeVisible();
    // Server-rendered on the next load.
    await loadReview(page, token);
    await expect(page.locator("html")).toHaveAttribute("data-line-numbers", "off");
    await expect(num).toBeHidden();
  });

  test("long lines in markdown code blocks wrap with the code setting", async ({ page }) => {
    await loadReview(page, token);
    const wide = page.locator(".line-content.code-line").filter({ hasText: "wide wide" });
    const height = () => wide.evaluate((el) => el.getBoundingClientRect().height);
    const single = await height();
    await expect(wide).toHaveCSS("white-space", "pre");
    await openSettings(page);
    await page.locator("#codeOverflowSelect").selectOption("wrap");
    await page.keyboard.press("Escape");
    await expect(page.locator("html")).toHaveAttribute("data-code-overflow", "wrap");
    await expect(wide).toHaveCSS("white-space", "pre-wrap");
    await expect.poll(height).toBeGreaterThan(single * 1.5);
  });
});

test.describe("Theme settings in preview mode", () => {
  test("offers only the theme choice and applies it", async ({ page, request }) => {
    const review = await createPreviewReview(request);
    try {
      await loadPreview(page, review.token);
      await openSettings(page);
      await expect(page.locator("#darkPaletteSelect")).toBeVisible();
      await expect(page.locator("#lightPaletteSelect")).toBeVisible();
      await expect(page.locator("#lineNumbersSelect")).toHaveCount(0);
      await expect(page.locator("#codeOverflowSelect")).toHaveCount(0);
      await expect(page.locator(".settings-theme-preview-link")).toHaveCount(0);
      await page.locator('[data-settings-theme="dark"]').click();
      await page.locator("#darkPaletteSelect").selectOption("dracula");
      await expect(page.locator("html")).toHaveAttribute("data-crit-palette", "dracula");
      expect(await page.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue("--crit-bg-page").trim()))
        .toBe(await page.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue("--crit-palette-bg").trim()));
    } finally {
      await deleteReview(request, review.deleteToken);
    }
  });
});
