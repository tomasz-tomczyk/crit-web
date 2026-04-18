import { test, expect, type Page } from "@playwright/test";
import {
  createReview,
  deleteReview,
  loadReview,
  waitForCommentCard,
} from "./helpers";

test.describe("Suggestion Diff Rendering", () => {
  let token: string;
  let deleteToken: string;

  test.beforeEach(async ({ request }) => {
    const review = await createReview(request, {
      files: [
        {
          path: "example.md",
          content:
            "# Hello World\n\nThis is the first line\nThis is the second line\nThis is the third line\n",
        },
      ],
    });
    token = review.token;
    deleteToken = review.deleteToken;
  });

  test.afterEach(async ({ request }) => {
    await deleteReview(request, deleteToken);
  });

  test("renders suggestion block as inline diff", async ({ page }) => {
    await loadReview(page, token);

    // Open comment form on a line
    const gutter = page.locator(".line-gutter").first();
    await gutter.click();

    const textarea = page.locator(".comment-form textarea");
    await expect(textarea).toBeVisible({ timeout: 5_000 });
    await textarea.fill(
      "Here is my suggestion:\n\n```suggestion\nreplacement line\n```\n\nPlease consider this change."
    );

    await page.locator('.comment-form button:has-text("Submit")').click();

    // Wait for comment to render
    await waitForCommentCard(page, "Here is my suggestion");

    // Verify the suggestion diff is rendered
    const suggestionDiff = page.locator(".suggestion-diff");
    await expect(suggestionDiff).toBeVisible({ timeout: 5_000 });

    // Should have a "Suggested change" header
    await expect(
      suggestionDiff.locator(".suggestion-header")
    ).toHaveText("Suggested change");

    // Should have deletion line (original) and addition line (suggestion)
    await expect(
      suggestionDiff.locator(".suggestion-line-del")
    ).toHaveCount(1);
    await expect(
      suggestionDiff.locator(".suggestion-line-add")
    ).toHaveCount(1);

    // The addition line should contain our replacement text
    await expect(
      suggestionDiff.locator(".suggestion-line-add .suggestion-line-content")
    ).toHaveText("replacement line");
  });

  test("regular code blocks do not render as suggestion diff", async ({
    page,
  }) => {
    await loadReview(page, token);

    const gutter = page.locator(".line-gutter").first();
    await gutter.click();

    const textarea = page.locator(".comment-form textarea");
    await expect(textarea).toBeVisible({ timeout: 5_000 });
    await textarea.fill('```javascript\nconsole.log("hello")\n```');

    await page.locator('.comment-form button:has-text("Submit")').click();

    // Wait for comment to render
    await expect(page.locator(".comment-card").first()).toBeVisible({
      timeout: 5_000,
    });

    // Should NOT render as suggestion diff
    await expect(page.locator(".suggestion-diff")).toHaveCount(0);

    // Should render as a normal code block
    const codeBlock = page.locator(".comment-body pre code");
    await expect(codeBlock).toBeVisible();
  });

  test("empty suggestion renders as deletion-only", async ({ page }) => {
    await loadReview(page, token);

    const gutter = page.locator(".line-gutter").first();
    await gutter.click();

    const textarea = page.locator(".comment-form textarea");
    await expect(textarea).toBeVisible({ timeout: 5_000 });
    await textarea.fill("```suggestion\n```");

    await page.locator('.comment-form button:has-text("Submit")').click();

    await expect(page.locator(".comment-card").first()).toBeVisible({
      timeout: 5_000,
    });

    // Should render as suggestion diff with deletion but no addition
    const suggestionDiff = page.locator(".suggestion-diff");
    await expect(suggestionDiff).toBeVisible({ timeout: 5_000 });
    await expect(suggestionDiff.locator(".suggestion-line-del")).toHaveCount(1);
    await expect(suggestionDiff.locator(".suggestion-line-add")).toHaveCount(0);
  });

  test("suggest button inserts suggestion template into textarea", async ({
    page,
  }) => {
    await loadReview(page, token);

    const gutter = page.locator(".line-gutter").first();
    await gutter.click();

    const textarea = page.locator(".comment-form textarea");
    await expect(textarea).toBeVisible({ timeout: 5_000 });

    // Click the Suggest button
    const suggestBtn = page.locator('.comment-form button:has-text("Suggest")');
    await expect(suggestBtn).toBeVisible();
    await suggestBtn.click();

    // Textarea should now contain a suggestion block
    const value = await textarea.inputValue();
    expect(value).toContain("```suggestion");
    expect(value).toContain("```");
  });
});
