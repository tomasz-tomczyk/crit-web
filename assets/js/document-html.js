import createDOMPurify from "dompurify"

// Isolated instances so the comment allowlist hooks never apply here.
// Raw HTML and rendered blocks each get their own: the hook below is for
// raw HTML only. Sharing the global instance would leak it into the
// rendered pass and into comments, so a factory is required.
// Keep this in sync with crit/web/document-html.js.
if (typeof createDOMPurify !== "function") throw new Error("document-html.js needs the DOMPurify factory")
const win = typeof window !== "undefined" ? window : undefined
const rawPurify = createDOMPurify(win)
const renderedPurify = createDOMPurify(win)

// The document is placed in the review page itself, so its classes, ids
// and data attributes would reach crit's own CSS and scripts (a full-page
// overlay class, a fake comment card), and attributes that point at an id
// would reach crit's own controls (<label for="finishBtn"> clicks Finish).
// Prefix the author's classes, and every id reference, with user-content-,
// as GitHub does. SANITIZE_NAMED_PROPS prefixes id and name the same way,
// and data attributes are dropped. Crit's own markup (headings, fences,
// task lists) is not raw HTML and keeps its names.
const PREFIX = "user-content-"
// Space-separated lists of class names or ids: prefix each token.
const TOKEN_LIST_ATTRS = new Set([
  "class",
  "for",
  "aria-labelledby",
  "aria-describedby",
  "aria-controls",
  "aria-owns",
  "list",
  "headers",
])
rawPurify.addHook("uponSanitizeAttribute", (_node, data) => {
  const name = data.attrName
  if (TOKEN_LIST_ATTRS.has(name)) {
    data.attrValue = data.attrValue.split(/\s+/).filter(Boolean).map(token => PREFIX + token).join(" ")
  } else if (name === "usemap") {
    // usemap="#map" names a <map name="map">, whose name is prefixed.
    const value = data.attrValue.trim()
    data.attrValue = "#" + PREFIX + (value.charAt(0) === "#" ? value.slice(1) : value)
  }
})

// Reviewed documents may carry raw HTML (<details>, <img width>, <kbd>...).
// DOMPurify's default profile keeps that markup and drops scripts, event
// handlers and javascript: URLs. <style>, <form> and style attributes would
// let a document restyle the review page, cover it, or post from it.
const RAW_CONFIG = {
  FORBID_TAGS: ["style", "form"],
  FORBID_ATTR: ["style"],
  ALLOW_DATA_ATTR: false,
  SANITIZE_NAMED_PROPS: true,
}
// Rendered blocks also hold crit's own inline styles (Shiki token colours,
// table column widths), classes and data attributes, so the second pass
// keeps them. Its input already went through the raw pass.
const RENDERED_CONFIG = { FORBID_TAGS: ["style", "form"] }

// Raw HTML from the document.
export function sanitizeDocumentHtml(html) {
  return rawPurify.sanitize(html, RAW_CONFIG)
}

// Block HTML that was changed as a string after the first pass (word-diff
// spans), cleaned again before it reaches the page.
export function sanitizeRenderedHtml(html) {
  return renderedPurify.sanitize(html, RENDERED_CONFIG)
}

function hasHtmlInline(tokens) {
  return tokens.some(token => token.type === "html_inline")
}

// Sanitize only the raw HTML a document brings in: html_block tokens, and
// inline runs that contain html_inline tokens. Cleaning the whole inline run
// keeps <a href>text</a> together, since its open and close tags are
// separate tokens. Markdown-it already escapes everything else, so Shiki
// fences and crit's own markup skip DOMPurify.
export function installDocumentSanitizer(md) {
  const renderInline = md.renderer.renderInline
  md.renderer.renderInline = function(tokens, options, env) {
    const html = renderInline.call(this, tokens, options, env)
    return hasHtmlInline(tokens) ? sanitizeDocumentHtml(html) : html
  }
  md.renderer.rules.html_block = (tokens, idx) => sanitizeDocumentHtml(tokens[idx].content)
  return md
}
