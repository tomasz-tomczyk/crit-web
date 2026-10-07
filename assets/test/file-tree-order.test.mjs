// The sidebar file tree must list files in the same order as the review list
// (fileSortComparator), including folders whose single-child chains were
// collapsed into one 'a/b/c' row. Ported from crit's
// web/__tests__/file-tree-order.test.js.
//
// document-renderer.js imports npm packages that the test mirror cannot
// resolve, so the functions under test are cut out of the source text.

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const src = readFileSync(
  join(dirname(fileURLToPath(import.meta.url)), '..', 'js', 'document-renderer.js'),
  'utf8',
)

function extractFunction(name) {
  const start = src.indexOf(`function ${name}(`)
  assert.notEqual(start, -1, `${name} must exist`)
  const bodyStart = src.indexOf('{', start)
  let depth = 0
  for (let i = bodyStart; i < src.length; i++) {
    if (src[i] === '{') depth++
    if (src[i] === '}') {
      depth--
      if (depth === 0) return src.slice(start, i + 1)
    }
  }
  throw new Error(`could not extract ${name}`)
}

function fakeElement() {
  return {
    dataset: {},
    style: {},
    children: [],
    addEventListener() {},
    appendChild(child) { this.children.push(child) },
  }
}

function treeFileOrder(container) {
  const paths = []
  ;(function walk(el) {
    if (el.dataset.path) paths.push(el.dataset.path)
    el.children.forEach(walk)
  })(container)
  return paths
}

function renderTree(paths) {
  const fileList = paths.map(p => ({ path: p, status: 'modified', comments: [] }))
  const container = fakeElement()
  const listOrder = new Function('document', 'fileList', 'container', `
    const ctx = { treeFolderState: {} }
    function escapeHtml(s) { return s }
    ${extractFunction('pathCompare')}
    ${extractFunction('fileSortComparator')}
    ${extractFunction('buildFileTree')}
    ${extractFunction('collapseCommonPrefixes')}
    ${extractFunction('renderTreeNode')}
    const files = fileList.slice().sort(fileSortComparator)
    renderTreeNode(ctx, container, collapseCommonPrefixes(buildFileTree(files)), 0, '')
    return files.map(f => f.path)
  `)({ createElement: fakeElement }, fileList, container)
  return { listOrder, treeOrder: treeFileOrder(container) }
}

test('tree orders a collapsed folder before a dotted sibling, like the list', () => {
  const { listOrder, treeOrder } = renderTree([
    'web.test/app/utils.test.ts',
    'web/src/app/utils.ts',
    'web.test/app/views/online/table.test.ts',
    'web/src/app/data/feature.ts',
    'web.test/app/format.test.ts',
    'web.test/app/views/calendar/month.test.ts',
    'web/src/app/format.ts',
    'web.test/app/views/online/chart.test.ts',
  ])
  assert.deepEqual(listOrder, [
    'web/src/app/data/feature.ts',
    'web/src/app/format.ts',
    'web/src/app/utils.ts',
    'web.test/app/views/calendar/month.test.ts',
    'web.test/app/views/online/chart.test.ts',
    'web.test/app/views/online/table.test.ts',
    'web.test/app/format.test.ts',
    'web.test/app/utils.test.ts',
  ])
  assert.deepEqual(treeOrder, listOrder)
})

test('list puts folders before root files, like the tree', () => {
  const { listOrder, treeOrder } = renderTree(['README.md', 'docs/a.md', 'Makefile', 'lib/x/y.ex'])
  assert.deepEqual(listOrder, ['docs/a.md', 'lib/x/y.ex', 'Makefile', 'README.md'])
  assert.deepEqual(treeOrder, listOrder)
})
