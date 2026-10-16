import { test, expect, Page } from "@playwright/test";
import { codeLine, createReview, deleteReview, loadReview, waitForCommentCard } from "./helpers";

const BASE_URL = `http://127.0.0.1:${process.env.CRIT_WEB_TEST_PORT || "4003"}`;

// The selection toolbar shows a Comment button above a mouse selection that
// `c` could comment on (crit's crit-selection-toolbar.js, vendored). It opens
// nothing by itself.

const GO = [
  "package main",
  "",
  "func check(key string) error {",
  '\tif key == "" {',
  '\t\treturn errors.New("invalid key")',
  "\t}",
  "\treturn nil",
  "}",
  "",
].join("\n");

const MD = "# Notes\n\nThe toolbar appears above a selection and comments on it like the c key.\n";

function toolbar(page: Page) {
  return page.locator(".crit-selection-toolbar");
}

// Drag across `text` inside `container` with the mouse (pointer events, as a
// reader would). Works in light DOM and inside Pierre's shadow root.
async function dragOverText(page: Page, container: ReturnType<Page["locator"]>, text: string) {
  await expect(async () => {
    await container.scrollIntoViewIfNeeded({ timeout: 2_000 });
    const pts = await container.evaluate((el, needle) => {
      const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
      let node: Node | null;
      while ((node = walker.nextNode())) {
        const at = node.textContent!.indexOf(needle);
        if (at < 0) continue;
        const point = (i: number) => {
          const r = document.createRange();
          r.setStart(node!, i);
          r.setEnd(node!, i + 1);
          const b = r.getBoundingClientRect();
          return { x: b.x + b.width / 2, y: b.y + b.height / 2 };
        };
        return { start: point(at), end: point(at + needle.length - 1) };
      }
      return null;
    }, text);
    expect(pts).toBeTruthy();
    await page.mouse.move(pts!.start.x - 2, pts!.start.y);
    await page.mouse.down();
    await page.mouse.move(pts!.end.x + 2, pts!.end.y, { steps: 5 });
    await page.mouse.up();
    await expect(toolbar(page)).toBeVisible({ timeout: 2_000 });
  }).toPass({ timeout: 15_000 });
}

test.describe("Selection toolbar", () => {
  let deleteToken: string;

  test.afterEach(async ({ request }) => {
    if (deleteToken) await deleteReview(request, deleteToken);
  });

  test("Comment on a document selection opens the form with the quote", async ({ page, request }) => {
    const review = await createReview(request, { files: [{ path: "notes.md", content: MD }] });
    deleteToken = review.deleteToken;
    await loadReview(page, review.token);

    const paragraph = page.locator(".line-block", { hasText: "The toolbar appears" }).locator(".line-content");
    await dragOverText(page, paragraph, "above a selection");

    // Selecting opens nothing and keeps the selection.
    await expect(page.locator(".comment-form")).toHaveCount(0);
    expect(await page.evaluate(() => window.getSelection()?.toString())).toContain("above a selection");
    await expect(toolbar(page).locator("kbd")).toHaveText("c");

    await toolbar(page).getByRole("button", { name: "Comment on selection" }).click();
    const textarea = page.locator(".comment-form textarea");
    await expect(textarea).toBeFocused();
    await expect(toolbar(page)).toBeHidden();
    await expect(page.locator("mark.quote-highlight")).toHaveText("above a selection");

    await textarea.fill("Toolbar comment");
    await textarea.press("Control+Enter");
    await waitForCommentCard(page, "Toolbar comment");
    await expect(page.locator("mark.quote-highlight")).toHaveText("above a selection");
  });

  test("Escape hides the toolbar and keeps the selection for c", async ({ page, request }) => {
    const review = await createReview(request, { files: [{ path: "notes.md", content: MD }] });
    deleteToken = review.deleteToken;
    await loadReview(page, review.token);

    const paragraph = page.locator(".line-block", { hasText: "The toolbar appears" }).locator(".line-content");
    await dragOverText(page, paragraph, "above a selection");
    await page.keyboard.press("Escape");
    await expect(toolbar(page)).toBeHidden();
    expect(await page.evaluate(() => window.getSelection()?.toString())).toContain("above a selection");

    await page.keyboard.press("c");
    await expect(page.locator(".comment-form textarea")).toBeVisible();
  });

  test("Comment on a code selection opens the line form with the quote", async ({ page, request }) => {
    const review = await createReview(request, { files: [{ path: "check.go", content: GO }] });
    deleteToken = review.deleteToken;
    await loadReview(page, review.token);

    await dragOverText(page, codeLine(page, "check.go", 5), "invalid key");
    await toolbar(page).getByRole("button", { name: "Comment on selection" }).click();
    await expect(page.locator(".comment-form-header")).toHaveText("Comment on Line 5");
    await page.locator(".comment-form textarea").fill("Quoted from the toolbar");
    await page.locator(".comment-form textarea").press("Control+Enter");
    await waitForCommentCard(page, "Quoted from the toolbar");
    await expect.poll(() => page.evaluate(() => {
      const ranges = [...(CSS.highlights.get("crit-quote") || [])] as Range[];
      return ranges.map((r) => r.toString());
    })).toContain("invalid key");
  });

  test("no toolbar when the review disallows comments", async ({ page, request }) => {
    const seeded = await (await request.post(`${BASE_URL}/api/test/seed-user`, { data: { name: "Toolbar Owner" } })).json();
    const bearer = seeded.token as string;
    const created = await request.post(`${BASE_URL}/api/reviews`, {
      headers: { Authorization: `Bearer ${bearer}` },
      data: { files: [{ path: "notes.md", content: MD }], comments: [] },
    });
    expect(created.status()).toBe(201);
    const { url, delete_token } = await created.json();
    deleteToken = delete_token;
    const token = (url as string).split("/r/")[1];
    const put = await request.put(`${BASE_URL}/api/reviews/${token}`, {
      headers: { Authorization: `Bearer ${bearer}` },
      data: { delete_token, files: [{ path: "notes.md", content: MD }], comments: [], review_round: 1, comment_policy: "disallowed" },
    });
    expect(put.status()).toBe(200);

    await loadReview(page, token);
    await expect(page.locator(".crit-page.crit-no-comments")).toHaveCount(1);
    const paragraph = page.locator(".line-block", { hasText: "The toolbar appears" }).locator(".line-content");
    const box = (await paragraph.boundingBox())!;
    await page.mouse.move(box.x + 20, box.y + box.height / 2);
    await page.mouse.down();
    await page.mouse.move(box.x + 200, box.y + box.height / 2, { steps: 5 });
    await page.mouse.up();
    expect(await page.evaluate(() => window.getSelection()?.toString().trim())).toBeTruthy();
    // The toolbar would show on the frame after pointerup; wait past it.
    await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve))));
    await expect(toolbar(page)).toBeHidden();
  });
});
