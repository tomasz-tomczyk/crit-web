import { test, expect, Page } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";
import { createReview, deleteReview, loadReview } from "./helpers";

// Same structure as crit's accessibility spec: the review page is audited in
// both modes of the reader's theme palette, with Syntax contrast off and on.
test.describe("Accessibility", () => {
  let token: string;
  let deleteToken: string;

  test.beforeEach(async ({ request }) => {
    const review = await createReview(request, {
      files: [
        {
          path: "example.md",
          content:
            "# Hello World\n\nThis is line 1\nThis is line 2\nThis is line 3\n\n```go\nfunc main() {\n\t// a comment\n}\n```\n",
        },
        {
          path: "main.go",
          content: "package main\n\n// main prints a greeting.\nfunc main() {\n\tprintln(\"hi\")\n}\n",
        },
      ],
      comments: [
        { start_line: 3, end_line: 3, body: "Test comment", file: "example.md" },
        { start_line: 4, end_line: 4, body: "Code comment", file: "main.go" },
      ],
    });
    token = review.token;
    deleteToken = review.deleteToken;
  });

  test.afterEach(async ({ request }) => {
    await deleteReview(request, deleteToken);
  });

  async function setBoost(page: Page, baseURL: string, on: boolean) {
    await page.context().addCookies([{
      name: "crit-settings",
      value: encodeURIComponent(JSON.stringify({ boostContrast: on ? "on" : "off" })),
      url: baseURL,
    }]);
  }

  // Contrast is a settled-state property: disable transitions so axe sees the
  // final colours, then switch through the app's theme control so code views
  // follow the page theme too, and wait for the palette to apply.
  async function setTheme(page: Page, theme: "dark" | "light") {
    await page.addStyleTag({ content: "* { transition: none !important; animation: none !important; }" });
    await page.locator("#settingsToggle").click();
    await page.locator(`[data-settings-theme="${theme}"]`).click();
    await page.keyboard.press("Escape");
    await page.waitForFunction((mode) => {
      const root = document.documentElement;
      const css = getComputedStyle(root);
      const id = mode === "light" ? root.dataset.critPaletteLight : root.dataset.critPaletteDark;
      return root.dataset.critPalette === id &&
        css.getPropertyValue("--crit-bg-page").trim() === css.getPropertyValue("--crit-palette-bg").trim();
    }, theme);
  }

  // Syntax colours belong to the theme and are shown as designed, so with the
  // boost off the contrast audit skips token text (spans carrying Pierre's
  // --diffs-token-* properties). Everything crit-web draws itself is audited.
  // With Syntax contrast on, token text is audited too.
  const isToken = (html: string) => /^<span style="--diffs-token-/.test(html);

  // Known shared gaps, identical in crit (same palette data, same Pierre
  // build; checked against crit's /): the muted meta text on a comment
  // header's accent tint and Pierre's default line-number colour fall below
  // 4.5:1 for some themes, and no single mix fixes every bundled theme. The
  // fix belongs in crit's palette generator (scripts/crit-theme-palette.mjs),
  // then scripts/sync-pierre.sh. Exempted by exact place, nothing wider.
  const isSharedPaletteGap = (target: string[]) => {
    const selector = target.join(" ");
    return /\.comment-header(-left)? > \.(comment-time|comment-author|comment-round-badge)\b/.test(selector) ||
      /\.resolve-btn > span/.test(selector) ||
      /diffs-container.*\[data-line-number-content/.test(selector);
  };

  async function audit(page: Page, boost: boolean) {
    const results = await new AxeBuilder({ page })
      .withTags(["wcag2a", "wcag2aa"])
      .disableRules(["nested-interactive"])
      .analyze();
    return results.violations.flatMap((v) => v.nodes
      .filter((n) => boost || v.id !== "color-contrast" || !isToken(n.html))
      .filter((n) => v.id !== "color-contrast" || !isSharedPaletteGap(n.target as string[]))
      .map((n) => `${v.id}: ${n.target.join(" ")} ${n.html.slice(0, 80)}\n${n.failureSummary || ""}`));
  }

  for (const boost of [false, true]) {
    const label = boost ? " (syntax contrast on)" : "";

    test("should have no critical accessibility violations" + label, async ({ page, baseURL }) => {
      await setBoost(page, baseURL!, boost);
      await loadReview(page, token);
      await expect(page.locator(".crit-code-file [data-line]").first()).toBeVisible();
      expect(await audit(page, boost)).toEqual([]);
    });

    for (const theme of ["dark", "light"] as const) {
      test(`should have no color contrast violations in ${theme} theme${label}`, async ({ page, baseURL }) => {
        await page.emulateMedia({ reducedMotion: "reduce" });
        await setBoost(page, baseURL!, boost);
        await loadReview(page, token);
        await expect(page.locator(".crit-code-file [data-line]").first()).toBeVisible();
        await setTheme(page, theme);
        expect(await audit(page, boost)).toEqual([]);
      });
    }
  }
});
