import { test, expect } from "@playwright/test";
import { createReview, deleteReview, loadReview, seedComment } from "./helpers";

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

  test("returns 404 flash for invalid token", async ({ page }) => {
    await page.goto("/r/nonexistent-token-12345");
    // Should redirect to home with flash error
    await expect(page).toHaveURL("/");
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
