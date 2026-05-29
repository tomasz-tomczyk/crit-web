import { type Page, type APIRequestContext, type Locator, expect } from "@playwright/test";

// 127.0.0.1, not "localhost": macOS resolves localhost to IPv6 ::1 first, but
// the Phoenix/Bandit test server binds IPv4 only, so API calls to localhost get
// ECONNREFUSED. 127.0.0.1 works on macOS and CI (Linux) alike.
const BASE_URL = `http://127.0.0.1:${process.env.CRIT_WEB_TEST_PORT || "4003"}`;

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
 * A small, self-contained preview page (HTML + CSS + JS) used by the preview
 * E2E spec. The HTML links style.css + app.js and exposes stable, easy-to-target
 * elements (a hero heading and a counter button) so the in-iframe Pin flow has
 * deterministic things to click. JS runs a trivial counter to prove scripts
 * execute inside the iframe.
 */
export const PREVIEW_HTML = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>Preview Demo</title>
  <link rel="stylesheet" href="style.css" />
</head>
<body>
  <main class="card">
    <h1 id="hero">Preview Demo Heading</h1>
    <p class="tagline">A shared static preview.</p>
    <button id="counter" type="button">Clicked 0 times</button>
  </main>
  <script src="app.js"></script>
</body>
</html>
`;

export const PREVIEW_CSS = `body { font-family: system-ui, sans-serif; margin: 0; }
.card { max-width: 480px; margin: 3rem auto; padding: 2rem; }
h1 { font-size: 1.75rem; }
button { padding: 0.5rem 1rem; cursor: pointer; }
`;

export const PREVIEW_JS = `(function () {
  var n = 0;
  var btn = document.getElementById("counter");
  if (btn) {
    btn.addEventListener("click", function () {
      n += 1;
      btn.textContent = "Clicked " + n + " times";
    });
  }
})();
`;

export interface PreviewComment {
  body: string;
  css_selector: string;
  tag_chain?: string[];
  outer_html?: string;
  resolved?: boolean;
  author_identity?: string;
}

/**
 * Create a *preview* review (review_type: "preview") via the API and return
 * { token, url, deleteToken }.
 *
 * Posts an inline html+css+js page plus any DOM-anchored comments. This keeps
 * the preview spec self-contained — it does not depend on the dev/test seed
 * (token "preview-demo-0000"), which the MIX_ENV=test Playwright webServer may
 * not have run.
 *
 * Each comment is stored as a file-scoped comment with a dom_anchor. The
 * comment changeset requires `dom_anchor.pathname` and `dom_anchor.css_selector`
 * to be strings, so both are always supplied.
 */
export async function createPreviewReview(
  request: APIRequestContext,
  opts: {
    htmlFile?: string;
    html?: string;
    css?: string;
    js?: string;
    comments?: PreviewComment[];
  } = {}
) {
  const htmlFile = opts.htmlFile ?? "index.html";

  const files = [
    { path: htmlFile, content: opts.html ?? PREVIEW_HTML, status: "modified" },
    { path: "style.css", content: opts.css ?? PREVIEW_CSS, status: "modified" },
    { path: "app.js", content: opts.js ?? PREVIEW_JS, status: "modified" },
  ];

  const comments = (opts.comments ?? []).map((c) => ({
    start_line: 0,
    end_line: 0,
    body: c.body,
    scope: "file",
    file_path: htmlFile,
    resolved: c.resolved ?? false,
    author_identity: c.author_identity,
    dom_anchor: {
      pathname: "/" + htmlFile,
      css_selector: c.css_selector,
      tag_chain: c.tag_chain ?? [],
      outer_html: c.outer_html ?? "",
    },
  }));

  const body: Record<string, unknown> = {
    review_type: "preview",
    review_round: 0,
    files,
  };
  if (comments.length) body.comments = comments;

  const res = await request.post(`${BASE_URL}/api/reviews`, { data: body });
  expect(res.status()).toBe(201);
  const data = await res.json();
  const token = (data.url as string).split("/r/")[1];
  return {
    token,
    url: data.url as string,
    deleteToken: data.delete_token as string,
    htmlFile,
  };
}

/**
 * Navigate to a preview review and wait for the PreviewMode chrome + iframe.
 * Returns a FrameLocator scoped to the preview iframe.
 */
export async function loadPreview(page: Page, token: string) {
  await page.goto(`/r/${token}`);
  await page.waitForSelector("#crit-preview-layout #critPreviewIframe", {
    timeout: 15_000,
  });
  // Wait for the hook's init to point the iframe at the raw HTML route.
  await page.waitForFunction(
    () => {
      const f = document.querySelector(
        "#critPreviewIframe"
      ) as HTMLIFrameElement | null;
      return !!f && /\/raw\//.test(f.src || "");
    },
    { timeout: 15_000 }
  );
  return page.frameLocator("#critPreviewIframe");
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

/**
 * Add a comment via the UI (click gutter, type, submit with Ctrl+Enter).
 * The comment is owned by the current session identity, so edit/delete/resolve
 * buttons will be visible.
 *
 * @param waitText - text to wait for in the comment card. Use when the body
 *   contains markdown that transforms (e.g. `**bold**` renders as `<strong>`),
 *   so the raw body won't appear as text in the card.
 */
export async function addCommentViaUI(
  page: Page,
  body: string,
  opts: { lineIndex?: number; waitText?: string } = {}
) {
  const gutter = page.locator(".line-gutter").nth(opts.lineIndex ?? 0);
  await gutter.click();

  const textarea = page.locator(".comment-form textarea");
  await expect(textarea).toBeVisible({ timeout: 5_000 });
  await textarea.fill(body);
  await textarea.press("Control+Enter");

  if (opts.waitText) {
    await waitForCommentCard(page, opts.waitText);
  } else {
    await waitForCommentCard(page, body);
  }
}
