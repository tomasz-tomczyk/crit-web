// A blockquote line carrying only the ">" marker must stay inside the quote
// instead of leaking into the document as a literal ">". Ported from crit's
// web/__tests__/crit-line-blocks.test.js.
//
// document-renderer.js imports npm packages that the test mirror cannot
// resolve, so the functions under test are cut out of the source text.

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const require = createRequire(join(here, '..', 'package.json'))
const markdownit = require('markdown-it')
const src = readFileSync(join(here, '..', 'js', 'document-renderer.js'), 'utf8')
const panelSrc = readFileSync(join(here, '..', 'js', 'comments-panel.js'), 'utf8')

function extractFunction(name, from = src) {
  const start = from.indexOf(`function ${name}(`)
  assert.notEqual(start, -1, `${name} must exist`)
  const bodyStart = from.indexOf('{', start)
  let depth = 0
  for (let i = bodyStart; i < from.length; i++) {
    if (from[i] === '{') depth++
    if (from[i] === '}') {
      depth--
      if (depth === 0) return from.slice(start, i + 1)
    }
  }
  throw new Error(`could not extract ${name}`)
}

const buildLineBlocks = new Function(
  `${extractFunction('escapeHtml', panelSrc)}
  ${extractFunction('rewriteFrontmatterAsYamlFence')}
  ${extractFunction('buildLineBlocks')}
  return buildLineBlocks`,
)()

const md = markdownit()

test('blockquote lines carrying only the > marker stay inside the quote', () => {
  const blocks = buildLineBlocks(md, '> line one\n>\n> line two')

  assert.equal(blocks.length, 3)
  assert.match(blocks[0].html, /<blockquote>/)
  assert.equal(blocks[1].startLine, 2)
  assert.equal(blocks[1].html, '<blockquote></blockquote>')
  assert.equal(blocks[1].isEmpty, false)
  assert.match(blocks[2].html, /<blockquote>/)
})

test('leading and trailing blockquote marker lines stay inside the quote', () => {
  const blocks = buildLineBlocks(md, '>\n> quoted\n>')

  assert.equal(blocks.length, 3)
  assert.equal(blocks[0].html, '<blockquote></blockquote>')
  assert.match(blocks[1].html, /<blockquote>/)
  assert.equal(blocks[2].html, '<blockquote></blockquote>')
})

test('a link reference definition inside a quote renders as an empty quote', () => {
  const blocks = buildLineBlocks(md, '> line one\n>\n> [ref]: https://example.com\n> line two')

  assert.equal(blocks.length, 4)
  assert.equal(blocks[2].startLine, 3)
  assert.equal(blocks[2].html, '<blockquote></blockquote>')
  assert.match(blocks[3].html, /<blockquote>/)
})
