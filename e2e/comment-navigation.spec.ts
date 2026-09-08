import { test, expect } from "@playwright/test";
import {
  createReview,
  deleteReview,
  loadReview,
  seedComment,
  waitForCommentCard,
} from "./helpers";

/**
 * Navigation jumps add a transient `.comment-nav-highlight` class to the
 * target card (removed again after ~1s), so assertions are fully
 * condition-based — no sleeps needed.
 */
const highlightedCard = (page: import("@playwright/test").Page) =>
  page.locator(".comment-card.comment-nav-highlight");

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

  async function seedTwoComments(request: Parameters<typeof seedComment>[0]) {
    await seedComment(request, token, {
      body: "First comment at top",
      startLine: 1,
    });
    await seedComment(request, token, {
      body: "Second comment lower",
      startLine: 10,
    });
  }

  test("prev/next buttons navigate between comments", async ({
    page,
    request,
  }) => {
    await seedTwoComments(request);

    await loadReview(page, token);
    const first = page
      .locator(".comment-card")
      .filter({ hasText: "First comment at top" });
    const second = page
      .locator(".comment-card")
      .filter({ hasText: "Second comment lower" });
    await waitForCommentCard(page, "First comment at top");
    await waitForCommentCard(page, "Second comment lower");

    // Next → highlights the first comment
    await page.locator("#comment-nav-next").click();
    await expect(first).toHaveClass(/comment-nav-highlight/);

    // Wait for the transient highlight to clear before the next jump
    await expect(first).not.toHaveClass(/comment-nav-highlight/);

    // Next again → highlights the second comment
    await page.locator("#comment-nav-next").click();
    await expect(second).toHaveClass(/comment-nav-highlight/);
    await expect(second).not.toHaveClass(/comment-nav-highlight/);

    // Previous → back to the first comment
    await page.locator("#comment-nav-prev").click();
    await expect(first).toHaveClass(/comment-nav-highlight/);
  });

  test("keyboard shortcuts [ and ] navigate comments", async ({
    page,
    request,
  }) => {
    await seedTwoComments(request);

    await loadReview(page, token);
    const first = page
      .locator(".comment-card")
      .filter({ hasText: "First comment at top" });
    const second = page
      .locator(".comment-card")
      .filter({ hasText: "Second comment lower" });
    await waitForCommentCard(page, "First comment at top");
    await waitForCommentCard(page, "Second comment lower");

    // ] → next comment gets highlighted
    await page.keyboard.press("]");
    await expect(highlightedCard(page)).toHaveCount(1);
    await expect(first).toHaveClass(/comment-nav-highlight/);
    await expect(first).not.toHaveClass(/comment-nav-highlight/);

    // ] again → the second comment
    await page.keyboard.press("]");
    await expect(second).toHaveClass(/comment-nav-highlight/);
    await expect(second).not.toHaveClass(/comment-nav-highlight/);

    // [ → back to the first comment
    await page.keyboard.press("[");
    await expect(first).toHaveClass(/comment-nav-highlight/);
  });
});
