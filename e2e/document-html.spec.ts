import { test, expect } from "@playwright/test";
import { createReview, deleteReview, loadReview } from "./helpers";

// Raw HTML in a shared document must not run script on the review page.
const CONTENT = [
  "# Raw HTML",
  "",
  'before <img src=x onerror="window.__xss=1"> after',
  "",
  '<div onclick="window.__xss=1"><script>window.__xss=1</script>block</div>',
  "",
  'a <a href="javascript:window.__xss=1">bad</a> link',
  "",
  "<details><summary>More</summary>hidden</details>",
  "",
  '<div class="overlay" style="position:fixed;inset:0">cover</div>',
  "",
  // A real review-page class (a fixed, full-page overlay), a page id, and a
  // fake comment card that comment links would jump to.
  '<div class="crit-prompt-overlay" id="commentsPanel">overlay class</div>',
  "",
  '<div class="comment-card" data-comment-id="fake-card">fake card</div>',
  "",
  // Id references: a label for a real review-page button, and every other
  // attribute that names ids.
  '<label for="settingsToggle">open settings</label>',
  "",
  '<span aria-labelledby="a b" aria-describedby="c" aria-controls="d" aria-owns="e">aria refs</span>',
  "",
  '<input list="choices" aria-label="list ref">',
  "",
  '<table><tr><td headers="h1 h2">cell ref</td></tr></table>',
  "",
  '<img alt="map ref" usemap=" #shapes" src="data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"><map name="shapes"></map>',
  "",
].join("\n");

test.describe("Document HTML sanitizing", () => {
  let token: string;
  let deleteToken: string;

  test.beforeEach(async ({ request }) => {
    const review = await createReview(request, {
      files: [{ path: "raw.md", content: CONTENT }],
    });
    token = review.token;
    deleteToken = review.deleteToken;
  });

  test.afterEach(async ({ request }) => {
    await deleteReview(request, deleteToken);
  });

  test("strips handlers, scripts, javascript: URLs and positioning styles and keeps plain HTML", async ({ page }) => {
    await loadReview(page, token);
    const doc = page.locator("#document-renderer");

    // The broken image still renders (then becomes a placeholder) but
    // without its handler. The CSP blocks inline handlers too; these checks
    // cover the markup itself.
    await expect(doc.locator(".img-placeholder")).toHaveText("[image]");
    await expect(doc.locator("[onerror], [onclick]")).toHaveCount(0);
    await expect(doc.getByText("block", { exact: true })).toBeVisible();
    await expect(doc.locator("script")).toHaveCount(0);
    await expect(doc.locator("a", { hasText: "bad" })).not.toHaveAttribute("href");
    await expect(doc.locator("details summary")).toHaveText("More");
    await expect(doc.getByText("cover", { exact: true })).not.toHaveAttribute("style");
    expect(await page.evaluate(() => (window as { __xss?: number }).__xss)).toBeUndefined();
  });

  test("prefixes author ids and classes and drops data attributes", async ({ page }) => {
    await loadReview(page, token);
    const doc = page.locator("#document-renderer");

    // Page classes and ids from the document get a user-content- prefix, so
    // the page's fixed overlay rule does not apply.
    const overlay = doc.getByText("overlay class", { exact: true });
    await expect(overlay).toHaveAttribute("class", "user-content-crit-prompt-overlay");
    await expect(overlay).toHaveAttribute("id", "user-content-commentsPanel");
    expect(await overlay.evaluate(el => getComputedStyle(el).position)).toBe("static");

    // The fake card is neither a .comment-card nor carries data-comment-id.
    const fake = doc.getByText("fake card", { exact: true });
    await expect(fake).toHaveAttribute("class", "user-content-comment-card");
    await expect(fake).not.toHaveAttribute("data-comment-id");
    await expect(page.locator('[data-comment-id="fake-card"]')).toHaveCount(0);
  });

  test("prefixes id references, so a label can't press a review-page button", async ({ page }) => {
    await loadReview(page, token);
    const doc = page.locator("#document-renderer");

    const label = doc.getByText("open settings", { exact: true });
    await expect(label).toHaveAttribute("for", "user-content-settingsToggle");
    await label.click();
    await expect(page.locator("#settingsOverlay.active")).toHaveCount(0);

    const aria = doc.getByText("aria refs", { exact: true });
    await expect(aria).toHaveAttribute("aria-labelledby", "user-content-a user-content-b");
    await expect(aria).toHaveAttribute("aria-describedby", "user-content-c");
    await expect(aria).toHaveAttribute("aria-controls", "user-content-d");
    await expect(aria).toHaveAttribute("aria-owns", "user-content-e");
    await expect(doc.locator('input[aria-label="list ref"]')).toHaveAttribute("list", "user-content-choices");
    await expect(doc.getByText("cell ref", { exact: true })).toHaveAttribute("headers", "user-content-h1 user-content-h2");
    await expect(doc.locator('img[alt="map ref"]')).toHaveAttribute("usemap", "#user-content-shapes");
    await expect(doc.locator("map")).toHaveAttribute("name", "user-content-shapes");
  });
});

// Relative image paths point at the review's raw route. The src arrives
// HTML-escaped (and percent-encoded by markdown-it), so it must be decoded
// once before each path segment is encoded.
test.describe("Document image paths", () => {
  let token: string;
  let deleteToken: string;

  test.beforeEach(async ({ request }) => {
    const review = await createReview(request, {
      files: [{
        path: "docs/plan.md",
        content: "# Images\n\n![amp](img/a&b.png)\n\n![space](<img/my pic.png>)\n\n<img alt=\"raw\" src=\"img/x&amp;y.png\">\n",
      }],
    });
    token = review.token;
    deleteToken = review.deleteToken;
  });

  test.afterEach(async ({ request }) => {
    await deleteReview(request, deleteToken);
  });

  test("encodes each path segment once", async ({ page }) => {
    // Serve a 1x1 PNG so the images stay on the page (a broken image is
    // swapped for a placeholder).
    const png = Buffer.from(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=",
      "base64",
    );
    await page.route("**/raw/docs/img/**", route => route.fulfill({ contentType: "image/png", body: png }));
    await loadReview(page, token);
    const doc = page.locator("#document-renderer");

    await expect(doc.locator('img[alt="amp"]')).toHaveAttribute("src", `/r/${token}/raw/docs/img/a%26b.png`);
    await expect(doc.locator('img[alt="space"]')).toHaveAttribute("src", `/r/${token}/raw/docs/img/my%20pic.png`);
    await expect(doc.locator('img[alt="raw"]')).toHaveAttribute("src", `/r/${token}/raw/docs/img/x%26y.png`);
  });
});

// Crit's own markup never goes through the raw-HTML pass, so it keeps its
// ids and classes even next to raw HTML.
test.describe("Document HTML — crit's own markup", () => {
  let token: string;
  let deleteToken: string;

  test.beforeEach(async ({ request }) => {
    const review = await createReview(request, {
      files: [{
        path: "own.md",
        content: [
          '# Setup <kbd class="key">Ctrl</kbd>',
          "",
          "```js",
          "const a = 1",
          "```",
          "",
          // Push the link target below the fold.
          ...Array.from({ length: 60 }, (_, i) => `Filler ${i + 1}.\n`),
          'Run <span id="cmd">this</span>:',
          "",
        ].join("\n"),
      }],
    });
    token = review.token;
    deleteToken = review.deleteToken;
  });

  test.afterEach(async ({ request }) => {
    await deleteReview(request, deleteToken);
  });

  test("headings and fences keep their ids and classes; author ids still work as link targets", async ({ page }) => {
    await loadReview(page, token);
    const doc = page.locator("#document-renderer");

    const heading = doc.locator("h1");
    const id = await heading.getAttribute("id");
    expect(id).toBeTruthy();
    expect(id).not.toMatch(/^user-content-/);
    await expect(doc.locator(`a.heading-anchor[href="#${id}"]`)).toHaveCount(1);
    await expect(heading.locator("kbd")).toHaveAttribute("class", "user-content-key");

    // The fence renders as crit's per-line code markup.
    await expect(doc.locator(".fence-marker")).toHaveCount(2);
    await expect(doc.locator("code.crit-code", { hasText: "const a = 1" })).toHaveCount(1);

    // #cmd finds the author's id="user-content-cmd", as on GitHub.
    const target = doc.locator("#user-content-cmd");
    await expect(target).toHaveText("this");
    await expect(target).not.toBeInViewport();
    await page.evaluate(() => { window.location.hash = "cmd"; });
    await expect(target).toBeInViewport();
  });
});
