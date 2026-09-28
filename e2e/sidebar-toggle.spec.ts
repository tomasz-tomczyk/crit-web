import { test, expect, type APIRequestContext, type Page } from "@playwright/test";
import { createMultiFileReview, createReview, deleteReview, loadReview, seedComment } from "./helpers";

const BASE_URL = `http://127.0.0.1:${process.env.CRIT_WEB_TEST_PORT || "4003"}`;

function collapsed(page: Page) {
  return page.evaluate(() => document.body.classList.contains("file-tree-collapsed"));
}

// Log in as the owner of a new multi-file review. The owner can change the
// comment policy, which patches the header without re-rendering the document
// (canComment stays true for the owner), so JS-owned header state has to
// survive the patch on its own.
async function ownerReview(request: APIRequestContext, page: Page) {
  const seed = await request.post(`${BASE_URL}/api/test/seed-user`, { data: { name: "Sidebar Owner" } });
  expect(seed.status()).toBe(200);
  const { user_id: userId, token: bearer } = await seed.json();
  const res = await request.post(`${BASE_URL}/api/reviews`, {
    headers: { Authorization: `Bearer ${bearer}` },
    data: {
      files: [
        { path: "src/main.ts", content: "export const a = 1;\n" },
        { path: "README.md", content: "# Project\n\nIntro.\n" },
      ],
      comments: [],
    },
  });
  expect(res.status()).toBe(201);
  const { url, delete_token: deleteToken } = await res.json();
  const token = (url as string).split("/r/")[1];
  await page.goto(`/test/login-as/${userId}`);
  return { token, deleteToken };
}

test.describe("File tree sidebar toggle", () => {
  let token: string;
  let deleteToken: string;

  test.beforeEach(async ({ request }) => {
    const review = await createMultiFileReview(request);
    token = review.token;
    deleteToken = review.deleteToken;
  });

  test.afterEach(async ({ request }) => {
    await deleteReview(request, deleteToken);
  });

  test("click and `b` toggle the sidebar, and the state persists", async ({ page }) => {
    await loadReview(page, token);
    const toggle = page.locator("#fileTreeToggle");
    await expect(toggle).toBeVisible();
    await expect(toggle).toHaveAttribute("aria-expanded", "true");
    expect(await collapsed(page)).toBe(false);

    await toggle.click();
    await expect.poll(() => collapsed(page)).toBe(true);
    await expect(toggle).toHaveAttribute("aria-expanded", "false");
    await expect(toggle).toHaveAttribute("aria-label", "Show sidebar");
    await expect(toggle).toHaveAttribute("title", "Show sidebar (b)");

    await page.keyboard.press("b");
    await expect.poll(() => collapsed(page)).toBe(false);
    await expect(toggle).toHaveAttribute("aria-expanded", "true");

    await page.keyboard.press("b");
    await expect.poll(() => collapsed(page)).toBe(true);

    await loadReview(page, token);
    await expect.poll(() => collapsed(page)).toBe(true);
    await expect(page.locator("#fileTreeToggle")).toHaveAttribute("aria-expanded", "false");
  });

  test("rebinding the shortcut updates the toggle's title", async ({ page }) => {
    await loadReview(page, token);
    await page.keyboard.press("?");
    await page.locator('[data-shortcut-id="toggle_file_tree"]').click();
    await page.keyboard.press("m");
    await expect(page.locator('[data-shortcut-id="toggle_file_tree"]')).toContainText("m");
    await expect(page.locator("#fileTreeToggle")).toHaveAttribute("title", "Hide sidebar (m)");
  });
});

test("JS-owned header state survives a LiveView patch", async ({ page, request }) => {
  const { token, deleteToken } = await ownerReview(request, page);
  await seedComment(request, token, { file: "README.md" });
  await loadReview(page, token);

  const toggle = page.locator("#fileTreeToggle");
  const viewed = page.locator("#viewedCount");
  const count = page.locator("#commentCountNumber");
  await expect(toggle).toBeVisible();
  await expect(viewed).toContainText("files viewed");
  await expect(count).toHaveText("1");
  await toggle.click();
  await expect(toggle).toHaveAttribute("aria-expanded", "false");

  await page.locator("#comment-policy-menu-trigger").click();
  await page.locator('[data-test="comment-policy-set-logged_in_only"]').click();
  await expect(page.locator("#comment-policy-menu-trigger")).toContainText("Login required");

  await expect(toggle).toBeVisible();
  await expect(toggle).toHaveAttribute("aria-expanded", "false");
  await expect(toggle).toHaveAttribute("aria-label", "Show sidebar");
  await expect(toggle).toHaveAttribute("title", "Show sidebar (b)");
  await expect(viewed).toBeVisible();
  await expect(viewed).toContainText("files viewed");
  await expect(count).toHaveText("1");
  await expect(page.locator("#comment-count")).toHaveAttribute("title", /1 unresolved comment/);
  expect(await collapsed(page)).toBe(true);

  await deleteReview(request, deleteToken);
});

test("the sidebar toggle is hidden on single-file reviews", async ({ page, request }) => {
  const { token, deleteToken } = await createReview(request);
  await loadReview(page, token);
  await expect(page.locator("#fileTreeToggle")).toBeHidden();
  // `b` is a no-op without the control.
  await page.keyboard.press("b");
  expect(await collapsed(page)).toBe(false);
  await deleteReview(request, deleteToken);
});
