// A rendered block needs an HTML direction for alignment and list markers.
// unicode-bidi: plaintext alone only changes the ordering of inline text.
export function applyAutoTextDirection(root) {
  root.dir = root.classList.contains('code-line') ? 'ltr' : 'auto'
  const blocks = 'p, h1, h2, h3, h4, h5, h6, ul, ol, li, blockquote, th, td'
  if (!root.matches(blocks)) {
    root.querySelectorAll(blocks).forEach(el => {
      let parent = el.parentElement
      while (parent && parent !== root && !parent.matches(blocks)) parent = parent.parentElement
      if (parent === root) el.dir = 'auto'
    })
  }
  root.querySelectorAll('pre, code').forEach(el => { el.dir = 'ltr' })
}
