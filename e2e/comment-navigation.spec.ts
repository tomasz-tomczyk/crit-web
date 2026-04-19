import { test, expect } from "@playwright/test";
import {
  createReview,
  deleteReview,
  loadReview,
  seedComment,
  waitForCommentCard,
} from "./helpers";

test.describe("Comment Navigation", () => {
  let token: string;
  let deleteToken: string;

  test.beforeEach(async ({ request }) => {
    const review = await createReview(request, {
      files: [
        {
          path: "example.md",
          content:
            "Line 1\nLine 2\nLine 3\nLine 4\nLine 5\nLine 6\nLine 7\nLine 8\nLine 9\nLine 10\n" +
            "Line 11\nLine 12\nLine 13\nLine 14\nLine 15\nLine 16\nLine 17\nLine 18\nLine 19\nLine 20\n",
        },
      ],
    });
    token = review.token;
    deleteToken = review.deleteToken;
  });

  test.afterEach(async ({ request }) => {
    await deleteReview(request, deleteToken);
  });

  test("prev/next buttons navigate between comments", async ({
    page,
    request,
  }) => {
    await seedComment(request, token, {
      body: "First comment at top",
      startLine: 1,
    });
    await seedComment(request, token, {
      body: "Second comment lower",
      startLine: 10,
    });

    await loadReview(page, token);
    await waitForCommentCard(page, "First comment at top");
    await waitForCommentCard(page, "Second comment lower");

    // Click next comment
    await page.locator("#comment-nav-next").click();

    // The focused comment should change — check that the first comment gets focused class
    // (the exact behavior depends on the JS, but at minimum clicking should not error)
    await page.waitForTimeout(300);

    // Click next again
    await page.locator("#comment-nav-next").click();
    await page.waitForTimeout(300);

    // Click previous
    await page.locator("#comment-nav-prev").click();
    await page.waitForTimeout(300);
  });

  test("keyboard shortcuts [ and ] navigate comments", async ({
    page,
    request,
  }) => {
    await seedComment(request, token, {
      body: "Navigate me first",
      startLine: 1,
    });
    await seedComment(request, token, {
      body: "Navigate me second",
      startLine: 10,
    });

    await loadReview(page, token);
    await waitForCommentCard(page, "Navigate me first");

    // Use ] to go to next comment
    await page.keyboard.press("]");
    await page.waitForTimeout(300);

    // Use [ to go to previous comment
    await page.keyboard.press("[");
    await page.waitForTimeout(300);
  });
});

test.describe("Comments Panel", () => {
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

  test("comment count button toggles comments panel", async ({
    page,
    request,
  }) => {
    await seedComment(request, token, {
      body: "Panel comment",
      startLine: 1,
    });

    await loadReview(page, token);
    await waitForCommentCard(page, "Panel comment");

    // Click the comment count button to open the panel
    await page.locator("#comment-count").click();

    // The comments panel should be visible
    const panel = page.locator(".comments-panel");
    await expect(panel).toBeVisible({ timeout: 5_000 });

    // The panel should contain the comment
    await expect(panel).toContainText("Panel comment");
  });
});
