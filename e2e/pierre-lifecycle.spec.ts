import { test, expect } from "@playwright/test";
import {
  addCommentViaUI,
  codeLine,
  createReview,
  deleteReview,
  loadReview,
  openCodeLineComment,
  waitForCommentCard,
} from "./helpers";

const files = [{ path: "server.go", content: "package main\n\nfunc main() {}\n" }];

test("comment deltas received while Pierre loads survive initialization", async ({ page, context, request }) => {
  const review = await createReview(request, { files });
  const peer = await context.newPage();
  let release!: () => void;
  const blocked = new Promise<void>(resolve => { release = resolve; });
  let loading!: () => void;
  const started = new Promise<void>(resolve => { loading = resolve; });
  try {
    await loadReview(peer, review.token);
    await page.route("**/pierre/pierre-diffs.js", async route => {
      loading();
      await blocked;
      await route.continue();
    });
    await page.goto(`/r/${review.token}`);
    await started;
    await addCommentViaUI(peer, "Arrived during renderer startup");
    await expect(page.locator("#commentCountNumber")).toHaveText("1");
    release();
    await expect(codeLine(page, "server.go", 1)).toBeVisible();
    await waitForCommentCard(page, "Arrived during renderer startup");
    await expect(page.locator("#commentCountNumber")).toHaveText("1");
  } finally {
    release();
    await peer.close();
    await deleteReview(request, review.deleteToken);
  }
});

test("another code comment preserves an inline edit draft, caret and focus", async ({ page, context, request }) => {
  const review = await createReview(request, { files });
  const peer = await context.newPage();
  try {
    await loadReview(page, review.token);
    await addCommentViaUI(page, "Earlier thread");
    await addCommentViaUI(page, "Original comment", { lineIndex: 2 });
    await loadReview(peer, review.token);
    await page.locator('.comment-card').filter({ hasText: "Original comment" }).locator('button[title="Edit"]').click();
    const textarea = page.locator(".comment-form textarea");
    await textarea.fill("Unsaved edit draft");
    await textarea.evaluate((el: HTMLTextAreaElement) => el.setSelectionRange(3, 7));
    await openCodeLineComment(peer, "server.go", 3);
    await peer.locator(".comment-form textarea").fill("Another thread");
    await peer.locator(".comment-form textarea").press("Control+Enter");
    await waitForCommentCard(page, "Another thread");
    await expect(textarea).toHaveValue("Unsaved edit draft");
    await expect(textarea).toBeFocused();
    expect(await textarea.evaluate((el: HTMLTextAreaElement) => [el.selectionStart, el.selectionEnd])).toEqual([3, 7]);
    await peer.locator('.comment-card').filter({ hasText: "Earlier thread" }).locator('.delete-btn').click();
    await expect(page.locator('.comment-card').filter({ hasText: "Earlier thread" })).toHaveCount(0);
    await expect(textarea).toHaveValue("Unsaved edit draft");
    await expect(textarea).toBeFocused();
    expect(await textarea.evaluate((el: HTMLTextAreaElement) => [el.selectionStart, el.selectionEnd])).toEqual([3, 7]);
    await textarea.press("Control+Enter");
    await waitForCommentCard(peer, "Unsaved edit draft");
  } finally {
    await peer.close();
    await deleteReview(request, review.deleteToken);
  }
});

test("cross-tab theme changes update Pierre alongside review chrome", async ({ page, context, request }) => {
  const review = await createReview(request, { files });
  const peer = await context.newPage();
  try {
    await page.addInitScript(() => localStorage.setItem("phx:theme", "dark"));
    await loadReview(page, review.token);
    const pre = page.locator(".crit-code-file pre").first();
    await expect(pre).toHaveCSS("background-color", "rgb(26, 27, 38)");
    await peer.goto("/themes");
    await peer.evaluate(() => localStorage.setItem("phx:theme", "light"));
    await expect(page.locator("html")).toHaveAttribute("data-theme", "light");
    await expect(pre).toHaveCSS("background-color", "rgb(255, 255, 255)");
    await peer.evaluate(() => localStorage.setItem("phx:theme", "dark"));
    await expect(pre).toHaveCSS("background-color", "rgb(26, 27, 38)");
  } finally {
    await peer.close();
    await deleteReview(request, review.deleteToken);
  }
});
