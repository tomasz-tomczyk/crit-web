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
// reader would), left to right or `backwards`. Works in light DOM and inside
// Pierre's shadow root.
async function dragOverText(page: Page, container: ReturnType<Page["locator"]>, text: string, backwards = false) {
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
    const [from, to] = backwards
      ? [{ x: pts!.end.x + 2, y: pts!.end.y }, { x: pts!.start.x - 2, y: pts!.start.y }]
      : [{ x: pts!.start.x - 2, y: pts!.start.y }, { x: pts!.end.x + 2, y: pts!.end.y }];
    await page.evaluate(() => window.getSelection()?.removeAllRanges());
    await page.mouse.move(from.x, from.y);
    await page.mouse.down();
    await page.mouse.move(to.x, to.y, { steps: 5 });
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
    await expect(toolbar(page).getByRole("button", { name: "Comment on selection" }).locator("kbd")).toHaveText("c");

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

// Pinned comment templates (crit's crit-comment-templates.js, vendored) sit in
// the toolbar before Comment; Settings > Selection toolbar turns the bar on or
// off and, under Advanced, places it, styles Comment and hides its shortcuts or
// templates, in the same crit-settings keys as crit.

async function setReviewSetting(page: Page, key: string, value: unknown) {
  await page.evaluate(([k, v]) => {
    const match = document.cookie.match(/(?:^|;\s*)crit-settings=([^;]*)/);
    const settings = match ? JSON.parse(decodeURIComponent(match[1])) : {};
    settings[k as string] = v;
    document.cookie = "crit-settings=" + encodeURIComponent(JSON.stringify(settings)) + "; path=/; SameSite=Lax";
  }, [key, value] as const);
}

test.describe("Selection toolbar templates", () => {
  let deleteToken: string;

  test.beforeEach(async ({ page, request }) => {
    const review = await createReview(request, { files: [{ path: "notes.md", content: MD }] });
    deleteToken = review.deleteToken;
    await page.goto("/");
    await page.evaluate(() => {
      localStorage.removeItem("crit-templates");
      localStorage.removeItem("crit-template-meta");
    });
    await loadReview(page, review.token);
  });

  test.afterEach(async ({ request }) => {
    if (deleteToken) await deleteReview(request, deleteToken);
  });

  const paragraph = (page: Page) => page.locator(".line-block", { hasText: "The toolbar appears" }).locator(".line-content");

  test("pinned 👍 and 👎 come before Comment, and one click comments the selection", async ({ page }) => {
    await dragOverText(page, paragraph(page), "above a selection");
    const buttons = toolbar(page).locator("button");
    await expect(buttons).toHaveCount(3);
    await expect(buttons.nth(0)).toHaveAccessibleName('Comment "Accepted"');
    await expect(buttons.nth(2)).toHaveAccessibleName("Comment on selection");
    await buttons.nth(0).click();
    await waitForCommentCard(page, "Accepted");
    await expect(page.locator(".comment-form")).toHaveCount(0);
    await expect(page.locator("mark.quote-highlight")).toHaveText("above a selection");
  });

  test("Hide Comment shortcut hides c only; a template hides its own key", async ({ page }) => {
    await setReviewSetting(page, "selectionToolbarShortcuts", false);
    await page.evaluate(() => {
      const meta = { seeded: true, items: { Accepted: { emoji: "👍", pinned: true, shortcut: "Alt+p" }, Rejected: { emoji: "👎", pinned: true, shortcut: "Alt+c", hideShortcut: true } } };
      localStorage.setItem("crit-templates", JSON.stringify(["Accepted", "Rejected"]));
      localStorage.setItem("crit-template-meta", JSON.stringify(meta));
    });
    await dragOverText(page, paragraph(page), "above a selection");
    await expect(toolbar(page).getByRole("button", { name: "Comment on selection" }).locator("kbd:visible")).toHaveCount(0);
    const pins = toolbar(page).locator(".crit-selection-toolbar-pin");
    await expect(pins.nth(0).locator("kbd")).toHaveText(["Alt", "p"]);
    await expect(pins.nth(1).locator("kbd")).toHaveCount(0);
  });

  test("Alt+P comments the selection with 👍 Accepted out of the box", async ({ page }) => {
    await dragOverText(page, paragraph(page), "above a selection");
    await expect(toolbar(page).locator(".crit-selection-toolbar-pin").first().locator("kbd")).toHaveText(["Alt", "p"]);
    await page.keyboard.press("Alt+p");
    await waitForCommentCard(page, "Accepted");
  });

  test("a template shortcut comments the selection", async ({ page }) => {
    await page.evaluate(() => {
      const meta = { seeded: true, items: { Accepted: { emoji: "👍", pinned: true, shortcut: "y" }, Rejected: { emoji: "👎", pinned: true } } };
      localStorage.setItem("crit-templates", JSON.stringify(["Accepted", "Rejected"]));
      localStorage.setItem("crit-template-meta", JSON.stringify(meta));
    });
    await dragOverText(page, paragraph(page), "above a selection");
    await expect(toolbar(page).locator(".crit-selection-toolbar-pin").first().locator("kbd")).toHaveText("y");
    await page.keyboard.press("y");
    await waitForCommentCard(page, "Accepted");
  });

  test("placements: a corner, bottom center, closest to the cursor, and off", async ({ page }) => {
    await setReviewSetting(page, "selectionToolbar", "bottom-left");
    await dragOverText(page, paragraph(page), "above a selection");
    await expect(toolbar(page)).toHaveAttribute("data-placement", "below");
    await page.keyboard.press("Escape");

    await setReviewSetting(page, "selectionToolbar", "bottom-center");
    await dragOverText(page, paragraph(page), "above a selection");
    await expect(toolbar(page)).toHaveAttribute("data-placement", "below");
    const last = await page.evaluate(() => {
      const rects = Array.from(window.getSelection()!.getRangeAt(0).getClientRects()).filter((r) => r.width > 0);
      const r = rects[rects.length - 1];
      return (r.left + r.right) / 2;
    });
    const bar = (await toolbar(page).boundingBox())!;
    expect(Math.abs(bar.x + bar.width / 2 - last)).toBeLessThan(2);
    await page.keyboard.press("Escape");

    await setReviewSetting(page, "selectionToolbar", "top-cursor");
    await dragOverText(page, paragraph(page), "above a selection", true);
    const edges = await page.evaluate(() => {
      const rects = Array.from(window.getSelection()!.getRangeAt(0).getClientRects()).filter((r) => r.width > 0);
      return { left: rects[0].left };
    });
    expect(Math.abs((await toolbar(page).boundingBox())!.x - edges.left)).toBeLessThan(2);
    await page.keyboard.press("Escape");

    await setReviewSetting(page, "selectionToolbarEnabled", false);
    await page.evaluate(() => window.getSelection()?.removeAllRanges());
    const box = (await paragraph(page).boundingBox())!;
    await page.mouse.move(box.x + 10, box.y + box.height / 2);
    await page.mouse.down();
    await page.mouse.move(box.x + 200, box.y + box.height / 2, { steps: 5 });
    await page.mouse.up();
    await page.waitForTimeout(200);
    await expect(toolbar(page)).toBeHidden();
  });

  test("Settings > Selection toolbar: the switch, then Advanced with position, style and Hide switches", async ({ page }) => {
    await page.locator("#settingsToggle").click();
    await expect(page.locator("#toolbarEnabledToggle")).toBeChecked();
    await page.locator("#toolbarAdvanced summary").click();
    const position = page.locator("#selectionToolbarSelect");
    await expect(position).toHaveValue("top-cursor");
    await expect(position.locator('option[value="off"]')).toHaveCount(0);
    await position.selectOption("bottom-center");
    await page.locator('[data-toolbar-style="icon"]').click();
    await expect(page.locator("#toolbarShortcutsToggle")).not.toBeChecked();
    await expect(page.locator("#toolbarTemplatesToggle")).not.toBeChecked();
    await expect(page.locator("#toolbarTemplatesCount")).toHaveText("One-click comments beside Comment · 2 in the toolbar");
    await page.locator("label.comments-panel-switch:has(#toolbarShortcutsToggle)").click();
    await page.locator("label.comments-panel-switch:has(#toolbarTemplatesToggle)").click();
    await page.locator("#manageTemplatesBtn").click();
    await expect(page.locator("#templatesPane")).toBeVisible();
    await page.locator("#settingsClose").click();
    const settings = await page.evaluate(() => {
      const match = document.cookie.match(/(?:^|;\s*)crit-settings=([^;]*)/);
      return match ? JSON.parse(decodeURIComponent(match[1])) : {};
    });
    expect(settings).toMatchObject({
      selectionToolbar: "bottom-center", selectionToolbarButtonStyle: "icon",
      selectionToolbarShortcuts: false, selectionToolbarTemplates: false,
    });

    await dragOverText(page, paragraph(page), "above a selection");
    const buttons = toolbar(page).locator("button:visible");
    await expect(buttons).toHaveCount(1);
    await expect(buttons.first().locator(".crit-selection-toolbar-add")).toBeVisible();
    await expect(toolbar(page).locator("kbd:visible")).toHaveCount(0);
  });
});
