import createDOMPurify from "dompurify"

// Isolated instance so comment hooks never pollute Mermaid's shared DOMPurify.
const purify = createDOMPurify(typeof window !== "undefined" ? window : undefined)

// Snapshot of HTMLPipeline::SanitizationFilter's public default allowlist.
// Keep this in sync with crit/web/comment-html.js.
const ALLOWED_TAGS = [
  "h1", "h2", "h3", "h4", "h5", "h6", "br", "b", "i", "strong", "em",
  "a", "pre", "code", "img", "tt", "div", "ins", "del", "sup", "sub",
  "p", "picture", "ol", "ul", "table", "thead", "tbody", "tfoot",
  "blockquote", "dl", "dt", "dd", "kbd", "q", "samp", "var", "hr", "ruby",
  "rt", "rp", "li", "tr", "td", "th", "s", "strike", "summary", "details",
  "caption", "figure", "figcaption", "abbr", "bdo", "cite", "dfn", "mark",
  "small", "source", "span", "time", "wbr",
]
const ALLOWED_ATTR = [
  "href", "src", "longdesc", "loading", "alt", "itemscope", "itemtype",
  "cite", "srcset", "abbr", "accept", "accept-charset", "accesskey",
  "action", "align", "aria-describedby", "aria-hidden", "aria-label",
  "aria-labelledby", "axis", "border", "char", "charoff", "charset",
  "checked", "clear", "cols", "colspan", "compact", "coords", "datetime",
  "dir", "disabled", "enctype", "for", "frame", "headers", "height",
  "hreflang", "hspace", "id", "ismap", "label", "lang", "maxlength",
  "media", "method", "multiple", "name", "nohref", "noshade", "nowrap",
  "open", "progress", "prompt", "readonly", "rel", "rev", "role", "rows",
  "rowspan", "rules", "scope", "selected", "shape", "size", "span", "start",
  "summary", "tabindex", "title", "type", "usemap", "valign", "value",
  "width", "itemprop", "class", "data-ref-id",
]
const SAFE_CLASS = /^(?:hljs(?:-[\w-]+)?|file-ref|comment-ref|comment-ref-code)$/
const SAFE_COMMENT_REF = /^(?:c|r|rp)_[a-f0-9]{6,}$/
const SAFE_URL = /^(?:(?:https?|mailto):|(?:\/|\.{1,2}\/|#))/i

function isSafeUrl(value) {
  return value === "" || SAFE_URL.test(String(value).trim())
}

purify.addHook("afterSanitizeAttributes", node => {
  for (const attr of ["href", "src", "longdesc", "cite"]) {
    if (node.hasAttribute(attr) && !isSafeUrl(node.getAttribute(attr))) node.removeAttribute(attr)
  }
  if (node.hasAttribute("class")) {
    const classes = node.getAttribute("class").split(/\s+/).filter(value => SAFE_CLASS.test(value))
    if (classes.length) node.setAttribute("class", classes.join(" "))
    else node.removeAttribute("class")
  }
  if (node.hasAttribute("data-ref-id") && !SAFE_COMMENT_REF.test(node.getAttribute("data-ref-id"))) {
    node.removeAttribute("data-ref-id")
  }
})

export function sanitizeCommentHtml(html) {
  return purify.sanitize(html, {
    ALLOWED_TAGS,
    ALLOWED_ATTR,
    ALLOW_DATA_ATTR: false,
    ALLOW_ARIA_ATTR: false,
    ALLOW_UNKNOWN_PROTOCOLS: false,
    FORBID_TAGS: ["style", "svg", "math"],
    FORBID_ATTR: ["style"],
  })
}
