import { test, expect, type Page } from "@playwright/test";
import { createReview, deleteReview, loadReview } from "./helpers";

// Templates come from crit's shared module (vendored crit-comment-templates.js),
// on localStorage: texts in `crit-templates`, title, emoji, shortcut, display
// and pin in `crit-template-meta`. The first use seeds 👍 Accepted and
// 👎 Rejected, pinned.

async function openCommentForm(page: Page) {
  const gutter = page.locator(".line-gutter").first();
  await gutter.click();
  await expect(page.locator(".comment-form")).toBeVisible({ timeout: 5_000 });
}

const saveBtn = (page: Page) => page.locator(".comment-form-actions button", { hasText: "+ Template" });
const chips = (page: Page) => page.locator(".comment-form .comment-template-bar .template-chip");
const dialog = (page: Page) => page.locator(".save-template-dialog");
const displayButtons = (page: Page) => dialog(page).locator(".template-display .settings-pill-btn");

test.describe("Comment Templates", () => {
  let token: string;
  let deleteToken: string;

  test.beforeEach(async ({ page, request }) => {
    const review = await createReview(request);
    token = review.token;
    deleteToken = review.deleteToken;
    await page.goto("/");
    await page.evaluate(() => {
      localStorage.removeItem("crit-templates");
      localStorage.removeItem("crit-template-meta");
    });
  });

  test.afterEach(async ({ request }) => {
    await deleteReview(request, deleteToken);
  });

  test("a fresh start offers 👍 Accepted and 👎 Rejected, pinned first, with an edit button and no ×", async ({ page }) => {
    await loadReview(page, token);
    await openCommentForm(page);
    await expect(chips(page)).toHaveCount(2);
    await expect(chips(page).nth(0)).toHaveText("👍Accepted");
    await expect(chips(page).nth(1)).toHaveText("👎Rejected");
    await expect(chips(page).nth(0)).toHaveClass(/template-chip--pinned/);
    await expect(chips(page).locator(".template-chip-edit")).toHaveCount(2);
    await expect(chips(page).locator(".template-chip-delete")).toHaveCount(0);
  });

  test("save a template with a title, emoji, display and pin; its chip inserts the text", async ({ page }) => {
    await loadReview(page, token);
    await openCommentForm(page);
    const textarea = page.locator(".comment-form textarea");
    await textarea.fill("Please add a unit test for this branch.");
    await saveBtn(page).click();

    await expect(dialog(page).locator("h3")).toHaveText("Save as template");
    await expect(dialog(page).locator(".save-template-input")).toHaveValue("Please add a unit test for this branch.");
    await expect(dialog(page).locator(".template-display")).toBeHidden();
    await dialog(page).getByLabel("Pin to the selection toolbar").check();
    await expect(displayButtons(page).nth(0)).toBeDisabled();
    await expect(displayButtons(page).nth(1)).toHaveClass(/active/);

    await dialog(page).locator(".save-template-title").fill("Ask for tests");
    await dialog(page).locator(".save-template-emoji").fill("🧪");
    await dialog(page).locator('[data-display="both"]').click();
    await dialog(page).locator("button", { hasText: "Save" }).click();
    await expect(dialog(page)).toHaveCount(0);

    await expect(chips(page)).toHaveCount(3);
    await expect(chips(page).nth(2)).toHaveText("🧪Ask for tests");
    await textarea.fill("");
    await chips(page).nth(2).click();
    await expect(textarea).toHaveValue("Please add a unit test for this branch.");

    const meta = await page.evaluate(() => JSON.parse(localStorage.getItem("crit-template-meta") || "{}"));
    expect(meta.items["Please add a unit test for this branch."]).toMatchObject({ title: "Ask for tests", emoji: "🧪", display: "both", pinned: true });
  });

  test("the edit button reopens the dialog filled in; delete needs a confirmation", async ({ page }) => {
    await loadReview(page, token);
    await openCommentForm(page);
    await chips(page).nth(1).locator(".template-chip-edit").click();
    await expect(dialog(page).locator("h3")).toHaveText("Edit template");
    await expect(dialog(page).locator(".save-template-input")).toHaveValue("Rejected");
    await expect(dialog(page).getByLabel("Pin to the selection toolbar")).toBeChecked();

    await dialog(page).locator(".save-template-delete").click();
    await expect(dialog(page).locator("button", { hasText: "Keep" })).toBeFocused();
    await page.keyboard.press("Enter");
    await expect(chips(page)).toHaveCount(2);
    await dialog(page).locator(".save-template-delete").click();
    await dialog(page).locator(".btn-danger", { hasText: "Delete" }).click();
    await expect(dialog(page)).toHaveCount(0);
    await expect(chips(page)).toHaveCount(1);
    await expect(chips(page).first()).toHaveText("👍Accepted");
  });

  test("a shortcut already taken is refused, a free one is kept", async ({ page }) => {
    await loadReview(page, token);
    await openCommentForm(page);
    await chips(page).nth(0).locator(".template-chip-edit").click();
    const shortcut = dialog(page).locator(".template-shortcut");
    await shortcut.click();
    await page.keyboard.press("c");
    await expect(page.locator(".mini-toast", { hasText: "c already does" })).toBeVisible();
    await shortcut.click();
    await page.keyboard.press("y");
    await expect(shortcut).toHaveText("y");
    await dialog(page).locator("button", { hasText: "Save" }).click();
    const meta = await page.evaluate(() => JSON.parse(localStorage.getItem("crit-template-meta") || "{}"));
    expect(meta.items.Accepted.shortcut).toBe("y");
  });

  test("the save dialog does nothing for an empty form, and can be cancelled", async ({ page }) => {
    await loadReview(page, token);
    await openCommentForm(page);
    await saveBtn(page).click();
    await expect(dialog(page)).toHaveCount(0);

    await page.locator(".comment-form textarea").fill("Cancel me");
    await saveBtn(page).click();
    await expect(dialog(page)).toBeVisible();
    await dialog(page).locator("button", { hasText: "Cancel" }).click();
    await expect(dialog(page)).toHaveCount(0);
    await expect(chips(page)).toHaveCount(2);
  });

  test("Settings list templates, create them in the dialog and reorder by drag; open forms follow", async ({ page }) => {
    await loadReview(page, token);
    await openCommentForm(page);
    await page.locator(".comment-form textarea").evaluate((el: HTMLTextAreaElement) => el.blur());
    await page.locator("#settingsToggle").click();
    const rows = page.locator("#settingsTemplates .settings-template-row");
    await expect(rows).toHaveCount(2);
    await expect(rows.locator("button")).toHaveCount(2);

    await page.locator(".settings-template-new").click();
    await dialog(page).locator(".save-template-input").fill("Out of scope for this change.");
    await dialog(page).locator(".save-template-title").fill("Out of scope");
    await page.keyboard.press("Control+Enter");
    await expect(rows).toHaveCount(3);

    await rows.nth(1).locator(".settings-template-handle").dragTo(rows.nth(0), { targetPosition: { x: 40, y: 3 } });
    await expect(rows.locator(".settings-template-name")).toHaveText(["Rejected", "Accepted", "Out of scope"]);

    await page.locator("#settingsClose").click();
    await expect(chips(page).locator(".template-chip-label")).toHaveText(["Rejected", "Accepted", "Out of scope"]);
  });
});
