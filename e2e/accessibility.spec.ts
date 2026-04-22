import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";
import { createReview, deleteReview, loadReview } from "./helpers";

test.describe("Accessibility", () => {
  let token: string;
  let deleteToken: string;

  test.beforeEach(async ({ request }) => {
    const review = await createReview(request, {
      files: [
        {
          path: "example.md",
          content:
            "# Hello World\n\nThis is line 1\nThis is line 2\nThis is line 3\n",
        },
      ],
      comments: [
        { start_line: 3, end_line: 3, body: "Test comment" },
      ],
    });
    token = review.token;
    deleteToken = review.deleteToken;
  });

  test.afterEach(async ({ request }) => {
    await deleteReview(request, deleteToken);
  });

  test("should have no critical accessibility violations", async ({ page }) => {
    await loadReview(page, token);


    const results = await new AxeBuilder({ page })
      .withTags(["wcag2a", "wcag2aa"])
      .disableRules(["nested-interactive", "link-in-text-block", "button-name"])
      .analyze();

    const violations = results.violations.map((v) => ({
      id: v.id,
      impact: v.impact,
      description: v.description,
      nodes: v.nodes.length,
    }));

    expect(violations).toEqual([]);
  });

  test("should have no color contrast violations in dark theme", async ({
    page,
  }) => {
    await loadReview(page, token);

    await page.evaluate(() =>
      document.documentElement.setAttribute("data-theme", "dark")
    );
    await page.waitForFunction(() => {
      const bg = getComputedStyle(document.documentElement)
        .getPropertyValue("--crit-bg-page")
        .trim();
      return bg === "#0e0f13";
    });

    const results = await new AxeBuilder({ page })
      .withTags(["wcag2a", "wcag2aa"])
      .disableRules(["nested-interactive"])
      .analyze();

    const contrast = results.violations.find(
      (v) => v.id === "color-contrast"
    );
    expect(contrast?.nodes ?? []).toEqual([]);
  });

  test("should have no color contrast violations in light theme", async ({
    page,
  }) => {
    await loadReview(page, token);

    await page.evaluate(() =>
      document.documentElement.setAttribute("data-theme", "light")
    );
    await page.waitForFunction(() => {
      const bg = getComputedStyle(document.documentElement)
        .getPropertyValue("--crit-bg-page")
        .trim();
      return bg === "#ffffff";
    });

    const results = await new AxeBuilder({ page })
      .withTags(["wcag2a", "wcag2aa"])
      .disableRules(["nested-interactive"])
      .analyze();

    const contrast = results.violations.find(
      (v) => v.id === "color-contrast"
    );
    expect(contrast?.nodes ?? []).toEqual([]);
  });
});
