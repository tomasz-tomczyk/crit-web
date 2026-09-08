import { test, expect } from "@playwright/test";
import { createReview, deleteReview, loadReview } from "./helpers";

test.describe("Drag Selection — Multi-line Comment Range", () => {
  let token: string;
  let deleteToken: string;

  test.beforeEach(async ({ request }) => {
    // Use a markdown list so each item becomes its own line-block
    const review = await createReview(request, {
      files: [
        {
          path: "example.md",
          content:
            "# Heading\n\n- Item one\n- Item two\n- Item three\n- Item four\n- Item five\n",
        },
      ],
    });
    token = review.token;
    deleteToken = review.deleteToken;
  });

  test.afterEach(async ({ request }) => {
    await deleteReview(request, deleteToken);
  });

  test("dragging across gutter elements opens comment form with multi-line header", async ({
    page,
  }) => {
    await loadReview(page, token);

    const gutters = page.locator(".line-gutter");
    const firstGutter = gutters.nth(0);
    const thirdGutter = gutters.nth(2);

    await expect(firstGutter).toBeAttached();
    await expect(thirdGutter).toBeAttached();

    // Perform drag from first to third gutter
    const firstBox = await firstGutter.boundingBox();
    const thirdBox = await thirdGutter.boundingBox();
    expect(firstBox).toBeTruthy();
    expect(thirdBox).toBeTruthy();

    await page.mouse.move(firstBox!.x + firstBox!.width / 2, firstBox!.y + firstBox!.height / 2);
    await page.mouse.down();
    await page.mouse.move(thirdBox!.x + thirdBox!.width / 2, thirdBox!.y + thirdBox!.height / 2, { steps: 5 });
    await page.mouse.up();

    // Comment form should open with "Lines" in the header (multi-line range)
    const form = page.locator(".comment-form");
    await expect(form).toBeVisible({ timeout: 5_000 });

    const header = page.locator(".comment-form-header");
    await expect(header).toContainText("Lines");

    // Submitting the range form creates one comment card
    const textarea = form.locator("textarea");
    await textarea.fill("Comment spanning three lines");
    await textarea.press("Control+Enter");
    await expect(
      page.locator(".comment-card").filter({ hasText: "Comment spanning three lines" })
    ).toBeVisible({ timeout: 5_000 });
  });

  test("after drag, selected line blocks have .selected class", async ({
    page,
  }) => {
    await loadReview(page, token);

    const gutters = page.locator(".line-gutter");
    const firstGutter = gutters.nth(0);
    const thirdGutter = gutters.nth(2);

    await expect(firstGutter).toBeAttached();
    await expect(thirdGutter).toBeAttached();

    const firstBox = await firstGutter.boundingBox();
    const thirdBox = await thirdGutter.boundingBox();

    await page.mouse.move(firstBox!.x + firstBox!.width / 2, firstBox!.y + firstBox!.height / 2);
    await page.mouse.down();
    await page.mouse.move(thirdBox!.x + thirdBox!.width / 2, thirdBox!.y + thirdBox!.height / 2, { steps: 5 });
    await page.mouse.up();

    // At least one line block should have the selected class
    const selectedBlocks = page.locator(".line-block.selected");
    const count = await selectedBlocks.count();
    expect(count).toBeGreaterThanOrEqual(1);
  });

  test("single click on gutter opens single-line comment form", async ({
    page,
  }) => {
    await loadReview(page, token);

    // Click on a specific line block's gutter (skip the heading, use a list item)
    const gutters = page.locator(".line-gutter");
    const count = await gutters.count();
    // Use the second gutter (first list item) to avoid the heading block
    const gutter = count > 1 ? gutters.nth(1) : gutters.first();
    await gutter.click();

    const form = page.locator(".comment-form");
    await expect(form).toBeVisible({ timeout: 5_000 });

    const header = page.locator(".comment-form-header");
    await expect(header).toContainText("Line");
  });

  test("Shift+click extends selection from anchor to a multi-line range", async ({
    page,
  }) => {
    await loadReview(page, token);

    const gutters = page.locator(".line-gutter");
    const count = await gutters.count();
    expect(count).toBeGreaterThanOrEqual(4);

    // Plain click sets the anchor (single-line form)
    await gutters.nth(1).click();
    await expect(page.locator(".comment-form-header")).toContainText("Line");

    // Shift+click a lower gutter: the anchor extends into a range and the
    // form re-opens with a "Lines x–y" header
    await gutters.nth(3).click({ modifiers: ["Shift"] });

    const form = page.locator(".comment-form");
    await expect(form).toBeVisible({ timeout: 5_000 });
    await expect(page.locator(".comment-form-header")).toContainText("Lines");
    await expect(form).toHaveCount(1);
  });
});
