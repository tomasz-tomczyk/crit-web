import { test, expect, type Page } from "@playwright/test";
import { createReview, deleteReview, loadReview } from "./helpers";

// Templates come from crit's shared module (vendored crit-comment-templates.js),
// on localStorage: texts in `crit-templates`, title, emoji, shortcut, display
// and pin in `crit-template-meta`. The first use seeds 👍 Accepted (Alt+P) and
// 👎 Rejected (Alt+C), shown in the selection toolbar. They are edited in
// Settings > Comment templates, unfolded in place: there is no template dialog.

async function openCommentForm(page: Page) {
  const gutter = page.locator(".line-gutter").first();
  await gutter.click();
  await expect(page.locator(".comment-form")).toBeVisible({ timeout: 5_000 });
}

const saveBtn = (page: Page) => page.locator(".comment-form-actions button", { hasText: "+ Template" });
const chips = (page: Page) => page.locator(".comment-form .comment-template-bar .template-chip");
const pane = (page: Page) => page.locator("#templatesPane");
const rows = (page: Page) => pane(page).locator(".settings-template-row");
const editor = (page: Page) => pane(page).locator(".settings-template-editor");
const displayButtons = (page: Page) => editor(page).locator(".template-display .settings-pill-btn");
// "Hide from selection toolbar", off by default like "Hide resolved comments".
const hideSwitch = (page: Page) => editor(page).getByLabel("Hide from the selection toolbar");
const hideLine = (page: Page) => editor(page).locator(".settings-template-line", { hasText: "Hide from selection toolbar" });

async function openTemplatesTab(page: Page) {
  await page.locator("#settingsToggle").click();
  await page.locator('.settings-tab[data-tab="templates"]').click();
  await expect(rows(page).first()).toBeVisible();
}

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

  test("+ Template opens the tab on a new template filled from the form, and the form keeps its draft", async ({ page }) => {
    await loadReview(page, token);
    await openCommentForm(page);
    const textarea = page.locator(".comment-form textarea");
    await textarea.fill("Please add a unit test for this branch.");
    await saveBtn(page).click();

    await expect(editor(page).locator(".settings-template-editor-head")).toHaveText("New template");
    await expect(editor(page).locator(".settings-template-text-input")).toHaveValue("Please add a unit test for this branch.");
    await expect(hideSwitch(page)).not.toBeChecked();
    await expect(displayButtons(page)).toHaveText(["Icon", "Text", "Both"]);
    await expect(displayButtons(page).nth(0)).toBeDisabled();
    await expect(displayButtons(page).nth(1)).toHaveClass(/active/);

    await editor(page).locator(".settings-template-name-input").fill("Ask for tests");
    await editor(page).locator(".settings-template-emoji-input").fill("🧪");
    await editor(page).locator('[data-display="both"]').click();
    await editor(page).locator("button", { hasText: "Save" }).click();
    await expect(editor(page)).toHaveCount(0);
    await expect(rows(page)).toHaveCount(3);

    await page.locator("#settingsClose").click();
    await expect(textarea).toHaveValue("Please add a unit test for this branch.");
    await expect(chips(page)).toHaveCount(3);
    await expect(chips(page).nth(2)).toHaveText("🧪Ask for tests");

    const meta = await page.evaluate(() => JSON.parse(localStorage.getItem("crit-template-meta") || "{}"));
    expect(meta.items["Please add a unit test for this branch."]).toMatchObject({ title: "Ask for tests", emoji: "🧪", display: "both", pinned: true });
  });

  test("a chip's edit button opens its template unfolded; delete needs a confirmation", async ({ page }) => {
    await loadReview(page, token);
    await openCommentForm(page);
    await chips(page).nth(1).locator(".template-chip-edit").click();
    await expect(editor(page).locator(".settings-template-text-input")).toHaveValue("Rejected");
    await expect(editor(page).locator(".template-shortcut")).toHaveText("Alt+c");
    await expect(hideSwitch(page)).not.toBeChecked();

    await editor(page).locator(".settings-template-delete").click();
    await expect(editor(page).locator("button", { hasText: "Keep" })).toBeFocused();
    await page.keyboard.press("Enter");
    await expect(rows(page)).toHaveCount(1);
    await editor(page).locator(".settings-template-delete").click();
    await editor(page).locator(".btn-danger", { hasText: "Delete" }).click();
    await expect(editor(page)).toHaveCount(0);
    await expect(rows(page)).toHaveCount(1);
    await page.locator("#settingsClose").click();
    await expect(chips(page)).toHaveCount(1);
    await expect(chips(page).first()).toHaveText("👍Accepted");
  });

  test("a shortcut already taken is refused, a free one is kept", async ({ page }) => {
    await loadReview(page, token);
    await openTemplatesTab(page);
    await rows(page).nth(0).locator(".settings-template-action").click();
    const shortcut = editor(page).locator(".template-shortcut");
    await expect(shortcut).toHaveText("Alt+p");
    await shortcut.click();
    await page.keyboard.press("c");
    await expect(page.locator(".mini-toast", { hasText: "c already does" })).toBeVisible();
    await shortcut.click();
    await page.keyboard.press("y");
    await expect(shortcut).toHaveText("y");
    await editor(page).locator("button", { hasText: "Save" }).click();
    const meta = await page.evaluate(() => JSON.parse(localStorage.getItem("crit-template-meta") || "{}"));
    expect(meta.items.Accepted.shortcut).toBe("y");
  });

  test("Esc and Cancel fold the editor without closing Settings or saving", async ({ page }) => {
    await loadReview(page, token);
    await openTemplatesTab(page);
    await rows(page).nth(0).locator(".settings-template-action").click();
    await editor(page).locator(".settings-template-name-input").fill("Changed?");
    await page.keyboard.press("Escape");
    await expect(editor(page)).toHaveCount(0);
    await expect(pane(page)).toBeVisible();
    await expect(rows(page).nth(0).locator(".settings-template-name")).toHaveText("Accepted");

    await pane(page).locator(".settings-template-new").click();
    await editor(page).locator(".settings-template-text-input").fill("Cancel me");
    await editor(page).locator("button", { hasText: "Cancel" }).click();
    await expect(rows(page)).toHaveCount(2);
  });

  test("the tab lists templates without switch, adds one and reorders by drag; open forms follow", async ({ page }) => {
    await loadReview(page, token);
    await openCommentForm(page);
    await page.locator(".comment-form textarea").evaluate((el: HTMLTextAreaElement) => el.blur());
    await openTemplatesTab(page);
    await expect(rows(page)).toHaveCount(2);
    await expect(rows(page).locator("button")).toHaveCount(2);
    await expect(rows(page).locator(".comments-panel-switch")).toHaveCount(0);

    await pane(page).locator(".settings-template-new").click();
    await editor(page).locator(".settings-template-text-input").fill("Out of scope for this change.");
    await editor(page).locator(".settings-template-name-input").fill("Out of scope");
    await page.keyboard.press("Control+Enter");
    await expect(rows(page)).toHaveCount(3);

    await rows(page).nth(1).locator(".settings-template-handle").dragTo(rows(page).nth(0), { targetPosition: { x: 40, y: 3 } });
    await expect(rows(page).locator(".settings-template-name")).toHaveText(["Rejected", "Accepted", "Out of scope"]);

    await page.locator("#settingsClose").click();
    await expect(chips(page).locator(".template-chip-label")).toHaveText(["Rejected", "Accepted", "Out of scope"]);
  });

  test("Hide shortcut in selection toolbar shows for a template with a key in the toolbar", async ({ page }) => {
    await loadReview(page, token);
    await openTemplatesTab(page);
    await rows(page).nth(0).locator(".settings-template-action").click();
    const keyLine = editor(page).locator(".settings-template-line", { hasText: "Hide shortcut in selection toolbar" });
    await expect(keyLine).toBeVisible();
    await hideLine(page).locator("label.comments-panel-switch").click();
    await expect(keyLine).toBeHidden();
    await hideLine(page).locator("label.comments-panel-switch").click();
    await keyLine.locator("label.comments-panel-switch").click();
    await editor(page).locator("button", { hasText: "Save" }).click();
    const meta = await page.evaluate(() => JSON.parse(localStorage.getItem("crit-template-meta") || "{}"));
    expect(meta.items.Accepted).toMatchObject({ shortcut: "Alt+p", hideShortcut: true });
  });

  test("Hide from selection toolbar is locked while the toolbar hides comment templates", async ({ page }) => {
    await loadReview(page, token);
    await page.evaluate(() => {
      document.cookie = "crit-settings=" + encodeURIComponent(JSON.stringify({ selectionToolbarTemplates: false })) + "; path=/; SameSite=Lax";
    });
    await openTemplatesTab(page);
    await rows(page).nth(0).locator(".settings-template-action").click();
    await expect(hideSwitch(page)).toBeDisabled();
    await expect(hideLine(page)).toHaveAttribute("title", /Hide comment templates/);
  });

  test("template shortcuts close the Shortcuts tab and change there", async ({ page }) => {
    await loadReview(page, token);
    await page.locator("#settingsToggle").click();
    await page.locator('.settings-tab[data-tab="shortcuts"]').click();
    const templateKeys = page.locator("#shortcutsPane [data-template-index]");
    await expect(templateKeys).toHaveCount(2);
    await expect(templateKeys.nth(0)).toHaveText("Alt+p");
    await templateKeys.nth(1).click();
    await page.keyboard.press("Alt+n");
    await expect(templateKeys.nth(1)).toHaveText("Alt+n");
    const meta = await page.evaluate(() => JSON.parse(localStorage.getItem("crit-template-meta") || "{}"));
    expect(meta.items.Rejected.shortcut).toBe("Alt+n");
  });
});
