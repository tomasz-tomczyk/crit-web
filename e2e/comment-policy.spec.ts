import { test, expect } from "@playwright/test";
import { createReview, deleteReview, loadReview } from "./helpers";

const BASE_URL = `http://localhost:${process.env.CRIT_WEB_TEST_PORT || "4003"}`;

/**
 * Set comment_policy via the API. We can't fully simulate owner-driven UI
 * toggling without a logged-in browser session (no E2E auth helper exists),
 * so we drive the policy change through the seeded admin path instead and
 * verify the viewer-side effects in the browser.
 *
 * Anonymous PUT silently ignores comment_policy, so we use the dev-only
 * seed pattern: create the review with an authenticated bearer token, then
 * PUT with that bearer to set the policy.
 */
async function seedUserAndToken(request) {
  const res = await request.post(`${BASE_URL}/api/test/seed-user`, {
    data: { name: "CP Owner" },
  });
  expect(res.status()).toBe(200);
  return res.json();
}

async function setCommentPolicyAsOwner(
  request,
  token: string,
  deleteToken: string,
  bearer: string,
  policy: "open" | "logged_in_only" | "disallowed"
) {
  const res = await request.put(`${BASE_URL}/api/reviews/${token}`, {
    headers: { Authorization: `Bearer ${bearer}` },
    data: {
      delete_token: deleteToken,
      files: [{ path: "a.md", content: "# hi\n" }],
      comments: [],
      review_round: 1,
      comment_policy: policy,
    },
  });
  expect(res.status()).toBe(200);
  const body = await res.json();
  expect(body.comment_policy).toBe(policy);
}

test.describe("comment policy", () => {
  test("logged_in_only — anon viewer sees the sign-in banner and no add-comment button", async ({
    browser,
    request,
  }) => {
    const { token: bearer } = await seedUserAndToken(request);

    // Create review as the authenticated owner so the bearer scope owns it.
    const createRes = await request.post(`${BASE_URL}/api/reviews`, {
      headers: { Authorization: `Bearer ${bearer}` },
      data: {
        files: [{ path: "a.md", content: "# hi\n" }],
        comments: [],
      },
    });
    expect(createRes.status()).toBe(201);
    const { url, delete_token: deleteToken } = await createRes.json();
    const token = (url as string).split("/r/")[1];

    await setCommentPolicyAsOwner(request, token, deleteToken, bearer, "logged_in_only");

    // Anonymous browser viewer.
    const ctx = await browser.newContext();
    const page = await ctx.newPage();
    await loadReview(page, token);

    await expect(page.locator('[data-test="signin-banner"]')).toBeVisible();
    await expect(page.locator('[data-test="signin-banner"]')).toContainText("Sign-in required");

    // Hidden via crit-no-comments root class.
    await expect(page.locator("html.crit-no-comments")).toHaveCount(1);

    await deleteReview(request, deleteToken);
  });

  test("disallowed — header carries the signal, no body banner, comment affordances hidden", async ({
    browser,
    request,
  }) => {
    const { token: bearer } = await seedUserAndToken(request);

    const createRes = await request.post(`${BASE_URL}/api/reviews`, {
      headers: { Authorization: `Bearer ${bearer}` },
      data: { files: [{ path: "a.md", content: "# hi\n" }], comments: [] },
    });
    const { url, delete_token: deleteToken } = await createRes.json();
    const token = (url as string).split("/r/")[1];

    await setCommentPolicyAsOwner(request, token, deleteToken, bearer, "disallowed");

    const ctx = await browser.newContext();
    const page = await ctx.newPage();
    await loadReview(page, token);

    await expect(page.locator('[data-test="signin-banner"]')).toBeHidden();
    await expect(page.locator('[data-test="comment-policy-badge"]')).toContainText("Disabled");
    await expect(page.locator("html.crit-no-comments")).toHaveCount(1);

    await deleteReview(request, deleteToken);
  });

  test("open — no banner, no badge for anon viewer", async ({ request, page }) => {
    const { token, deleteToken } = await createReview(request);
    await loadReview(page, token);

    await expect(page.locator('[data-test="signin-banner"]')).toBeHidden();
    await expect(page.locator('[data-test="comment-policy-badge"]')).toHaveCount(0);
    await expect(page.locator("html.crit-no-comments")).toHaveCount(0);

    await deleteReview(request, deleteToken);
  });
});
