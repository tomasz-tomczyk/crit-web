import createDOMPurify from "dompurify"

// Isolated instance so the comment allowlist hooks never apply here.
// Keep this in sync with crit/web/document-html.js.
const purify = createDOMPurify(typeof window !== "undefined" ? window : undefined)

// Reviewed documents may carry raw HTML (<details>, <img width>, <kbd>...).
// DOMPurify's default profile keeps that markup and drops scripts, event
// handlers and javascript: URLs. <style>, <form> and style attributes would
// let a document restyle the review page, cover it, or post from it.
const RAW_CONFIG = { FORBID_TAGS: ["style", "form"], FORBID_ATTR: ["style"] }
// Rendered blocks also hold crit's own inline styles (Shiki token colours,
// table column widths), so the second pass keeps style attributes.
const RENDERED_CONFIG = { FORBID_TAGS: ["style", "form"] }

// Raw HTML from the document.
export function sanitizeDocumentHtml(html) {
  return purify.sanitize(html, RAW_CONFIG)
}

// Block HTML that was changed as a string after the first pass (word-diff
// spans), cleaned again before it reaches the page.
export function sanitizeRenderedHtml(html) {
  return purify.sanitize(html, RENDERED_CONFIG)
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
