import { test, expect, type APIRequestContext, type Page } from "@playwright/test";
import { codeLine, createReview, deleteReview, loadReview, openSettingsPane, seedComment } from "./helpers";

// crit's pluggable renderers (vendored): ```mermaid fences and .mmd /
// .mermaid files render as diagrams. Files get a Diagram / Source toggle and a
// click on a node comments on the line that defines it.

const BASE_URL = `http://127.0.0.1:${process.env.CRIT_WEB_TEST_PORT || "4003"}`;

const MMD = "flow.mmd";
const FLOW = [
  "flowchart TD",
  "  Start[Receive request] --> Auth{Authorized?}",
  "  Auth -->|yes| Handle[Handle request]",
  "  Auth -->|no| Reject[Reject]",
  "",
].join("\n");

async function commentsOf(request: APIRequestContext, token: string) {
  const res = await request.get(`${BASE_URL}/api/reviews/${token}/comments`);
  expect(res.ok()).toBe(true);
  return (await res.json()) as { start_line: number; end_line: number; body: string }[];
}

// A file's <details> section in a multi-file review.
function section(page: Page, path: string) {
  return page.locator(".file-section").filter({ has: page.locator(".file-header .filename", { hasText: path }) });
}

test.describe("Diagram renderers — .mmd files", () => {
  let token: string;
  let deleteToken: string;

  test.beforeEach(async ({ request }) => {
    const review = await createReview(request, {
      files: [
        { path: MMD, content: FLOW },
        { path: "main.go", content: "package main\n\nfunc main() {}\n" },
      ],
    });
    token = review.token;
    deleteToken = review.deleteToken;
  });

  test.afterEach(async ({ request }) => {
    await deleteReview(request, deleteToken);
  });

  test("opens as a diagram with a Diagram / Source toggle", async ({ page }) => {
    await loadReview(page, token);
    const file = section(page, MMD);
    const target = file.locator('.crit-render[data-crit-renderer="mermaid"][data-crit-kind="file"]');
    await expect(target).toHaveAttribute("data-crit-state", "rendered", { timeout: 10_000 });
    await expect(target.locator(".crit-render-output svg")).toBeVisible();
    await expect(target.locator(".crit-render-source")).toBeHidden();

    const toggle = file.locator(".file-header .file-header-toggle");
    await expect(toggle.getByRole("button")).toHaveText(["Diagram", "Source"]);
    await expect(toggle.locator('[data-mode="rendered"]')).toHaveAttribute("aria-pressed", "true");
  });

  test("Source shows the file as code and Diagram switches back", async ({ page }) => {
    await loadReview(page, token);
    const file = section(page, MMD);
    const toggle = file.locator(".file-header-toggle");
    await toggle.locator('[data-mode="source"]').click();
    await expect(codeLine(page, MMD, 1)).toContainText("flowchart TD");
    await expect(file.locator(".crit-render")).toHaveCount(0);
    // The click switched views; it did not collapse the file.
    await expect(file).toHaveAttribute("open", "");

    await toggle.locator('[data-mode="rendered"]').click();
    await expect(file.locator(".crit-render .crit-render-output svg")).toBeVisible();
  });

  test("clicking a node opens a comment on the line that defines it", async ({ page, request }) => {
    await loadReview(page, token);
    const file = section(page, MMD);
    const node = file.locator(".crit-render-output g.node", { hasText: "Authorized?" });
    await expect(node).toBeVisible({ timeout: 10_000 });
    await node.click();

    const form = file.locator(".comment-form");
    await expect(form).toBeVisible();
    await form.locator("textarea").fill("Which roles count as authorized?");
    await form.locator("textarea").press("Control+Enter");

    await expect(file.locator(".comment-card")).toContainText("Which roles count as authorized?");
    await expect.poll(async () => (await commentsOf(request, token)).map(c => `${c.start_line}-${c.end_line}`))
      .toEqual(["2-2"]);
  });

  test("a theme change re-renders the diagram in the new theme", async ({ page }) => {
    await loadReview(page, token);
    await openSettingsPane(page);
    const target = section(page, MMD).locator(".crit-render");
    await page.locator('[data-settings-theme="light"]').click();
    await expect(target).toHaveAttribute("data-crit-theme", /^light/, { timeout: 10_000 });
    await expect(target).toHaveAttribute("data-crit-state", "rendered");
    await target.locator(".crit-render-output svg").evaluate(svg => svg.setAttribute("data-e2e-old", ""));

    await page.locator('[data-settings-theme="dark"]').click();
    await expect(target).toHaveAttribute("data-crit-theme", /^dark/);
    await expect(target).toHaveAttribute("data-crit-state", "rendered");
    await expect(target.locator(".crit-render-output svg")).toBeVisible();
    await expect(target.locator(".crit-render-output svg[data-e2e-old]")).toHaveCount(0);
  });

  test("line comments show below the diagram", async ({ page, request }) => {
    await seedComment(request, token, { file: MMD, startLine: 4, body: "Return 403 here" });
    await loadReview(page, token);
    const file = section(page, MMD);
    const svg = file.locator(".crit-render-output svg");
    const card = file.locator(".comment-card", { hasText: "Return 403 here" });
    await expect(svg).toBeVisible({ timeout: 10_000 });
    await expect(card).toBeVisible();
    await expect.poll(async () => {
      const s = await svg.boundingBox();
      const c = await card.boundingBox();
      return !!s && !!c && c.y >= s.y + s.height - 1;
    }, { message: "comment card sits below the diagram" }).toBe(true);
  });
});

test.describe("Diagram renderers — single file", () => {
  test("a single .mermaid file renders with the toggle above it", async ({ page, request }) => {
    const { token, deleteToken } = await createReview(request, { files: [{ path: "flow.mermaid", content: FLOW }] });
    try {
      await loadReview(page, token);
      const toggle = page.locator(".crit-file-view-bar .file-header-toggle");
      await expect(toggle.locator('[data-mode="rendered"]')).toHaveAttribute("aria-pressed", "true");
      await expect(page.locator(".crit-render .crit-render-output svg")).toBeVisible({ timeout: 10_000 });

      await toggle.locator('[data-mode="source"]').click();
      await expect(codeLine(page, "flow.mermaid", 2)).toContainText("Authorized?");
      await expect(page.locator(".crit-render")).toHaveCount(0);
    } finally {
      await deleteReview(request, deleteToken);
    }
  });
});

test.describe("Diagram renderers — fences", () => {
  test("an invalid diagram shows its source and the error", async ({ page, request }) => {
    const { token, deleteToken } = await createReview(request, {
      files: [{ path: "plan.md", content: "# Plan\n\n```mermaid\nflowchart TD\n  A --> \n  this is not mermaid ((\n```\n\nAfter the diagram\n" }],
    });
    try {
      await loadReview(page, token);
      const target = page.locator(".crit-render");
      await expect(target).toHaveAttribute("data-crit-state", "error", { timeout: 10_000 });
      await expect(target.locator(".crit-render-error")).toContainText("Could not render mermaid:");
      await expect(target.locator(".crit-render-source")).toContainText("this is not mermaid");
      await expect(target.locator(".crit-render-expand")).toHaveCount(0);
      // mermaid draws nothing of its own: no error graphic or scratch node.
      await expect(page.locator('body > [id^="dcrit-mermaid-"]')).toHaveCount(0);
      await expect(page.getByText("Syntax error in text")).toHaveCount(0);
      // The rest of the document still renders.
      await expect(page.locator(".line-content", { hasText: "After the diagram" })).toBeVisible();
    } finally {
      await deleteReview(request, deleteToken);
    }
  });

  test("the fence language is case-insensitive", async ({ page, request }) => {
    const { token, deleteToken } = await createReview(request, {
      files: [{ path: "plan.md", content: "# Plan\n\n```Mermaid\ngraph TD; A-->B;\n```\n" }],
    });
    const requested: string[] = [];
    page.on("request", req => { if (/mermaid/.test(new URL(req.url()).pathname)) requested.push(req.url()); });
    try {
      await loadReview(page, token);
      await expect(page.locator('.crit-render[data-crit-renderer="mermaid"] .crit-render-output svg')).toBeVisible({ timeout: 10_000 });
      // crit-web's own chunk, never crit's mermaid.min.js.
      expect(requested.some(u => /\/mermaid\.core-[^/]*\.js$/.test(u))).toBe(true);
      expect(requested.filter(u => u.includes("mermaid.min.js"))).toEqual([]);
    } finally {
      await deleteReview(request, deleteToken);
    }
  });

  test("a mermaid fence in a comment renders as a diagram", async ({ page, request }) => {
    const { token, deleteToken } = await createReview(request, {
      files: [{ path: "plan.md", content: "# Plan\n\nSome text\n" }],
    });
    try {
      await seedComment(request, token, { startLine: 3, body: "Like this:\n\n```mermaid\ngraph TD; X-->Y;\n```\n" });
      await loadReview(page, token);
      const card = page.locator(".comment-card .comment-body").first();
      await expect(card.locator('.crit-render[data-crit-kind="fence"] .crit-render-output svg')).toBeVisible({ timeout: 10_000 });
      await expect(card.locator(".crit-render-source")).toBeHidden();
    } finally {
      await deleteReview(request, deleteToken);
    }
  });

  test("a mermaid fence in a comment on a code file renders as a diagram", async ({ page, request }) => {
    const { token, deleteToken } = await createReview(request, {
      files: [{ path: "main.go", content: "package main\n\nfunc main() {}\n" }],
    });
    try {
      await seedComment(request, token, { file: "main.go", startLine: 3, body: "Flow:\n\n```mermaid\ngraph TD; X-->Y;\n```\n" });
      await loadReview(page, token);
      const card = page.locator(".crit-code-file .comment-card .comment-body").first();
      await expect(card.locator('.crit-render[data-crit-kind="fence"] .crit-render-output svg')).toBeVisible({ timeout: 10_000 });
    } finally {
      await deleteReview(request, deleteToken);
    }
  });
});

test.describe("Diagram renderers — loading", () => {
  test("a review without diagrams never requests mermaid", async ({ page, request }) => {
    const { token, deleteToken } = await createReview(request, {
      files: [
        { path: "plan.md", content: "# Plan\n\n```go\nfunc main() {}\n```\n" },
        { path: "main.go", content: "package main\n\nfunc main() {}\n" },
      ],
    });
    const requested: string[] = [];
    page.on("request", req => { if (/mermaid/.test(new URL(req.url()).pathname)) requested.push(req.url()); });
    try {
      await seedComment(request, token, { file: "plan.md", startLine: 1, body: "Plain `code` and\n\n```js\nlet x = 1\n```\n" });
      await loadReview(page, token);
      await expect(page.locator(".comment-card").first()).toBeVisible();
      await page.waitForLoadState("networkidle");
      expect(requested).toEqual([]);
    } finally {
      await deleteReview(request, deleteToken);
    }
  });

  test("a failed mermaid chunk shows the error, without requesting mermaid.min.js", async ({ page, request }) => {
    const { token, deleteToken } = await createReview(request, {
      files: [{ path: "plan.md", content: "# Plan\n\n```mermaid\ngraph TD; A-->B;\n```\n" }],
    });
    const fallback: string[] = [];
    page.on("request", req => { if (req.url().includes("mermaid.min.js")) fallback.push(req.url()); });
    await page.route(/\/mermaid\.core-[^/]*\.js$/, route => route.abort());
    try {
      await loadReview(page, token);
      const target = page.locator(".crit-render");
      await expect(target).toHaveAttribute("data-crit-state", "error", { timeout: 10_000 });
      await expect(target.locator(".crit-render-error")).toContainText("Could not load mermaid");
      await expect(target.locator(".crit-render-source")).toContainText("graph TD");
      expect(fallback).toEqual([]);
    } finally {
      await deleteReview(request, deleteToken);
    }
  });
});
