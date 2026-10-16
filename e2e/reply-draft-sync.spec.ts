import { test, expect, type Browser, type Page } from "@playwright/test";
import {
  addCommentViaUI,
  codeFile,
  createReview,
  deleteReview,
  loadReview,
  openCodeLineComment,
  seedComment,
  waitForCommentCard,
} from "./helpers";

// A reply being typed survives another reviewer's comment arriving over
// PubSub: the draft text stays and focus and caret go back to the reply
// textarea (crit: cli-comment.spec.ts, #1051). In a code file the new comment
// rebuilds the file's Pierre annotations, thread cards included.

const GO = [
  "package main",
  "",
  'import "fmt"',
  "",
  "func main() {",
  '\tfmt.Println("hello")',
  "}",
  "",
].join("\n");

async function openSecondReviewer(browser: Browser, token: string) {
  const context = await browser.newContext();
  const page = await context.newPage();
  await loadReview(page, token);
  return { context, page };
}

async function startReply(page: Page, commentBody: string) {
  const card = page.locator(".comment-card").filter({ hasText: commentBody });
  await card.locator(".reply-input").click();
  const replyTextarea = card.locator(".reply-textarea");
  await expect(replyTextarea).toBeFocused();
  await page.keyboard.type("draft reply");
  return replyTextarea;
}

test.describe("Reply drafts across comment sync", () => {
  let deleteToken: string;

  test.afterEach(async ({ request }) => {
    if (deleteToken) await deleteReview(request, deleteToken);
  });

  test("a reply being typed in a markdown file keeps text and focus when another comment arrives", async ({
    page,
    browser,
    request,
  }) => {
    const review = await createReview(request);
    deleteToken = review.deleteToken;
    await seedComment(request, review.token, { body: "Reviewer comment", startLine: 1 });

    await loadReview(page, review.token);
    await waitForCommentCard(page, "Reviewer comment");
    const replyTextarea = await startReply(page, "Reviewer comment");

    const other = await openSecondReviewer(browser, review.token);
    try {
      await addCommentViaUI(other.page, "Comment from another reviewer", { lineIndex: 2 });
    } finally {
      await other.context.close();
    }
    await waitForCommentCard(page, "Comment from another reviewer");

    await expect(replyTextarea).toBeFocused();
    await page.keyboard.type(" continues");
    await expect(replyTextarea).toHaveValue("draft reply continues");
  });

  // The review conversation is rebuilt on every comment change, so this one
  // loses the draft without the fix even in a markdown review.
  test("a reply being typed on a review-level comment keeps text and focus when another comment arrives", async ({
    page,
    browser,
    request,
  }) => {
    const review = await createReview(request);
    deleteToken = review.deleteToken;
    await seedComment(request, review.token, { body: "Review-level comment", scope: "review" });

    await loadReview(page, review.token);
    await expect(
      page.locator("#reviewConversation .comment-card").filter({ hasText: "Review-level comment" })
    ).toBeVisible({ timeout: 10_000 });
    const replyTextarea = await startReply(page, "Review-level comment");

    const other = await openSecondReviewer(browser, review.token);
    try {
      await addCommentViaUI(other.page, "Comment from another reviewer", { lineIndex: 2 });
    } finally {
      await other.context.close();
    }
    await waitForCommentCard(page, "Comment from another reviewer");

    await expect(replyTextarea).toBeFocused();
    await page.keyboard.type(" continues");
    await expect(replyTextarea).toHaveValue("draft reply continues");
  });

  test("a reply being typed in a code file keeps text and focus when another comment arrives", async ({
    page,
    browser,
    request,
  }) => {
    const review = await createReview(request, {
      files: [
        { path: "main.go", content: GO },
        { path: "notes.md", content: "# Notes\n\nSome prose.\n" },
      ],
    });
    deleteToken = review.deleteToken;
    await seedComment(request, review.token, { body: "Reviewer comment", file: "main.go", startLine: 1 });

    await loadReview(page, review.token);
    const thread = codeFile(page, "main.go").locator(".comment-card").filter({ hasText: "Reviewer comment" });
    await expect(thread).toBeVisible({ timeout: 10_000 });
    const replyTextarea = await startReply(page, "Reviewer comment");
    // Caret mid-draft, so the restore has to keep the selection, not just focus.
    await replyTextarea.evaluate((el: HTMLTextAreaElement) => el.setSelectionRange(5, 5));

    const other = await openSecondReviewer(browser, review.token);
    try {
      await openCodeLineComment(other.page, "main.go", 5);
      const form = other.page.locator(".comment-form textarea");
      await form.fill("Comment from another reviewer");
      await form.press("Control+Enter");
      await waitForCommentCard(other.page, "Comment from another reviewer");
    } finally {
      await other.context.close();
    }
    await expect(
      codeFile(page, "main.go").locator(".comment-card").filter({ hasText: "Comment from another reviewer" })
    ).toBeVisible({ timeout: 10_000 });

    await expect(replyTextarea).toBeFocused();
    await expect(replyTextarea).toHaveValue("draft reply");
    await page.keyboard.type("X");
    await expect(replyTextarea).toHaveValue("draftX reply");
  });
});
