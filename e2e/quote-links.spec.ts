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

  test.describe("in a code file", () => {
    // Pierre paints the quote as a CSS Custom Highlight range in its shadow
    // root, so there is no element to click: the page hit-tests the range.
    const CODE = ["package main", "", "func rotateKey() {"]
      .concat(Array.from({ length: 36 }, (_, i) => `\t// step ${i + 1}`), ["}", ""]).join("\n");
    let codeToken: string;
    let codeDeleteToken: string;

    test.beforeEach(async ({ request }) => {
      ({ token: codeToken, deleteToken: codeDeleteToken } = await createReview(request, {
        files: [{ path: "keys.go", content: CODE }],
        comments: [{ file: "keys.go", start_line: 3, end_line: 40, body: "Which keys?", quote: "rotateKey" }],
      }));
    });

    test.afterEach(async ({ request }) => {
      await deleteReview(request, codeDeleteToken);
    });

    test("the quote goes to its comment, and the comment label goes back to the quote", async ({ page }) => {
      await loadReview(page, codeToken);
      const card = page.locator(".comment-card:not(#commentsPanel .comment-card)", { hasText: "Which keys?" });
      const quotePoint = () => page.evaluate(() => {
        const range = [...(CSS.highlights.get("crit-quote") || [])][0] as Range | undefined;
        const box = range && range.getClientRects()[0];
        return box && box.width > 0 ? { x: box.x + box.width / 2, y: box.y + box.height / 2 } : null;
      });
      const flash = () => page.evaluate(() => [...(CSS.highlights.get("crit-quote-flash") || [])].map(r => r.toString()));

      await expect.poll(quotePoint).not.toBeNull();
      await expect(card).not.toBeInViewport();
      const point = (await quotePoint())!;
      await page.mouse.move(point.x, point.y);
      await expect(page.locator("diffs-container[data-crit-quote-hover]")).toHaveCount(1);
      await page.mouse.click(point.x, point.y);
      await expect(card).toBeInViewport();

      const label = card.locator(".comment-line-ref");
      await expect(label).toHaveAttribute("role", "link");
      await label.click();
      await expect.poll(flash).toEqual(["rotateKey"]);
      // The smooth scroll brings the quote back on screen.
      const height = page.viewportSize()!.height;
      await expect.poll(async () => {
        const back = await quotePoint();
        return !!back && back.y > 0 && back.y < height;
      }).toBe(true);
    });
  });
});
