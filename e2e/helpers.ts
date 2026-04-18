import { type Page, type APIRequestContext, expect } from "@playwright/test";

const BASE_URL = `http://localhost:${process.env.CRIT_WEB_TEST_PORT || "4003"}`;

/**
 * Create a review via the API and return { token, url, deleteToken }.
 */
export async function createReview(
  request: APIRequestContext,
  opts: {
    files?: Array<{ path: string; content: string; status?: string }>;
    comments?: Array<{
      start_line: number;
      end_line: number;
      body: string;
      file?: string;
      author_identity?: string;
    }>;
    reviewRound?: number;
  } = {}
) {
  const files = opts.files ?? [
    {
      path: "example.md",
      content: "# Hello World\n\nThis is line 1\nThis is line 2\nThis is line 3\n",
    },
  ];

  const body: Record<string, unknown> = {
    files,
    review_round: opts.reviewRound ?? 0,
  };

  if (opts.comments) {
    body.comments = opts.comments;
  }

  const res = await request.post(`${BASE_URL}/api/reviews`, { data: body });
  expect(res.status()).toBe(201);
  const data = await res.json();
  const token = (data.url as string).split("/r/")[1];
  return { token, url: data.url as string, deleteToken: data.delete_token as string };
}

/**
 * Delete a review via the API.
 */
export async function deleteReview(
  request: APIRequestContext,
  deleteToken: string
) {
  const res = await request.delete(`${BASE_URL}/api/reviews`, {
    data: { delete_token: deleteToken },
  });
  expect(res.status()).toBe(204);
}

/**
 * Add a comment to a review via the seed-comment test endpoint.
 */
export async function seedComment(
  request: APIRequestContext,
  token: string,
  opts: {
    body?: string;
    startLine?: number;
    endLine?: number;
    file?: string;
    scope?: string;
  } = {}
) {
  const data: Record<string, unknown> = {
    body: opts.body ?? "Test comment",
    start_line: opts.startLine ?? 1,
    end_line: opts.endLine ?? opts.startLine ?? 1,
    scope: opts.scope ?? "line",
  };

  if (opts.file) data.file = opts.file;

  const res = await request.post(
    `${BASE_URL}/api/reviews/${token}/seed-comment`,
    { data }
  );
  expect(res.status()).toBe(200);
  return res.json();
}

/**
 * Navigate to a review page and wait for the document to render.
 */
export async function loadReview(page: Page, token: string) {
  await page.goto(`/r/${token}`);
  // Wait for the LiveView to connect and the document renderer to initialize
  await page.waitForSelector("#document-renderer .line-block", {
    timeout: 15_000,
  });
}

/**
 * Wait for a comment card to appear in the document.
 */
export async function waitForCommentCard(page: Page, bodyText?: string) {
  if (bodyText) {
    await expect(
      page.locator(".comment-card").filter({ hasText: bodyText })
    ).toBeVisible({ timeout: 10_000 });
  } else {
    await expect(page.locator(".comment-card").first()).toBeVisible({
      timeout: 10_000,
    });
  }
}
