import { test, expect, type Locator } from "@playwright/test";
import { createReview, deleteReview, loadReview, seedComment } from "./helpers";

const API_ORIGIN = `http://127.0.0.1:${process.env.CRIT_WEB_TEST_PORT || "4003"}`;
const TABLE_MARKDOWN =
  "| Link | Status |\n" +
  "| --- | --- |\n" +
  "| [x](https://example.com/a/very/very/very/long/hidden/path) | available |\n" +
  "| beta | waiting for review |\n" +
  "| gamma | ready |\n" +
  "| delta | review then review |\n";

test.describe("Review Page — Loading", () => {
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

  test("renders the review page with document content", async ({ page }) => {
    await loadReview(page, token);

    // The meta bar should show the filename
    await expect(page.locator(".crit-review-meta")).toContainText("example.md");

    // The document should have rendered line blocks
    const lineBlocks = page.locator(".line-block");
    await expect(lineBlocks.first()).toBeVisible();
    expect(await lineBlocks.count()).toBeGreaterThan(0);
  });

  test("renders markdown heading as rendered content", async ({ page }) => {
    await loadReview(page, token);

    // The heading "Hello World" should be rendered
    await expect(page.locator("#document-renderer h1")).toContainText(
      "Hello World"
    );
  });

  test("renders YAML frontmatter as highlighted YAML", async ({ page, request }) => {
    const review = await createReview(request, {
      files: [{
        path: "frontmatter.md",
        content: "---\ntitle: Hello\n---\n\n# Document\n",
      }],
    });
    const frontmatterToken = review.token;

    try {
      await loadReview(page, frontmatterToken);
      const code = page.locator("#document-renderer code.hljs").filter({ hasText: "title: Hello" });
      await expect(code).toContainText("title: Hello");
      await expect(code.locator(".hljs-attr")).toHaveText("title:");
    } finally {
      await deleteReview(request, review.deleteToken);
    }
  });

  test("shows comment navigation group", async ({ page }) => {
    await loadReview(page, token);

    // The comment navigation buttons should exist in the header
    const commentCountBtn = page.locator("#comment-count");
    await expect(commentCountBtn).toBeVisible();
  });

  test("shows the 'Get prompt' button", async ({ page }) => {
    await loadReview(page, token);

    await expect(
      page.locator(".crit-split-btn-main")
    ).toContainText("Get prompt");
  });

  test("renders 404 page for invalid token", async ({ page }) => {
    const response = await page.goto("/r/nonexistent-token-12345");
    expect(response?.status()).toBe(404);
    await expect(page.getByRole("heading", { level: 1 })).toContainText(
      "not found"
    );
  });
});

test.describe("Review Page — Display Name", () => {
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

  test("can set display name", async ({ page }) => {
    await loadReview(page, token);

    // Click the name pill button to show the form
    const nameBtn = page.locator("#name-pill-btn");
    await expect(nameBtn).toBeVisible();
    await nameBtn.click();

    // Fill in the name
    const nameInput = page.locator("#name-input");
    await expect(nameInput).toBeVisible();
    await nameInput.fill("Test Reviewer");

    // Submit
    await page.locator(".crit-name-save").click();

    // Button should now show the name
    await expect(nameBtn).toContainText("Test Reviewer");
  });
});

test.describe("Review Page — Rendered Tables", () => {
  let token: string;
  let deleteToken: string;

  test.beforeEach(async ({ request }) => {
    const review = await createReview(request, {
      files: [{
        path: "table.md",
        content: TABLE_MARKDOWN,
      }, {
        path: "notes.md",
        content: "# Notes\n\nA second file exercises the multi-file renderer.\n",
      }],
      reviewRound: 1,
    });
    token = review.token;
    deleteToken = review.deleteToken;
  });

  test.afterEach(async ({ request }) => {
    await deleteReview(request, deleteToken);
  });

  test("uses one native auto-layout table without generated widths", async ({ page }) => {
    await loadReview(page, token);

    const table = page.locator("table.native-table");
    await expect(table).toHaveCount(1);
    await expect(table.locator("thead tr.table-row")).toHaveCount(1);
    await expect(table.locator("tbody tr.table-row")).toHaveCount(4);
    await expect(table.locator("colgroup")).toHaveCount(0);
    expect(await table.evaluate(element => getComputedStyle(element).tableLayout)).toBe("auto");
    expect(await table.locator("..").evaluate(element => getComputedStyle(element).borderTopWidth)).toBe("0px");
  });

  test("table-row forms cancel with both the button and Escape", async ({ page }) => {
    await loadReview(page, token);

    let row = page.getByRole("cell", { name: "beta", exact: true }).locator("..");
    await row.locator(".line-gutter").click();
    await expect(page.locator(".comment-form")).toBeVisible();
    await page.getByRole("button", { name: "Cancel", exact: true }).click();
    await expect(page.locator(".comment-form")).toHaveCount(0);

    row = page.getByRole("cell", { name: "beta", exact: true }).locator("..");
    await row.locator(".line-gutter").click();
    const textarea = page.locator(".comment-form textarea");
    await expect(textarea).toBeFocused();
    await textarea.press("Escape");
    await expect(page.locator(".comment-form")).toHaveCount(0);
  });

  test("selected text in a table cell is highlighted when commenting", async ({ page }) => {
    await loadReview(page, token);
    const cell = page.getByRole("cell", { name: "waiting for review", exact: true });
    await selectPhrase(cell, "review");
    await page.keyboard.press("c");

    await expect(page.locator(".comment-form textarea")).toBeFocused();
    await expect(page.locator("mark.quote-highlight")).toHaveText("review");
    await page.getByRole("button", { name: "Cancel", exact: true }).click();

    const row = page.getByRole("cell", { name: "beta", exact: true }).locator("..");
    await row.evaluate(element => {
      const cells = element.querySelectorAll(".line-content");
      const first = cells[0].firstChild;
      const second = cells[1].firstChild;
      if (!first || !second) throw new Error("Expected text in adjacent table cells");
      const range = document.createRange();
      range.setStart(first, 0);
      range.setEnd(second, 7);
      const selection = window.getSelection();
      selection?.removeAllRanges();
      selection?.addRange(range);
    });
    await page.keyboard.press("c");
    await expect(page.locator("mark.quote-highlight")).toHaveCount(2);
    await expect(page.locator("mark.quote-highlight").nth(0)).toHaveText("beta");
    await expect(page.locator("mark.quote-highlight").nth(1)).toHaveText("waiting");
  });

  test("keeps the selected occurrence of a duplicate phrase after submission", async ({ page }) => {
    await loadReview(page, token);
    const cell = page.getByRole("cell", { name: "review then review", exact: true });
    await selectPhrase(cell, "review", 1);
    await page.keyboard.press("c");

    const textarea = page.locator(".comment-form textarea");
    await textarea.fill("Second occurrence");
    await textarea.press("Control+Enter");
    await expect(page.locator(".comment-card", { hasText: "Second occurrence" })).toBeVisible();
    await expect(cell.locator("mark.quote-highlight")).toHaveCount(1);
    expect(await cell.evaluate(element => element.innerHTML)).toMatch(/review then\s*<mark[^>]*>review<\/mark>/);
  });

  test("keeps fallback table columns aligned in rendered round diffs", async ({ page, request }) => {
    const updatedTable = TABLE_MARKDOWN.replace(
      "| beta | waiting for review |",
      "| beta | waiting for a substantially longer second review |",
    );
    const update = async (content: string) => {
      const response = await request.put(`${API_ORIGIN}/api/reviews/${token}`, {
        data: {
          delete_token: deleteToken,
          files: [
            { path: "table.md", content },
            { path: "notes.md", content: "# Notes\n\nA second file exercises the multi-file renderer.\n" },
          ],
          comments: [],
        },
      });
      expect(response.ok()).toBeTruthy();
    };
    await update(updatedTable);
    await update(updatedTable.replace("| gamma | ready |", "| gamma | ready now |"));

    await loadReview(page, token);
    const section = page.locator(".file-section").filter({ hasText: "table.md" });
    await page.locator("button.crit-round-diff-btn").click();
    const diff = section.locator(".diff-view");
    await expect(diff).toBeVisible();
    const tables = diff.locator("table.split-table");
    await expect(tables.first()).toBeVisible();
    await expect(tables.locator("colgroup").first()).toBeAttached();

    const sideWidthSets = await diff.evaluate(element => {
      const cells = Array.from(element.querySelectorAll(":scope > .diff-view-cell"));
      return [0, 1].map(side => Array.from(new Set(cells
        .filter((_, index) => index % 2 === side)
        .map(cell => Array.from(cell.querySelectorAll("table.split-table col"))
          .map(col => (col as HTMLElement).style.width).join(","))
        .filter(Boolean))));
    });
    expect(sideWidthSets[0]).toHaveLength(1);
    expect(sideWidthSets[1]).toHaveLength(1);
    expect(await tables.first().evaluate(table => getComputedStyle(table).marginTop)).toBe("0px");
  });

  test("n and Shift+N navigate and flash rendered table diff changes", async ({ page, request }) => {
    const update = async (content: string) => {
      const response = await request.put(`${API_ORIGIN}/api/reviews/${token}`, {
        data: {
          delete_token: deleteToken,
          files: [
            { path: "table.md", content },
            { path: "notes.md", content: "# Notes\n\nA second file exercises the multi-file renderer.\n" },
          ],
          comments: [],
        },
      });
      expect(response.ok()).toBeTruthy();
    };
    await update(TABLE_MARKDOWN.replace("| beta | waiting for review |", "| beta | changed once |"));
    await update(
      TABLE_MARKDOWN
        .replace("| beta | waiting for review |", "| beta | changed twice |")
        .replace("| gamma | ready |", "| gamma | changed separately |")
    );

    await loadReview(page, token);
    const tableSection = page.locator(".file-section").filter({ hasText: "table.md" });
    await page.locator("button.crit-round-diff-btn").click();
    await expect(tableSection.locator(".diff-view")).toBeVisible();

    await page.keyboard.press("n");
    const firstTarget = page.locator(".change-flash");
    await expect(firstTarget).toHaveCount(1);
    const firstText = await firstTarget.textContent();

    await page.keyboard.press("Shift+N");
    const previousTarget = page.locator(".change-flash");
    await expect(previousTarget).toHaveCount(1);
    expect(await previousTarget.textContent()).not.toBe(firstText);
  });

  test("drag selection has continuous row-height gutter segments", async ({ page }) => {
    await loadReview(page, token);
    const first = page.getByRole("cell", { name: "x", exact: true }).locator("..").locator(".line-gutter");
    const last = page.getByRole("cell", { name: "gamma", exact: true }).locator("..").locator(".line-gutter");
    await first.scrollIntoViewIfNeeded();
    const firstBox = await first.boundingBox();
    const lastBox = await last.boundingBox();
    expect(firstBox).toBeTruthy();
    expect(lastBox).toBeTruthy();
    if (!firstBox || !lastBox) return;

    await page.mouse.move(firstBox.x + firstBox.width / 2, firstBox.y + 10);
    await page.mouse.down();
    await page.mouse.move(lastBox.x + lastBox.width / 2, lastBox.y + 10, { steps: 5 });
    const segments = await page.locator(".native-table .line-block.drag-range .line-comment-gutter")
      .evaluateAll(gutters => gutters.map(gutter => {
        const rect = gutter.getBoundingClientRect();
        return { top: rect.top, bottom: rect.bottom, height: rect.height };
      }));
    expect(segments).toHaveLength(3);
    for (let index = 0; index < segments.length - 1; index++) {
      expect(Math.abs(segments[index].bottom - segments[index + 1].top)).toBeLessThanOrEqual(0.5);
      expect(segments[index].height).toBeGreaterThan(20);
    }
    await page.mouse.up();
    await expect(page.locator(".comment-form")).toBeVisible();
  });

  test("row stripes stay stable when an annotation is inserted", async ({ page }) => {
    await loadReview(page, token);
    const evenRow = page.getByRole("cell", { name: "beta", exact: true }).locator("..");
    const oddRow = page.getByRole("cell", { name: "gamma", exact: true }).locator("..");
    await expect(evenRow).toHaveClass(/table-even/);
    await expect(oddRow).not.toHaveClass(/table-even/);
    const before = await Promise.all([
      evenRow.locator("td.line-content").first().evaluate(cell => getComputedStyle(cell).backgroundColor),
      oddRow.locator("td.line-content").first().evaluate(cell => getComputedStyle(cell).backgroundColor),
    ]);
    expect(before[0]).not.toBe(before[1]);

    await page.getByRole("cell", { name: "x", exact: true }).locator("..").locator(".line-gutter").click();
    const after = await Promise.all([
      page.getByRole("cell", { name: "beta", exact: true }).evaluate(cell => getComputedStyle(cell).backgroundColor),
      page.getByRole("cell", { name: "gamma", exact: true }).evaluate(cell => getComputedStyle(cell).backgroundColor),
    ]);
    expect(after).toEqual(before);
  });

  test("live-added table comments remain wrapped in semantic annotation rows", async ({ page, browser }) => {
    const observer = await browser.newPage();
    await loadReview(page, token);
    await loadReview(observer, token);

    await page.getByRole("cell", { name: "beta", exact: true }).locator("..").locator(".line-gutter").click();
    const textarea = page.locator(".comment-form textarea");
    await textarea.fill("Broadcast table comment");
    await textarea.press("Control+Enter");

    const annotation = observer.locator("tr.native-table-annotation", { hasText: "Broadcast table comment" });
    await expect(annotation).toBeVisible();
    expect(await annotation.evaluate(element => element.parentElement?.tagName)).toBe("TBODY");
    await observer.close();
  });
});

async function selectPhrase(cell: Locator, phrase: string, occurrence = 0) {
  await cell.evaluate((element, requested) => {
    const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT);
    let node;
    while ((node = walker.nextNode())) {
      let start = -1;
      let fromIndex = 0;
      for (let index = 0; index <= requested.occurrence; index++) {
        start = node.textContent?.indexOf(requested.phrase, fromIndex) ?? -1;
        if (start === -1) break;
        fromIndex = start + requested.phrase.length;
      }
      if (start === -1) continue;
      const range = document.createRange();
      range.setStart(node, start);
      range.setEnd(node, start + requested.phrase.length);
      const selection = window.getSelection();
      selection?.removeAllRanges();
      selection?.addRange(range);
      return;
    }
    throw new Error(`Phrase not found: ${requested.phrase}`);
  }, { phrase, occurrence });
}
