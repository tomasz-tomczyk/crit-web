import { test, expect, type Page } from "@playwright/test";
import { createReview, deleteReview, loadReview } from "./helpers";

// Remote images in a shared document or a comment must not load until the
// reader clicks them: an agent could encode data in the URL. Only the hosts
// in the CSP's img-src (CritWeb.Plugs.SecurityHeaders.remote_image_hosts)
// load directly. Port of crit's remote-images.filemode.spec.ts.

const REMOTE_HOST = "remote-images.test";
const ALLOWED_HOST = "assets.crit.md";
const MD_IMAGE = `![Status badge](https://${REMOTE_HOST}/md.png?d=secret-md)`;
const RAW_IMAGE = `<img src="https://${REMOTE_HOST}/raw.png?d=secret-raw" alt="Raw image" width="40" height="20">`;
const ALLOWED_IMAGE = `![Allowed](https://${ALLOWED_HOST}/e2e-allowed.png)`;
// 40x20 PNG.
const PNG = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAACgAAAAUCAIAAABwJOjsAAAAGklEQVR42u3BAQ0AAADCoPdPbQ8HFAAAAMB3DxQAAQq3iQAAAAAASUVORK5CYII=",
  "base64"
);

function doc(extra: string) {
  return `# Remote images\n\nIntro line.\n\n${extra}\n`;
}

// Requests to the remote host, and any CSP violation the page logs.
function watch(page: Page) {
  const remoteRequests: string[] = [];
  const cspErrors: string[] = [];
  page.on("request", (req) => {
    if (new URL(req.url()).hostname === REMOTE_HOST) remoteRequests.push(req.url());
  });
  page.on("console", (msg) => {
    if (/Content Security Policy/i.test(msg.text())) cspErrors.push(msg.text());
  });
  return { remoteRequests, cspErrors };
}

test.describe("Remote images — click to load", () => {
  let deleteToken: string | undefined;

  test.afterEach(async ({ request }) => {
    if (deleteToken) await deleteReview(request, deleteToken);
    deleteToken = undefined;
  });

  test("document images become placeholders and fetch nothing", async ({ page, request }) => {
    const review = await createReview(request, {
      files: [{ path: "plan.md", content: doc(MD_IMAGE + "\n\n" + RAW_IMAGE) }],
    });
    deleteToken = review.deleteToken;
    const seen = watch(page);
    await loadReview(page, review.token);

    const renderer = page.locator("#document-renderer");
    await expect(renderer.locator(".crit-remote-image")).toHaveCount(2);
    await expect(
      renderer.getByRole("button", {
        name: /Load remote image "Status badge" from remote-images\.test/,
      })
    ).toBeVisible();
    await expect(renderer.locator(`img[src*="${REMOTE_HOST}"]`)).toHaveCount(0);

    expect(seen.remoteRequests).toEqual([]);
    expect(seen.cspErrors).toEqual([]);
  });

  test("clicking a placeholder loads the image in a sandboxed frame", async ({ page, request }) => {
    const review = await createReview(request, {
      files: [{ path: "plan.md", content: doc(MD_IMAGE) }],
    });
    deleteToken = review.deleteToken;
    const seen = watch(page);
    await page.route(`https://${REMOTE_HOST}/**`, (route) =>
      route.fulfill({ contentType: "image/png", body: PNG })
    );
    await loadReview(page, review.token);

    const renderer = page.locator("#document-renderer");
    expect(seen.remoteRequests).toEqual([]);
    await renderer.getByRole("button", { name: /Load remote image "Status badge"/ }).click();

    const frame = renderer.locator("iframe.crit-remote-image-frame");
    await expect(frame).toHaveAttribute("sandbox", "allow-scripts");
    await expect(frame).toHaveAttribute("referrerpolicy", "no-referrer");
    // The frame reports the image size and the page sizes the frame to it.
    await expect
      .poll(() => frame.evaluate((el) => Math.round(el.getBoundingClientRect().width)))
      .toBe(40);
    await expect
      .poll(() => frame.evaluate((el) => Math.round(el.getBoundingClientRect().height)))
      .toBe(20);
    expect(seen.remoteRequests).toEqual([`https://${REMOTE_HOST}/md.png?d=secret-md`]);
    // Clicking did not open a comment form on the line.
    await expect(page.locator(".comment-form")).toHaveCount(0);
  });

  test("a failed load says so and links to the image", async ({ page, request }) => {
    const review = await createReview(request, {
      files: [{ path: "plan.md", content: doc(MD_IMAGE) }],
    });
    deleteToken = review.deleteToken;
    await page.route(`https://${REMOTE_HOST}/**`, (route) => route.abort());
    await loadReview(page, review.token);

    const renderer = page.locator("#document-renderer");
    await renderer.getByRole("button", { name: /Load remote image "Status badge"/ }).click();
    const error = renderer.locator(".crit-remote-image-error");
    await expect(error).toContainText(`Couldn’t load image from ${REMOTE_HOST}`);
    await expect(error.getByRole("link", { name: "Open in a new tab" })).toHaveAttribute(
      "href",
      `https://${REMOTE_HOST}/md.png?d=secret-md`
    );
  });

  test("comment images become placeholders", async ({ page, request }) => {
    const review = await createReview(request, {
      files: [{ path: "plan.md", content: doc("Plain text.") }],
      comments: [
        {
          file: "plan.md",
          start_line: 3,
          end_line: 3,
          body: `See ![Agent image](https://${REMOTE_HOST}/comment.png?d=secret-comment) and <img src="https://${REMOTE_HOST}/comment-raw.png">`,
        },
      ],
    });
    deleteToken = review.deleteToken;
    const seen = watch(page);
    await loadReview(page, review.token);

    const body = page.locator(".comment-card .comment-body").first();
    await expect(body).toContainText("See");
    await expect(body.locator(".crit-remote-image")).toHaveCount(2);
    await expect(body.locator(`img[src*="${REMOTE_HOST}"]`)).toHaveCount(0);
    expect(seen.remoteRequests).toEqual([]);
    expect(seen.cspErrors).toEqual([]);
  });

  test("allowlisted hosts load directly", async ({ page, request }) => {
    const review = await createReview(request, {
      files: [{ path: "plan.md", content: doc(ALLOWED_IMAGE) }],
    });
    deleteToken = review.deleteToken;
    await page.route(`https://${ALLOWED_HOST}/e2e-allowed.png`, (route) =>
      route.fulfill({ contentType: "image/png", body: PNG })
    );
    await loadReview(page, review.token);

    const renderer = page.locator("#document-renderer");
    await expect(renderer.locator(`img[src="https://${ALLOWED_HOST}/e2e-allowed.png"]`)).toHaveCount(1);
    await expect(renderer.locator(".crit-remote-image")).toHaveCount(0);
  });
});
