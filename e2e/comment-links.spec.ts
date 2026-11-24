import { test, expect, type Page } from "@playwright/test";
import { createReview, deleteReview, loadReview } from "./helpers";

// Links to comments (crit #1218). A link is the review URL with the
// comment's crit id (external_id) as the fragment, so a link copied locally
// or written by an agent also works on the share. Matches crit's
// test/e2e/tests/comment-links.spec.ts.

const MD = Array.from({ length: 80 }, (_, i) => `Line ${i + 1}`).join("\n") + "\n";
const GO = "package main\n\n" +
  Array.from({ length: 60 }, (_, i) => `func f${i}() {}`).join("\n") + "\n";

const TARGET_ID = "c_aa11bb";
const CODE_TARGET_ID = "c_cc22dd";

function card(page: Page, text: string) {
  return page.locator("#document-renderer .comment-card").filter({ hasText: text });
}

// Wheel up until `target` is in view.
async function scrollBackTo(page: Page, target: ReturnType<typeof card>) {
  await page.mouse.move(640, 400);
  await expect(async () => {
    await page.mouse.wheel(0, -600);
    await expect(target).toBeInViewport({ timeout: 200 });
  }).toPass();
}

// A fresh page load at /r/<token>#<id>, not a hash change on an open page.
async function openLink(page: Page, token: string, id: string) {
  await page.goto("about:blank");
  await page.goto(`/r/${token}#${id}`);
}

test.describe("Comment links", () => {
  let token: string;
  let deleteToken: string;

  test.beforeEach(async ({ request }) => {
    const review = await createReview(request, {
      files: [
        { path: "notes.md", content: MD },
        { path: "main.go", content: GO },
      ],
      comments: [
        { file: "notes.md", start_line: 2, end_line: 2, external_id: "c_ee33ff",
          body: "Same problem as [the main comment](#c_aa11bb), and see c_cc22dd." },
        { file: "notes.md", start_line: 75, end_line: 75, external_id: TARGET_ID,
          body: "The main explanation" },
        { file: "main.go", start_line: 58, end_line: 58, external_id: CODE_TARGET_ID,
          body: "A comment in a code file" },
        // Written on crit-web, so it has no crit id: its link uses the server id.
        { file: "notes.md", start_line: 50, end_line: 50, body: "A comment without a crit id" },
      ],
    });
    token = review.token;
    deleteToken = review.deleteToken;
  });

  test.afterEach(async ({ request }) => {
    await deleteReview(request, deleteToken);
  });

  test("opening a link by crit id scrolls to the card", async ({ page }) => {
    await openLink(page, token, TARGET_ID);
    await expect(card(page, "The main explanation")).toBeInViewport();
  });

  test("opening a link to a code-file comment waits for the card", async ({ page }) => {
    await openLink(page, token, CODE_TARGET_ID);
    await expect(card(page, "A comment in a code file")).toBeInViewport();
  });

  test("the link button copies a URL with the crit id", async ({ page, context }) => {
    await context.grantPermissions(["clipboard-read", "clipboard-write"]);
    await loadReview(page, token);
    const target = card(page, "The main explanation");
    await target.scrollIntoViewIfNeeded();
    const btn = target.locator(".comment-link-btn");
    await expect(btn).toHaveAttribute("aria-label", "Copy link to comment");
    await btn.click();

    await expect(btn).toHaveClass(/comment-link-copied/);
    await expect(page).toHaveURL(new RegExp(`#${TARGET_ID}$`));
    await expect.poll(() => page.evaluate(() => navigator.clipboard.readText()))
      .toBe(page.url());
  });

  test("a markdown link and a ref chip in a comment jump to their comments", async ({ page }) => {
    await loadReview(page, token);
    const linker = card(page, "Same problem as");

    const link = linker.locator(".comment-body a", { hasText: "the main comment" });
    await link.click();
    await expect(card(page, "The main explanation")).toBeInViewport();

    // Clicking the same link again still jumps: the hash doesn't change, so
    // this needs the click handler, not hashchange. Scroll back the way a
    // reader would: wheel input also stops the jump's re-centring.
    await scrollBackTo(page, linker);
    await expect(card(page, "The main explanation")).not.toBeInViewport();
    await link.click();
    await expect(card(page, "The main explanation")).toBeInViewport();

    await scrollBackTo(page, linker);
    await linker.locator(".comment-ref", { hasText: CODE_TARGET_ID }).click();
    await expect(card(page, "A comment in a code file")).toBeInViewport();
  });

  test("a comment without a crit id links by its server id", async ({ page, context }) => {
    await context.grantPermissions(["clipboard-read", "clipboard-write"]);
    await loadReview(page, token);
    const target = card(page, "A comment without a crit id");
    await target.scrollIntoViewIfNeeded();
    const btn = target.locator(".comment-link-btn");
    await btn.click();
    await expect(btn).toHaveClass(/comment-link-copied/);
    const url = await page.evaluate(() => navigator.clipboard.readText());
    const id = new URL(url).hash.slice(1);
    expect(id).not.toMatch(/^c_/);
    expect(id).toBe(await target.getAttribute("data-comment-id"));

    await openLink(page, token, id);
    await expect(card(page, "A comment without a crit id")).toBeInViewport();
  });
});
