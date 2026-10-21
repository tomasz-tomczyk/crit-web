import createDOMPurify from "dompurify"

// Isolated instance so the comment allowlist hooks never apply here.
// Keep this in sync with crit/web/document-html.js.
const purify = createDOMPurify(typeof window !== "undefined" ? window : undefined)

// Reviewed documents may carry raw HTML (<details>, <img width>, <kbd>...).
// DOMPurify's default profile keeps that markup and drops scripts, event
// handlers and javascript: URLs. <style> and <form> would let a document
// restyle or post from the review page, so they go too.
const CONFIG = { FORBID_TAGS: ["style", "form"] }

export function sanitizeDocumentHtml(html) {
  return purify.sanitize(html, CONFIG)
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
