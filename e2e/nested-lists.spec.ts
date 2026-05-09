import { test, expect } from "@playwright/test";
import { createReview, deleteReview, loadReview } from "./helpers";

test.describe("Nested list rendering — per-item line blocks", () => {
  let token: string;
  let deleteToken: string;

  test.beforeEach(async ({ request }) => {
    const review = await createReview(request, {
      files: [
        {
          path: "nested.md",
          content: [
            "# Nested",
            "",
            "- Top alpha lead.",
            "  - Nested alpha-one.",
            "  - Nested alpha-two.",
            "    - Deep alpha-two-a.",
            "- Top beta lead.",
            "  - Nested beta-one.",
            "",
          ].join("\n"),
        },
      ],
    });
    token = review.token;
    deleteToken = review.deleteToken;
  });

  test.afterEach(async ({ request }) => {
    await deleteReview(request, deleteToken);
  });

  test("each nested bullet item is its own commentable line block", async ({
    page,
  }) => {
    await loadReview(page, token);

    const items = [
      "Top alpha lead.",
      "Nested alpha-one.",
      "Nested alpha-two.",
      "Deep alpha-two-a.",
      "Top beta lead.",
      "Nested beta-one.",
    ];

    const startLines = new Set<string>();
    for (const text of items) {
      const block = page
        .locator("#document-renderer .line-block")
        .filter({ hasText: text })
        .first();
      await expect(block).toBeVisible();
      const startLine = await block.getAttribute("data-start-line");
      expect(startLine, `block for "${text}" should have data-start-line`).toBeTruthy();
      startLines.add(startLine!);
    }

    expect(startLines.size).toBe(items.length);

    await expect(
      page.locator("#document-renderer ul.crit-list-wrapper").first()
    ).toBeAttached();
  });
});
