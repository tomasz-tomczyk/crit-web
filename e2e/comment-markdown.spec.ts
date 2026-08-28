import { test, expect, type Locator } from "@playwright/test";
import {
  createReview,
  deleteReview,
  loadReview,
  addCommentViaUI,
} from "./helpers";

const TABLE_MD = [
  "| Field | Type | Notes |",
  "| --- | --- | --- |",
  "| id | string | primary key |",
  "| name | string | display name |",
].join("\n");

async function expectAllTableCellBorders(table: Locator) {
  const cells = table.locator("th, td");
  await expect(cells).not.toHaveCount(0);
  for (const cell of await cells.all()) {
    for (const side of ["top", "right", "bottom", "left"] as const) {
      await expect(cell).toHaveCSS(`border-${side}-style`, "solid");
      await expect(cell).toHaveCSS(`border-${side}-width`, "1px");
    }
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
    await addCommentViaUI(page, "This is **bold text** here", { waitText: "bold text" });

    const body = page.locator(".comment-card .comment-body");
    await expect(body.locator("strong")).toHaveText("bold text");
  });

  test("renders inline code as <code>", async ({ page }) => {
    await loadReview(page, token);
    await addCommentViaUI(page, "Use `inline code` here", { waitText: "inline code" });

    const body = page.locator(".comment-card .comment-body");
    await expect(body.locator("code")).toHaveText("inline code");
  });

  test("renders links as <a> tags", async ({ page }) => {
    await loadReview(page, token);
    await addCommentViaUI(page, "See [the docs](https://example.com) for details", { waitText: "the docs" });

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

  test("keeps typographer replacements literal", async ({ page }) => {
    await loadReview(page, token);
    await addCommentViaUI(page, "Choose (c), (r), or (tm)");

    await expect(page.locator(".comment-card .comment-body")).toHaveText(
      "Choose (c), (r), or (tm)",
    );
  });

  test("renders safe HTML while stripping unsafe markup from comments", async ({
    page,
  }) => {
    await loadReview(page, token);
    await addCommentViaUI(
      page,
      '<details open><summary>More context</summary>Safe content</details><!-- agent metadata --><img src="https://example.com/safe.png" srcset="javascript:alert(1) 1x, https://example.com/safe.png 2x" onerror="window.__commentXss = true"><a href="javascript:alert(1)">unsafe</a>',
      { waitText: "Safe content" },
    );

    const body = page.locator(".comment-card .comment-body");
    await expect(body.locator("details[open] > summary")).toHaveText("More context");
    await expect(body).toContainText("Safe content");
    await expect(body.locator("script, [onerror], [onclick]")).toHaveCount(0);
    await expect(body.locator('a[href^="javascript:"]')).toHaveCount(0);
    await expect(body.locator('img[srcset*="javascript:"]')).toHaveCount(0);
    await expect(
      await body.evaluate((el) => {
        const walker = document.createTreeWalker(el, NodeFilter.SHOW_COMMENT);
        return walker.nextNode();
      }),
    ).toBeNull();
  });

  test("renders fenced code blocks with syntax highlighting", async ({
    page,
  }) => {
    await loadReview(page, token);
    await addCommentViaUI(
      page,
      'Check this:\n```javascript\nconsole.log("hello")\n```',
      { waitText: "Check this" }
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
      { waitText: "bold text" }
    );

    const body = page.locator(".comment-card .comment-body");
    await expect(body.locator("strong")).toHaveText("bold text");
    await expect(body.locator("code")).toHaveText("inline code");
    const link = body.locator("a");
    await expect(link).toHaveText("a link");
    await expect(link).toHaveAttribute("href", "https://example.com");
  });

  test("draws a border on every cell of a markdown table in a comment", async ({
    page,
  }) => {
    await loadReview(page, token);
    await addCommentViaUI(page, TABLE_MD, { waitText: "primary key" });

    const table = page.locator(".comment-card .comment-body table");
    await expect(table).toBeVisible();
    await expect(table).toHaveCSS("border-collapse", "collapse");
    await expect(table.locator("th")).toHaveCount(3);
    await expect(table.locator("tbody tr")).toHaveCount(2);

    await expectAllTableCellBorders(table);
  });

  test("draws a border on every cell of a markdown table in a reply", async ({
    page,
  }) => {
    await loadReview(page, token);
    await addCommentViaUI(page, "Which fields does this cover?", {
      waitText: "Which fields",
    });

    const card = page.locator(".comment-card").filter({
      hasText: "Which fields does this cover?",
    });
    await card.locator(".reply-input").click();
    const replyTextarea = card.locator(".reply-textarea");
    await expect(replyTextarea).toBeVisible({ timeout: 5_000 });
    await replyTextarea.fill(TABLE_MD);
    await card.locator(".reply-form-buttons .btn-primary").click();

    const table = card.locator(".reply-body table");
    await expect(table).toBeVisible();
    await expect(table.locator("th")).toHaveCount(3);
    await expectAllTableCellBorders(table);
  });
});
