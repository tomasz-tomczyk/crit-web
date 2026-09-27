// Review snippets on /overview (CritWeb.Components.ReviewSnippet): highlight
// each code preview with the same Shiki grammars and themes as the review
// page (crit-code-highlight.js in Pierre's worker pool). Pierre picks the
// language from the file name, as it does for code files; unknown languages
// stay plain.

import { adapter, codeHighlight, configureCodeHighlight, loadPierre } from "./pierre-runtime.js"

function languageFor(P, path) {
  return adapter.languageOverride(path) || P.getFiletypeFromFileName(path)
}

export const SnippetHighlight = {
  mounted() {
    configureCodeHighlight()
    this.run()
  },
  updated() { this.run() },
  async run() {
    const snippets = Array.from(this.el.querySelectorAll('[data-snippet-path]:not([data-hl])'))
    if (snippets.length === 0) return
    snippets.forEach(el => el.setAttribute('data-hl', 'pending'))
    const P = await loadPierre()
    if (!P) return
    await Promise.all(snippets.map(async el => {
      const lineEls = Array.from(el.querySelectorAll('[data-snippet-line]'))
      const code = lineEls.map(line => line.textContent).join('\n') + '\n'
      const lang = languageFor(P, el.dataset.snippetPath)
      await codeHighlight.prime([{ code, lang }])
      const lines = codeHighlight.lines(code, lang)
      if (!lines || !el.isConnected) return
      lineEls.forEach((line, i) => {
        if (lines[i] === undefined) return
        line.innerHTML = lines[i]
        line.classList.add('crit-code')
      })
      el.setAttribute('data-hl', 'highlighted')
    }))
  },
}
