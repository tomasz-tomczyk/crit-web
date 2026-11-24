import { test, expect } from "@playwright/test";
import { createReview, deleteReview, loadReview } from "./helpers";

// A comment on selected text and its highlighted quote link to each other in
// the rendered document (crit: test/e2e/tests/quote-links.spec.ts). The
// quoted comment spans lines 3-40, so its card sits far below the quote.
const filler = Array.from({ length: 18 }, (_, i) => `\nParagraph ${i + 1}, filler text to push the card down the page.`).join("\n");
const CONTENT = `# Plan\n\nWe will rotate the API key every 30 days.\n${filler}\n\nThe deploy script runs after tests pass.\n`;
const LAST_LINE = CONTENT.split("\n").length - 1;

test.describe("Quoted text and its comment", () => {
  let token: string;
  let deleteToken: string;

  test.beforeEach(async ({ request }) => {
    ({ token, deleteToken } = await createReview(request, {
      files: [{ path: "plan.md", content: CONTENT }],
      comments: [
        { file: "plan.md", start_line: 3, end_line: 40, body: "Which keys?", quote: "API key" },
        { file: "plan.md", start_line: LAST_LINE, end_line: LAST_LINE, body: "Whole-line comment" },
      ],
    }));
  });

  test.afterEach(async ({ request }) => {
    await deleteReview(request, deleteToken);
  });

  test("the highlight goes to its comment, and the comment label goes back to the text", async ({ page }) => {
    await loadReview(page, token);
    const mark = page.locator("mark.quote-highlight", { hasText: "API key" });
    const quotedCard = page.locator(".comment-card:not(#commentsPanel .comment-card)", { hasText: "Which keys?" });
    await expect(quotedCard).not.toBeInViewport();

    await mark.click();
    await expect(quotedCard).toBeInViewport();

    const label = quotedCard.locator(".comment-line-ref");
    await expect(label).toHaveAttribute("role", "link");
    await label.click();
    await expect(mark).toBeInViewport();

    await quotedCard.scrollIntoViewIfNeeded();
    await label.focus();
    await page.keyboard.press("Enter");
    await expect(mark).toBeInViewport();

    // A whole-line comment's label is plain text.
    const plainCard = page.locator(".comment-card:not(#commentsPanel .comment-card)", { hasText: "Whole-line comment" });
    await expect(plainCard.locator(".comment-line-ref")).not.toHaveAttribute("role", "link");
  });

  test("double-clicking inside a highlight selects text and does not jump", async ({ page }) => {
    await loadReview(page, token);
    const mark = page.locator("mark.quote-highlight", { hasText: "API key" });
    const quotedCard = page.locator(".comment-card:not(#commentsPanel .comment-card)", { hasText: "Which keys?" });

    await mark.dblclick();
    expect(await page.evaluate(() => window.getSelection()!.toString().length)).toBeGreaterThan(0);
    // This checks that something does not happen: wait out the deferred jump.
    await page.waitForTimeout(1000);
    await expect(quotedCard).not.toBeInViewport();
  });
});
