import { test, expect, type APIRequestContext, type Page } from "@playwright/test";
import { codeLine, createReview, deleteReview, loadReview, seedComment } from "./helpers";

// Markdown files get a Document / Source toggle (crit #1106). Source shows
// the whole file in the code view; Document is the rendered default.

const BASE_URL = `http://127.0.0.1:${process.env.CRIT_WEB_TEST_PORT || "4003"}`;

const PLAN = "plan.md";
const NOTES = "notes.md";

async function commentsOf(request: APIRequestContext, token: string) {
  const res = await request.get(`${BASE_URL}/api/reviews/${token}/comments`);
  expect(res.ok()).toBe(true);
  return (await res.json()) as { file_path?: string; file?: string; start_line: number; end_line: number; body: string }[];
}

function section(page: Page, path: string) {
  return page.locator(`details.file-section[data-file-path="${path}"]`);
}

test.describe("Markdown Document / Source toggle", () => {
  let token: string;
  let deleteToken: string;

  test.beforeEach(async ({ request }) => {
    const review = await createReview(request, {
      files: [
        { path: PLAN, content: "# Plan\n\nFirst **step**.\n\nSecond step.\n" },
        { path: NOTES, content: "# Notes\n\nSome notes.\n" },
      ],
    });
    token = review.token;
    deleteToken = review.deleteToken;
  });

  test.afterEach(async ({ request }) => {
    await deleteReview(request, deleteToken);
  });

  test("opens on Document, Source shows the file as code, Document switches back", async ({ page, request }) => {
    await seedComment(request, token, { file: PLAN, startLine: 3, body: "Spell out the step" });
    await loadReview(page, token);
    const file = section(page, PLAN);
    const toggle = file.locator(".file-header .file-header-toggle");
    await expect(toggle.getByRole("button")).toHaveText(["Document", "Source"]);
    await expect(toggle.locator('[data-mode="rendered"]')).toHaveAttribute("aria-pressed", "true");
    await expect(file.locator(".line-content h1")).toHaveText("Plan");
    // The Raw link stays.
    await expect(file.locator(".file-header .crit-round-diff-btn")).toHaveText("Raw");

    await toggle.locator('[data-mode="source"]').click();
    await expect(toggle.locator('[data-mode="source"]')).toHaveAttribute("aria-pressed", "true");
    await expect(codeLine(page, PLAN, 3)).toContainText("First **step**.");
    await expect(file.locator(".line-block")).toHaveCount(0);
    await expect(file.locator(".comment-card")).toContainText("Spell out the step");
    // The click switched views; it did not collapse the file.
    await expect(file).toHaveAttribute("open", "");
    // The other file keeps its own view.
    await expect(section(page, NOTES).locator(".line-content h1")).toHaveText("Notes");

    await toggle.locator('[data-mode="rendered"]').click();
    await expect(file.locator(".line-content h1")).toHaveText("Plan");
    await expect(file.locator(".crit-code-file")).toHaveCount(0);
    await expect(file.locator(".comment-card")).toContainText("Spell out the step");
  });

  test("j/k and c comment on a source line", async ({ page, request }) => {
    await loadReview(page, token);
    const file = section(page, NOTES);
    await file.locator('.file-header-toggle [data-mode="source"]').click();
    await expect(codeLine(page, NOTES, 1)).toContainText("# Notes");
    // Collapse plan.md so j starts in notes.md.
    await section(page, PLAN).locator(".file-header-chevron").click();
    await expect(section(page, PLAN)).not.toHaveAttribute("open", "");

    await page.keyboard.press("j");
    await page.keyboard.press("j");
    await page.keyboard.press("c");
    const form = file.locator(".comment-form");
    await expect(form).toBeVisible();
    await form.locator("textarea").fill("On line two");
    await form.locator("textarea").press("Control+Enter");
    await expect(file.locator(".comment-card")).toContainText("On line two");
    // j twice: lines 1 and 2 of notes.md.
    await expect.poll(async () => (await commentsOf(request, token))
      .filter(c => c.body === "On line two")
      .map(c => `${c.start_line}-${c.end_line}`)).toEqual(["2-2"]);
  });

  test("the toggle is hidden while the round diff is on", async ({ page, request }) => {
    // Two updates leave a previous round to diff against.
    for (const step of ["Second step, changed.", "Second step, changed again."]) {
      const res = await request.put(`${BASE_URL}/api/reviews/${token}`, {
        data: {
          delete_token: deleteToken,
          files: [
            { path: PLAN, content: `# Plan\n\nFirst **step**.\n\n${step}\n` },
            { path: NOTES, content: "# Notes\n\nSome notes.\n" },
          ],
          comments: [],
        },
      });
      expect(res.ok()).toBeTruthy();
    }
    await loadReview(page, token);
    const toggle = section(page, PLAN).locator(".file-header-toggle");
    await toggle.locator('[data-mode="source"]').click();
    await expect(codeLine(page, PLAN, 1)).toContainText("# Plan");

    const roundDiff = page.locator("button.crit-round-diff-btn");
    await roundDiff.click();
    await expect(section(page, PLAN).locator(".diff-view")).toBeVisible();
    await expect(page.locator(".file-header-toggle")).toHaveCount(0);
    await expect(section(page, PLAN).locator(".crit-code-file")).toHaveCount(0);

    // Round diff off: the toggle and the Source view come back.
    await roundDiff.click();
    await expect(toggle.locator('[data-mode="source"]')).toHaveAttribute("aria-pressed", "true");
    await expect(codeLine(page, PLAN, 1)).toContainText("# Plan");
  });
});
