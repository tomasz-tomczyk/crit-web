import { test, expect, type Page } from "@playwright/test";
import { createReview, deleteReview, loadReview } from "./helpers";

// a (toggle viewed) and o (collapse or expand) act on the file of the last
// j/k focus, or on the file under the mouse when the mouse moved since then
// (crit #1049).

const FIRST = "a-first.md";
const SECOND = "b-second.md";

function section(page: Page, path: string) {
  return page.locator(`details.file-section[data-file-path="${path}"]`);
}

test.describe("File shortcuts — a / o", () => {
  let token: string;
  let deleteToken: string;

  test.beforeEach(async ({ page, request }) => {
    const review = await createReview(request, {
      files: [
        { path: FIRST, content: "# First\n\n- one\n- two\n" },
        { path: SECOND, content: "# Second\n\n- three\n- four\n" },
      ],
    });
    token = review.token;
    deleteToken = review.deleteToken;
    // Viewed state is kept per browser; start clean.
    await page.goto("/");
    await page.evaluate(() => {
      for (let i = localStorage.length - 1; i >= 0; i--) {
        const key = localStorage.key(i);
        if (key && key.startsWith("crit-viewed-")) localStorage.removeItem(key);
      }
    });
  });

  test.afterEach(async ({ request }) => {
    await deleteReview(request, deleteToken);
  });

  test("a marks the focused file viewed, and again unmarks it", async ({ page }) => {
    await loadReview(page, token);
    await page.keyboard.press("j");
    await expect(section(page, FIRST).locator(".line-block.focused")).toHaveCount(1);

    const checkbox = section(page, FIRST).locator(".file-header-viewed input");
    await page.keyboard.press("a");
    await expect(checkbox).toBeChecked();
    // Viewing a file collapses it, as the checkbox does.
    await expect(section(page, FIRST)).not.toHaveAttribute("open", "");
    await expect(page.locator("#critStatus")).toHaveText(`Marked ${FIRST} viewed`);
    await expect(section(page, SECOND).locator(".file-header-viewed input")).not.toBeChecked();

    await page.keyboard.press("a");
    await expect(checkbox).not.toBeChecked();
    await expect(page.locator("#critStatus")).toHaveText(`Unmarked ${FIRST} viewed`);
  });

  test("o collapses and expands the focused file", async ({ page }) => {
    await loadReview(page, token);
    await page.keyboard.press("j");

    await page.keyboard.press("o");
    await expect(section(page, FIRST)).not.toHaveAttribute("open", "");
    await expect(section(page, SECOND)).toHaveAttribute("open", "");
    await expect(page.locator("#critStatus")).toHaveText(`Collapsed ${FIRST}`);

    await page.keyboard.press("o");
    await expect(section(page, FIRST)).toHaveAttribute("open", "");
    await expect(page.locator("#critStatus")).toHaveText(`Expanded ${FIRST}`);
    // The focus comes back with the file.
    await expect(section(page, FIRST).locator(".line-block.focused")).toHaveCount(1);
  });

  test("the file under the mouse wins once the mouse moves after j/k", async ({ page }) => {
    await loadReview(page, token);
    await page.keyboard.press("j");

    // The second file's header is on screen; its body may not be.
    const box = await section(page, SECOND).locator(".file-header .filename").boundingBox();
    if (!box) throw new Error("second file header not on screen");
    await page.mouse.move(box.x + 2, box.y + box.height / 2);
    await page.mouse.move(box.x + 10, box.y + box.height / 2, { steps: 4 });

    await page.keyboard.press("o");
    await expect(section(page, SECOND)).not.toHaveAttribute("open", "");
    await expect(section(page, FIRST)).toHaveAttribute("open", "");

    // j moves the keyboard focus again: it wins over the still mouse.
    await page.keyboard.press("j");
    await page.keyboard.press("o");
    await expect(section(page, FIRST)).not.toHaveAttribute("open", "");
  });

  test("o on a file above the focus keeps j moving within the focused file", async ({ page }) => {
    await loadReview(page, token);
    const second = section(page, SECOND);
    // j until the focus is on the first row of the second file.
    for (let i = 0; i < 20; i++) {
      await page.keyboard.press("j");
      if ((await second.locator(".line-block.focused").count()) > 0) break;
    }
    const focused = second.locator(".line-block.focused");
    await expect(focused).toHaveCount(1);
    const startLine = Number(await focused.getAttribute("data-start-line"));

    // Collapse the first file with the mouse over it.
    const box = await section(page, FIRST).locator(".file-header .filename").boundingBox();
    if (!box) throw new Error("first file header not on screen");
    await page.mouse.move(box.x + 2, box.y + box.height / 2);
    await page.mouse.move(box.x + 10, box.y + box.height / 2, { steps: 4 });
    await page.keyboard.press("o");
    await expect(section(page, FIRST)).not.toHaveAttribute("open", "");

    // j goes to the next row of the second file, not a row further on.
    await page.keyboard.press("j");
    await expect(focused).toHaveCount(1);
    const nextStart = Number(await focused.getAttribute("data-start-line"));
    const rowStarts = await second.locator(".line-block").evaluateAll(els =>
      els.map(el => Number((el as HTMLElement).dataset.startLine)));
    expect(nextStart).toBe(rowStarts[rowStarts.indexOf(startLine) + 1]);
  });

  test("does nothing with no focus and no mouse over a file", async ({ page }) => {
    await loadReview(page, token);
    await page.keyboard.press("o");
    await page.keyboard.press("a");
    await expect(section(page, FIRST)).toHaveAttribute("open", "");
    await expect(section(page, SECOND)).toHaveAttribute("open", "");
    await expect(page.locator(".file-header-viewed input:checked")).toHaveCount(0);
  });

  test("tooltips and the shortcuts panel name the keys", async ({ page }) => {
    await loadReview(page, token);
    const header = section(page, FIRST).locator(".file-header");
    await expect(header.locator(".file-header-viewed")).toHaveAttribute("title", "Viewed (a)");
    await expect(header.locator(".file-header-chevron")).toHaveAttribute("title", "Collapse or expand (o)");

    await page.keyboard.press("?");
    const pane = page.locator("#shortcutsPane");
    await expect(pane).toContainText("Toggle viewed on focused file (or file under the mouse)");
    await expect(pane).toContainText("Collapse or expand focused file (or file under the mouse)");
  });
});
