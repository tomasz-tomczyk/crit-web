import { test, expect, type Page } from "@playwright/test";
import {
  createReview,
  deleteReview,
  loadReview,
  waitForCommentCard,
} from "./helpers";

/**
 * Add a comment via the UI and wait for it to appear.
 * Uses a stable identifier to wait for the card, since markdown
 * rendering transforms the raw text (e.g. **bold** becomes <strong>).
 */
async function addCommentViaUI(page: Page, body: string, waitText?: string) {
  const gutter = page.locator(".line-gutter").first();
  await gutter.click();

  const textarea = page.locator(".comment-form textarea");
  await expect(textarea).toBeVisible({ timeout: 5_000 });
  await textarea.fill(body);
  await textarea.press("Control+Enter");

  // Wait for a comment card to appear. Use waitText if provided,
  // otherwise wait for any card.
  if (waitText) {
    await waitForCommentCard(page, waitText);
  } else {
    await expect(page.locator(".comment-card").first()).toBeVisible({
      timeout: 10_000,
    });
  }
}

test.describe("Comment Markdown Rendering", () => {
  let token: string;
  let deleteToken: string;

  test.beforeEach(async ({ request }) => {
    const review = await createReview(request);
    token = review.token;
    deleteToken = review.deleteToken;
  });

  test.afterEach(async ({ request }) => {
    await deleteReview(request, deleteToken);
  });

  test("renders bold text as <strong>", async ({ page }) => {
    await loadReview(page, token);
    await addCommentViaUI(page, "This is **bold text** here", "bold text");

    const body = page.locator(".comment-card .comment-body");
    await expect(body.locator("strong")).toHaveText("bold text");
  });

  test("renders inline code as <code>", async ({ page }) => {
    await loadReview(page, token);
    await addCommentViaUI(page, "Use `inline code` here", "inline code");

    const body = page.locator(".comment-card .comment-body");
    await expect(body.locator("code")).toHaveText("inline code");
  });

  test("renders links as <a> tags", async ({ page }) => {
    await loadReview(page, token);
    await addCommentViaUI(page, "See [the docs](https://example.com) for details", "the docs");

    const body = page.locator(".comment-card .comment-body");
    const link = body.locator("a");
    await expect(link).toHaveText("the docs");
    await expect(link).toHaveAttribute("href", "https://example.com");
  });

  test("auto-links bare URLs", async ({ page }) => {
    await loadReview(page, token);
    await addCommentViaUI(page, "Visit https://example.com for more");

    const body = page.locator(".comment-card .comment-body");
    const link = body.locator("a");
    await expect(link).toBeVisible();
    await expect(link).toHaveAttribute("href", "https://example.com");
  });

  test("renders fenced code blocks with syntax highlighting", async ({
    page,
  }) => {
    await loadReview(page, token);
    await addCommentViaUI(
      page,
      'Check this:\n```javascript\nconsole.log("hello")\n```'
    );

    const body = page.locator(".comment-card .comment-body");
    const codeBlock = body.locator("pre code");
    await expect(codeBlock).toBeVisible();

    // hljs should produce spans with hljs-* classes
    await expect(
      codeBlock.locator('span[class^="hljs-"]').first()
    ).toBeVisible();
  });

  test("renders markdown with bold, code, and link combined", async ({
    page,
  }) => {
    await loadReview(page, token);
    await addCommentViaUI(
      page,
      "**bold text** and `inline code` and [a link](https://example.com)",
      "bold text"
    );

    const body = page.locator(".comment-card .comment-body");
    await expect(body.locator("strong")).toHaveText("bold text");
    await expect(body.locator("code")).toHaveText("inline code");
    const link = body.locator("a");
    await expect(link).toHaveText("a link");
    await expect(link).toHaveAttribute("href", "https://example.com");
  });
});
