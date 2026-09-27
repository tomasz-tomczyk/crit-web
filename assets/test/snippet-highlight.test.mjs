import { test } from 'node:test'
import assert from 'node:assert/strict'
import { install } from './support/dom.mjs'
import { importModule } from './support/modules.mjs'

install()

// A Pierre stand-in whose worker pool "tokenizes" each line into one span.
function fakePierre() {
  const primed = []
  const results = new Map()
  const pool = {
    isInitialized: () => true,
    subscribeToStatChanges: () => () => {},
    primeFileHighlightCache(file) {
      primed.push({ lang: file.lang, contents: file.contents })
      const lines = file.contents.split('\n').map(text => ({
        type: 'element', tagName: 'div',
        children: [{ type: 'element', tagName: 'span', properties: { style: '--diffs-token-dark:#fff' }, children: [{ type: 'text', value: text }] }],
      }))
      results.set(file.cacheKey, { result: { code: lines } })
      return Promise.resolve()
    },
    getFileResultCache: file => results.get(file.cacheKey),
    evictFileFromCache: key => results.delete(key),
  }
  return {
    primed,
    P: {
      getOrCreateWorkerPoolSingleton: () => pool,
      getFiletypeFromFileName: path => (path.endsWith('.ex') ? 'elixir' : 'text'),
    },
  }
}

function snippet(path, lines) {
  const attrs = new Map()
  const lineEls = lines.map(text => {
    const classes = new Set()
    return { textContent: text, innerHTML: text, classList: { add: c => classes.add(c), has: c => classes.has(c) } }
  })
  return {
    dataset: { snippetPath: path },
    isConnected: true,
    lineEls,
    setAttribute: (k, v) => attrs.set(k, v),
    getAttribute: k => attrs.get(k),
    querySelectorAll: () => lineEls,
  }
}

test('highlights each preview line with its language, once', async () => {
  const { P, primed } = fakePierre()
  window.PierreDiffs = P
  const { SnippetHighlight } = await importModule('js/snippet-highlight.js')
  const code = snippet('lib/foo.ex', ['defmodule Foo do', 'end'])
  const heex = snippet('lib/page.html.heex', ['<div>'])
  const hook = Object.create(SnippetHighlight)
  hook.el = { querySelectorAll: () => [code, heex].filter(s => !s.getAttribute('data-hl')) }

  hook.mounted()
  await new Promise(resolve => setTimeout(resolve, 10))

  assert.deepEqual(primed.map(p => p.lang).sort(), ['elixir', 'html'], 'HEEx resolves to HTML like code files')
  assert.equal(code.getAttribute('data-hl'), 'highlighted')
  assert.equal(code.lineEls[0].innerHTML, '<span style="--diffs-token-dark:#fff">defmodule Foo do</span>')
  assert.equal(code.lineEls[1].innerHTML, '<span style="--diffs-token-dark:#fff">end</span>')
  assert.equal(code.lineEls[0].classList.has('crit-code'), true)

  // Already highlighted previews are skipped on LiveView updates.
  primed.length = 0
  hook.updated()
  await new Promise(resolve => setTimeout(resolve, 10))
  assert.deepEqual(primed, [])
})
