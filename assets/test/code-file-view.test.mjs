import { test } from 'node:test'
import assert from 'node:assert/strict'
import { install } from './support/dom.mjs'
import { importModule } from './support/modules.mjs'

install()
const view = await importModule('js/code-file-view.js')

// Records what a Pierre File is asked to do.
function fakePierre() {
  const files = []
  class File {
    constructor(options, pool) { this.options = options; this.pool = pool; this.renders = []; this.selected = []; files.push(this) }
    render(props) { this.renders.push(props) }
    setOptions(options) { this.options = options }
    rerender() { this.rerendered = true }
    setSelectedLines(range) { this.selected.push(range) }
    cleanUp() { this.cleaned = true }
  }
  return { files, P: { File, setLanguageOverride: (contents, lang) => Object.assign({}, contents, { lang }) } }
}

const options = { display: { overflow: 'scroll', disableLineNumbers: false }, themeType: 'dark', commentable: true }

function makeView(handlers = {}, opts = options) {
  const { P, files } = fakePierre()
  const calls = { ranges: [], touches: [], posts: [] }
  const v = view.createCodeFileView({
    P, pool: 'pool', path: 'lib/app.ex', content: 'a\nb\nc\n', options: opts,
    handlers: Object.assign({
      buildAnnotation: m => ({ built: m }),
      onGutterRange: r => calls.ranges.push(r),
      onTouchLine: l => calls.touches.push(l),
      onPostRender: (host, phase) => calls.posts.push(phase),
    }, handlers),
  })
  return { v, file: files[0], calls }
}

test('lineCount matches Pierre: a trailing newline ends the last line', () => {
  assert.equal(view.lineCount(''), 0)
  assert.equal(view.lineCount('a'), 1)
  assert.equal(view.lineCount('a\n'), 1)
  assert.equal(view.lineCount('a\nb\n'), 2)
  assert.equal(view.lineCount('a\n\n'), 2)
})

test('annotations: threads on their end line, open forms after theirs', () => {
  const comments = [
    { id: 'c1', scope: 'line', start_line: 1, end_line: 2 },
    { id: 'c2', scope: 'file' },
    { id: 'c3', scope: 'line', start_line: 3, end_line: 3, resolved: true },
    { id: 'c4', scope: 'line', start_line: 9, end_line: 9 },
    { id: 'c5', scope: 'review' },
  ]
  const forms = [
    { formKey: 'f1', startLine: 1, endLine: 3 },
    { formKey: 'edit:c1', editingId: 'c1', endLine: 2 },
    { formKey: 'f2', scope: 'file' },
  ]
  assert.deepEqual(view.annotationsForCodeFile({ comments, forms, lineTotal: 3, hideResolved: false }), [
    { lineNumber: 2, metadata: { kind: 'thread', id: 'c1', editingForm: forms[1] } },
    { lineNumber: 3, metadata: { kind: 'thread', id: 'c3' } },
    { lineNumber: 3, metadata: { kind: 'form', id: 'f1' } },
  ])
  const hidden = view.annotationsForCodeFile({ comments, forms: [], lineTotal: 3, hideResolved: true })
  assert.deepEqual(hidden.map(a => a.metadata.id), ['c1'])
})

test('comments past the end of the file are outdated', () => {
  assert.equal(view.isOutdatedLineComment({ scope: 'line', end_line: 4 }, 3), true)
  assert.equal(view.isOutdatedLineComment({ scope: 'line', end_line: 3 }, 3), false)
  assert.equal(view.isOutdatedLineComment({ scope: 'file' }, 0), false)
})

test('renders the whole file with its annotations into its own element', () => {
  const { v, file } = makeView()
  assert.equal(v.lineTotal, 3)
  assert.equal(v.element.className, 'crit-code-file')
  assert.equal(v.element.dataset.filePath, 'lib/app.ex')
  assert.equal(file.pool, 'pool')
  assert.equal(file.options.disableFileHeader, true)
  assert.equal(file.options.enableGutterUtility, true)
  assert.equal(file.options.themeType, 'dark')
  v.update([{ lineNumber: 2, metadata: { kind: 'thread', id: 'c1' } }])
  const props = file.renders.at(-1)
  assert.equal(props.containerWrapper, v.element)
  assert.equal(props.file.name, 'lib/app.ex')
  assert.equal(props.file.contents, 'a\nb\nc\n')
  assert.deepEqual(props.lineAnnotations, [{ lineNumber: 2, metadata: { kind: 'thread', id: 'c1' } }])
})

test('HEEx and other overrides get their language', () => {
  const { P, files } = fakePierre()
  const v = view.createCodeFileView({ P, pool: null, path: 'a/page.html.heex', content: 'x', options, handlers: { buildAnnotation() {}, onPostRender() {} } })
  v.update([])
  assert.equal(files[0].renders[0].file.lang, 'html')
})

test('open forms keep their annotation element; threads are rebuilt; closed forms are forgotten', () => {
  const { v, file } = makeView()
  const form = { lineNumber: 2, metadata: { kind: 'form', id: 'f1' } }
  const thread = { lineNumber: 1, metadata: { kind: 'thread', id: 'c1' } }
  v.update([thread, form])
  const [t1, f1] = file.renders.at(-1).lineAnnotations.map(a => a.metadata)
  v.update([thread, form])
  const [t2, f2] = file.renders.at(-1).lineAnnotations.map(a => a.metadata)
  assert.equal(f2, f1, 'form metadata is stable, so Pierre keeps its element')
  assert.notEqual(t2, t1, 'thread metadata is new, so Pierre rebuilds the card')
  v.update([thread])
  v.update([thread, form])
  const f3 = file.renders.at(-1).lineAnnotations[1].metadata
  assert.notEqual(f3, f1, 'a reopened form starts fresh')
})

test('gutter "+" and drag open a form for the range, then drop Pierre\'s selection', () => {
  const { file, calls } = makeView()
  file.options.onGutterUtilityClick({ start: 3, end: 1, side: 'additions' })
  assert.deepEqual(calls.ranges, [{ startLine: 1, endLine: 3 }])
  assert.deepEqual(file.selected.at(-1), null)
})

test('a tap on a line number comments on touch only, and only when commenting is allowed', () => {
  const { file, calls } = makeView()
  let prevented = false
  file.options.onLineNumberClick({ lineNumber: 2, event: { pointerType: 'mouse', preventDefault() {} } })
  file.options.onLineNumberClick({ lineNumber: 2, event: { pointerType: 'touch', preventDefault() { prevented = true } } })
  assert.deepEqual(calls.touches, [2])
  assert.equal(prevented, true)

  const readOnly = makeView({}, Object.assign({}, options, { commentable: false }))
  assert.equal(readOnly.file.options.enableGutterUtility, false)
  readOnly.file.options.onLineNumberClick({ lineNumber: 2, event: { pointerType: 'touch', preventDefault() {} } })
  assert.deepEqual(readOnly.calls.touches, [])
})

test('keyboard focus uses Pierre\'s line selection on the new side', () => {
  const { v, file } = makeView()
  v.setSelectedLines({ start: 2, end: 3 })
  v.setSelectedLines(null)
  assert.deepEqual(file.selected, [{ start: 2, end: 3, side: 'additions', endSide: 'additions' }, null])
})

test('setOptions re-renders with the new display settings; destroy cleans up', () => {
  const { v, file } = makeView()
  v.setOptions({ display: { overflow: 'wrap', disableLineNumbers: true }, themeType: 'light', commentable: true })
  assert.equal(file.options.overflow, 'wrap')
  assert.equal(file.options.disableLineNumbers, true)
  assert.equal(file.options.themeType, 'light')
  assert.equal(file.rerendered, true)
  v.destroy()
  assert.equal(file.cleaned, true)
  assert.equal(v.element.isConnected, false)
})
