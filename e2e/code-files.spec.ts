import { test, expect, Page } from "@playwright/test";
import {
  codeFile,
  codeLine,
  createReview,
  deleteReview,
  hoverCodeLine,
  loadReview,
  openCodeLineComment,
  selectedCodeLines,
  waitForCommentCard,
} from "./helpers";

const BASE_URL = `http://127.0.0.1:${process.env.CRIT_WEB_TEST_PORT || "4003"}`;

// Code files render through Pierre's File (Shiki highlighting, line numbers,
// hover "+", gutter range selection), as crit renders files-mode code files.
// Comments and open forms are Pierre line annotations; tints and quote
// highlights live in its shadow root.

const GO = [
  "package main",
  "",
  'import "net/http"',
  "",
  "// authMiddleware checks the API key.",
  "func authMiddleware(next http.Handler) http.Handler {",
  "\treturn http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {",
  '\t\tif r.Header.Get("X-API-Key") == "" {',
  '\t\t\thttp.Error(w, "invalid key", http.StatusUnauthorized)',
  "\t\t\treturn",
  "\t\t}",
  "\t\tnext.ServeHTTP(w, r)",
  "\t})",
  "}",
  "",
].join("\n");

// Rows run in file order across documents and code files; step with j until
// the keyboard focus reaches line 1 of `path`.
async function focusFirstLineOf(page: Page, path: string) {
  await page.locator("body").click({ position: { x: 5, y: 300 } });
  for (let i = 0; i < 40; i++) {
    await page.keyboard.press("j");
    if ((await selectedCodeLines(page, path)).join() === "1") return;
  }
  throw new Error(`keyboard focus never reached ${path}`);
}

test.describe("Code files", () => {
  let token: string;
  let deleteToken: string;

  test.beforeEach(async ({ request, page }) => {
    const review = await createReview(request, {
      files: [
        { path: "server.go", content: GO },
        { path: "notes.md", content: "# Notes\n\nSome prose.\n" },
        { path: "LICENSE", content: "MIT License\n\nCopyright (c) 2026\n" },
      ],
      comments: [{ start_line: 6, end_line: 7, body: "Existing thread", file: "server.go" }],
    });
    token = review.token;
    deleteToken = review.deleteToken;
    await loadReview(page, token);
    await expect(codeLine(page, "server.go", 1)).toBeVisible();
  });

  test.afterEach(async ({ request }) => {
    await deleteReview(request, deleteToken);
  });

  test("renders code files with Shiki, line numbers and no line blocks", async ({ page }) => {
    const file = codeFile(page, "server.go");
    // 14 lines; Pierre shows the empty line after the trailing newline too.
    await expect(file.locator('[data-column-number="14"]')).toBeVisible();
    await expect(file.locator('[data-column-number="16"]')).toHaveCount(0);
    await expect(codeLine(page, "server.go", 6).locator('span[style*="--diffs-token-dark"]').first()).toBeVisible();
    await expect(file.locator(".line-block")).toHaveCount(0);
    // Files without a markdown extension are code, as in crit (LICENSE, .txt, ...).
    await expect(codeLine(page, "LICENSE", 1)).toContainText("MIT License");
    // Markdown still renders as a document.
    await expect(page.locator('.line-block[data-file-path="notes.md"] h1')).toHaveText(/Notes/);
  });

  test("code files use the same centered reading width as markdown", async ({ page }) => {
    await page.setViewportSize({ width: 1600, height: 1000 });
    await expect(async () => {
      const layout = await page.locator("#document-renderer").evaluate(root => {
        const rect = root.getBoundingClientRect();
        return {
          center: rect.x + rect.width / 2,
          width: rect.width,
          bodies: Array.from(root.querySelectorAll('.file-body')).map(body => {
            const box = body.getBoundingClientRect();
            return { center: box.x + box.width / 2, width: box.width };
          }),
        };
      });
      expect(layout.bodies).toHaveLength(3);
      for (const body of layout.bodies) {
        expect(body.center).toBeCloseTo(layout.center, 1);
        expect(body.width).toBeCloseTo(layout.bodies[0].width, 1);
        expect(body.width).toBeLessThan(layout.width);
      }
    }).toPass();
  });

  test("content width resizes every file and persists after reload", async ({ page }) => {
    await page.setViewportSize({ width: 1900, height: 1000 });
    await page.locator("#settingsToggle").click();
    await expect(page.locator("#settingsOverlay.active")).toBeVisible();

    const expectWidth = async (width: number) => {
      await expect(async () => {
        const layout = await page.locator("#document-renderer").evaluate(root => {
          const rect = root.getBoundingClientRect();
          return {
            center: rect.x + rect.width / 2,
            bodies: Array.from(root.querySelectorAll('.file-body')).map(body => {
              const box = body.getBoundingClientRect();
              return { center: box.x + box.width / 2, width: box.width };
            }),
          };
        });
        expect(layout.bodies).toHaveLength(3);
        for (const body of layout.bodies) {
          expect(body.width).toBeCloseTo(width, 1);
          expect(body.center).toBeCloseTo(layout.center, 1);
        }
      }).toPass();
    };

    for (const [choice, width] of [["compact", 840], ["default", 1040], ["wide", 1280]] as const) {
      await page.locator(`[data-settings-width="${choice}"]`).click();
      await expectWidth(width);
    }
    await loadReview(page, token);
    await expect(codeLine(page, "server.go", 1)).toBeVisible();
    await expectWidth(1280);
  });

  test("file and inline cards share reading width across settings and viewports", async ({ page, request }) => {
    const fixture = await createReview(request, {
      files: [
        { path: "sample.go", content: "package main\nfunc main() {}\n" },
        { path: "sample.md", content: "# Sample\n\nSome prose.\n" },
      ],
      comments: [
        { scope: "file", file: "sample.go", body: "Code file thread" },
        { start_line: 1, end_line: 1, file: "sample.go", body: "Code line thread" },
        { scope: "file", file: "sample.md", body: "Markdown file thread" },
        { start_line: 1, end_line: 1, file: "sample.md", body: "Markdown line thread" },
      ],
    });
    try {
      await loadReview(page, fixture.token);
      await expect(codeLine(page, "sample.go", 1)).toBeVisible();
      for (const viewport of [1900, 1000, 390]) {
        await page.setViewportSize({ width: viewport, height: 1000 });
        await page.locator("#settingsToggle").click();
        for (const choice of ["compact", "default", "wide"]) {
          await page.locator(`[data-settings-width="${choice}"]`).click();
          await expect(async () => {
            const boxes = await page.locator(".file-section .comment-card").evaluateAll(cards =>
              cards.map(card => ({ width: card.getBoundingClientRect().width, x: card.getBoundingClientRect().x })));
            expect(boxes).toHaveLength(4);
            for (const box of boxes) {
              expect(Math.abs(box.width - boxes[0].width)).toBeLessThan(2);
              expect(Math.abs(box.x - boxes[0].x)).toBeLessThan(2);
              expect(box.width).toBeGreaterThan(200);
            }
            expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(viewport);
          }).toPass();
        }
        await page.keyboard.press("Escape");
      }
      const card = page.locator('.comment-card').filter({ hasText: 'Code line thread' });
      await card.locator('.comment-collapse-btn').click();
      await expect(card).toHaveClass(/collapsed/);
      await card.locator('.comment-collapse-btn').click();
      await expect(card).not.toHaveClass(/collapsed/);
      await page.setViewportSize({ width: 1900, height: 1000 });
      await expect(page.locator(".file-header").first()).toHaveCSS("border-top-left-radius", "6px");
      await expect(page.locator(".files-container")).toHaveCSS("padding-left", "32px");
      await expect(page.locator(".file-section").first()).toHaveCSS("margin-bottom", "18px");
    } finally {
      await deleteReview(request, fixture.deleteToken);
    }
  });

  test("existing threads sit under their end line with the range tinted", async ({ page }) => {
    const file = codeFile(page, "server.go");
    const card = file.locator(".comment-card").filter({ hasText: "Existing thread" });
    await expect(card).toBeVisible();
    // The thread is below line 7 and above line 8.
    await expect(async () => {
      const [line7, cardBox, line8] = await Promise.all([
        codeLine(page, "server.go", 7).boundingBox(),
        card.boundingBox(),
        codeLine(page, "server.go", 8).boundingBox(),
      ]);
      expect(line7).not.toBeNull();
      expect(cardBox).not.toBeNull();
      expect(line8).not.toBeNull();
      expect(cardBox!.y).toBeGreaterThan(line7!.y);
      expect(cardBox!.y).toBeLessThan(line8!.y);
    }).toPass();
    const tint = (n: number) => codeLine(page, "server.go", n).evaluate((el) => getComputedStyle(el).backgroundColor);
    expect(await tint(6)).not.toBe(await tint(3));
    expect(await tint(7)).toBe(await tint(6));
  });

  test("the gutter + opens a form and a new comment appears live", async ({ page }) => {
    await openCodeLineComment(page, "server.go", 9);
    await expect(page.locator(".comment-form-header")).toHaveText("Comment on Line 9");
    await page.locator(".comment-form textarea").fill("Use a constant for this");
    await page.locator(".comment-form textarea").press("Control+Enter");
    await waitForCommentCard(page, "Use a constant for this");
    await expect(codeFile(page, "server.go").locator(".comment-card").filter({ hasText: "Use a constant" })).toBeVisible();
    await expect(page.locator(".comment-form")).toHaveCount(0);
  });

  test("dragging across line numbers comments on the range", async ({ page }) => {
    const to = codeFile(page, "server.go").locator('[data-column-number="11"]');
    await hoverCodeLine(page, "server.go", 9);
    const utility = codeFile(page, "server.go").locator("[data-utility-button]");
    await expect(utility).toBeVisible();
    const start = await utility.boundingBox();
    const end = await to.boundingBox();
    await page.mouse.move(start!.x + start!.width / 2, start!.y + start!.height / 2);
    await page.mouse.down();
    await page.mouse.move(start!.x + start!.width / 2, end!.y + end!.height / 2, { steps: 6 });
    await page.mouse.up();
    await expect(page.locator(".comment-form-header")).toHaveText("Comment on Lines 9–11");
  });

  test("an open form keeps its text when another form opens elsewhere", async ({ page }) => {
    await openCodeLineComment(page, "server.go", 3);
    await page.locator(".comment-form textarea").fill("Draft on line 3");
    await page.locator('.line-block[data-file-path="notes.md"] .line-gutter').first().click();
    await expect(page.locator(".comment-form")).toHaveCount(2);
    await expect(codeFile(page, "server.go").locator(".comment-form textarea")).toHaveValue("Draft on line 3");
  });

  test("j/k move through code lines and c comments on the focused line", async ({ page }) => {
    await focusFirstLineOf(page, "server.go");
    await page.keyboard.press("j");
    await page.keyboard.press("j");
    await expect.poll(() => selectedCodeLines(page, "server.go")).toEqual([3]);
    await page.keyboard.press("k");
    await expect.poll(() => selectedCodeLines(page, "server.go")).toEqual([2]);
    await page.keyboard.press("c");
    await expect(page.locator(".comment-form-header")).toHaveText("Comment on Line 2");
  });

  test("visual mode selects a range of code lines for one comment", async ({ page }) => {
    await focusFirstLineOf(page, "server.go");
    for (let i = 0; i < 3; i++) await page.keyboard.press("j");
    await page.keyboard.press("Shift+V");
    await page.keyboard.press("j");
    await page.keyboard.press("j");
    await expect.poll(() => selectedCodeLines(page, "server.go")).toEqual([4, 5, 6]);
    await page.keyboard.press("c");
    await expect(page.locator(".comment-form-header")).toHaveText("Comment on Lines 4–6");
  });

  test("selecting text in code comments on its lines with a quote", async ({ page }) => {
    await hoverCodeLine(page, "server.go", 9);
    await page.evaluate(() => {
      const host = document.querySelector('.crit-code-file[data-file-path="server.go"] diffs-container')!;
      const line = host.shadowRoot!.querySelector('[data-content] > [data-line="9"]')!;
      const walker = document.createTreeWalker(line, NodeFilter.SHOW_TEXT);
      let node: Node | null;
      while ((node = walker.nextNode())) {
        const at = node.textContent!.indexOf("invalid key");
        if (at < 0) continue;
        const range = document.createRange();
        range.setStart(node, at);
        range.setEnd(node, at + "invalid key".length);
        const selection = window.getSelection()!;
        selection.removeAllRanges();
        selection.addRange(range);
        return;
      }
      throw new Error("text not found");
    });
    await page.keyboard.press("c");
    await expect(page.locator(".comment-form-header")).toHaveText("Comment on Line 9");
    await page.locator(".comment-form textarea").fill("Quoted");
    await page.locator(".comment-form textarea").press("Control+Enter");
    await waitForCommentCard(page, "Quoted");
    // The quote is highlighted inside Pierre's shadow root (CSS Custom Highlight API).
    await expect.poll(() => page.evaluate(() => {
      const ranges = [...(CSS.highlights.get("crit-quote") || [])] as Range[];
      return ranges.map((r) => r.toString());
    })).toContain("invalid key");
  });

  test("hide resolved removes resolved threads from code files", async ({ page }) => {
    // Resolve a thread this visitor wrote (seeded threads belong to nobody here).
    await openCodeLineComment(page, "server.go", 10);
    await page.locator(".comment-form textarea").fill("Mine to resolve");
    await page.locator(".comment-form textarea").press("Control+Enter");
    await waitForCommentCard(page, "Mine to resolve");
    const card = codeFile(page, "server.go").locator(".comment-card").filter({ hasText: "Mine to resolve" });
    await card.locator(".resolve-btn").click();
    await expect(codeFile(page, "server.go").locator(".resolved-card")).toBeVisible();
    await page.locator("#settingsToggle").click();
    await page.locator("#hideResolvedToggle").check();
    await page.keyboard.press("Escape");
    await expect(codeFile(page, "server.go").locator(".comment-card").filter({ hasText: "Mine to resolve" })).toHaveCount(0);
    await expect(codeFile(page, "server.go").locator(".comment-card").filter({ hasText: "Existing thread" })).toBeVisible();
  });
});

test.describe("Code files — edge cases", () => {
  test("a comment past the end of the file is listed as outdated", async ({ page, request }) => {
    const review = await createReview(request, {
      files: [
        { path: "a.go", content: "package a\n" },
        { path: "b.md", content: "# B\n" },
      ],
      comments: [{ start_line: 40, end_line: 40, body: "Line gone", file: "a.go" }],
    });
    try {
      await loadReview(page, review.token);
      const outdated = page.locator(".file-section .file-comments .outdated-comment");
      await expect(outdated).toContainText("Line gone");
      await expect(outdated.locator(".outdated-badge")).toHaveText("Outdated");
    } finally {
      await deleteReview(request, review.deleteToken);
    }
  });

  test("a single-file code review renders through Pierre", async ({ page, request }) => {
    const review = await createReview(request, {
      files: [{ path: "app.ex", content: "defmodule App do\n  def hi, do: :ok\nend\n" }],
      comments: [{ start_line: 2, end_line: 2, body: "Single file thread", file: "app.ex" }],
    });
    try {
      await loadReview(page, review.token);
      await expect(codeLine(page, "app.ex", 2).locator('span[style*="--diffs-token"]').first()).toBeVisible();
      await expect(codeFile(page, "app.ex").locator(".comment-card")).toContainText("Single file thread");
      await openCodeLineComment(page, "app.ex", 3);
      await expect(page.locator(".comment-form-header")).toHaveText("Comment on Line 3");
    } finally {
      await deleteReview(request, review.deleteToken);
    }
  });

  test("reviews closed to anonymous comments show no gutter + on code", async ({ browser, request }) => {
    const seeded = await request.post(`${BASE_URL}/api/test/seed-user`, { data: { name: "Code Owner" } });
    const { token: bearer } = await seeded.json();
    const files = [{ path: "a.go", content: "package a\n\nfunc A() {}\n" }];
    const created = await request.post(`${BASE_URL}/api/reviews`, {
      headers: { Authorization: `Bearer ${bearer}` },
      data: { files, comments: [] },
    });
    const { url, delete_token: deleteToken } = await created.json();
    const token = (url as string).split("/r/")[1];
    const updated = await request.put(`${BASE_URL}/api/reviews/${token}`, {
      headers: { Authorization: `Bearer ${bearer}` },
      data: { delete_token: deleteToken, files, comments: [], review_round: 1, comment_policy: "logged_in_only" },
    });
    expect(updated.status()).toBe(200);
    const ctx = await browser.newContext();
    const page = await ctx.newPage();
    try {
      await loadReview(page, token);
      await hoverCodeLine(page, "a.go", 3, { commentable: false });
      await expect(codeLine(page, "a.go", 3)).toBeVisible();
      await expect(codeFile(page, "a.go").locator("[data-utility-button]")).toHaveCount(0);
    } finally {
      await ctx.close();
      await deleteReview(request, deleteToken);
    }
  });
});
