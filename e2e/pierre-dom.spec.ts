import { test, expect } from "@playwright/test";
import { codeFile, createReview, deleteReview, hoverCodeLine, loadReview } from "./helpers";

// crit-pierre-dom.js is crit's compatibility boundary for Pierre's shadow DOM
// (labels, line lookup, quote highlights). crit-web vendors it; this checks
// its selectors still match the vendored Pierre build.
test("Pierre controls are labelled and lines resolve through the shared helpers", async ({ page, request }) => {
  const review = await createReview(request, {
    files: [{ path: "a.go", content: "package a\n\nfunc A() {\n\treturn\n}\n" }, { path: "b.md", content: "# B\n" }],
    comments: [{ start_line: 3, end_line: 3, body: "Quoted", file: "a.go" }],
  });
  try {
    await loadReview(page, review.token);
    await hoverCodeLine(page, "a.go", 3);
    await expect(codeFile(page, "a.go").locator("[data-utility-button]")).toHaveAttribute("aria-label", "Add comment");
    const host = codeFile(page, "a.go").locator("diffs-container");
    await expect(host).toHaveAttribute("data-crit-path", "a.go");
    const text = await codeFile(page, "a.go").evaluate((el) => {
      const root = el.querySelector("diffs-container")!.shadowRoot!;
      return root.querySelector('code [data-line="3"]')!.textContent;
    });
    expect(text).toContain("func A()");
  } finally {
    await deleteReview(request, review.deleteToken);
  }
});
