// One code file of a review, rendered by Pierre's File component: Shiki
// highlighting, line numbers, the hover "+" and gutter range selection, with
// comment threads and open forms as line annotations. Mirrors how crit renders
// a files-mode code file (a Pierre `file` item) and a story chapter
// (renderPierreInlineDiff): same adapter options, same annotation metadata
// ({ kind, id }), same shadow-root helpers (crit-pierre-dom.js).
//
// crit-web renders reviews as a list of <details> sections, not a virtualized
// CodeView, so each file gets its own File instance. The caller keeps the
// view across document re-renders (moving `element` into the new section) so
// a re-render only re-publishes annotations.
//
// Pierre rebuilds an annotation's DOM when its metadata object changes. Like
// crit's CodeView wrapper, metadata is kept per "kind:id": thread cards are
// rebuilt on every update (cheap, always current), except active inline
// editors. Editors and open forms keep their element so typing, caret and
// focus survive a re-render. A form that closed
// is forgotten, so reopening the same range starts from a fresh form.

import adapter from '../vendor/crit/crit-pierre-adapter.js'
import pierreDOM from '../vendor/crit/crit-pierre-dom.js'

let nextCacheKey = 0

// Lines in a file as Pierre numbers them: a trailing newline ends the last
// line rather than starting an empty one.
export function lineCount(content) {
  if (!content) return 0
  return content.split('\n').length - (content.endsWith('\n') ? 1 : 0)
}

// Pierre line annotations for a code file (crit: pierreAnnotationsFor, file
// view). Threads anchor on their end line, open forms after their end line.
// Comments past the end of the file cannot anchor; the caller shows them as
// outdated. Edit forms render inside their thread card, not as annotations.
export function annotationsForCodeFile({ comments, forms, lineTotal, hideResolved }) {
  const out = []
  for (const c of comments) {
    if (c.scope === 'file' || c.scope === 'review') continue
    if (hideResolved && c.resolved) continue
    if (!c.end_line || c.end_line > lineTotal) continue
    const metadata = { kind: 'thread', id: c.id }
    const editingForm = forms.find(f => f.editingId === c.id)
    if (editingForm) metadata.editingForm = editingForm
    out.push({ lineNumber: c.end_line, metadata })
  }
  for (const f of forms) {
    if (f.editingId || f.scope === 'file' || f.scope === 'review') continue
    if (!f.endLine || f.endLine > lineTotal) continue
    out.push({ lineNumber: f.endLine, metadata: { kind: 'form', id: f.formKey } })
  }
  return out
}

// Comments on lines the file no longer has (e.g. the file shrank between
// rounds): they are listed with the file-level comments instead.
export function isOutdatedLineComment(comment, lineTotal) {
  return comment.scope !== 'file' && comment.scope !== 'review' && !!comment.end_line && comment.end_line > lineTotal
}

// Round diff for a code file: Pierre FileDiff of the previous round's content
// against this round's, so a re-shared review shows code changes the way
// crit's git mode does. Comments and forms live on the new (additions) side;
// crit-web comments carry no side, so old-side lines are not commentable.
// A share keeps the same file list every round (crit only updates a review
// whose file list matches), so a file missing at one revision is uploaded as
// this one-line marker. The round diff treats it as an empty file: a new file
// shows as all additions, a deleted one as all deletions.
export const ABSENT_MARKER = '(file not present at this revision)'
export function roundDiffText(content) {
  return (content || '').replace(/\r?\n$/, '') === ABSENT_MARKER ? '' : (content || '')
}

function buildRoundDiff(P, path, prevContent, content, key) {
  const fileDiff = P.parseDiffFromFile(
    { name: path, contents: roundDiffText(prevContent), cacheKey: key + ':old' },
    { name: path, contents: roundDiffText(content), cacheKey: key + ':new' },
  )
  const lang = adapter.languageOverride(path)
  return lang ? P.setLanguageOverride(fileDiff, lang) : fileDiff
}

// prevContent: null/undefined renders the file; a string (possibly empty, for
// a file new in this round) renders a diff against it in `diffMode`.
export function createCodeFileView({ P, pool, path, content, prevContent, diffMode, options, handlers }) {
  const element = document.createElement('div')
  element.className = 'crit-code-file'
  element.dataset.filePath = path

  const isDiff = typeof prevContent === 'string'
  const mode = diffMode === 'split' ? 'split' : 'unified'
  const cacheKey = 'crit-web-file:' + (++nextCacheKey)
  const contents = isDiff
    ? buildRoundDiff(P, path, prevContent, content, cacheKey)
    : adapter.buildFileContents(P, { path, content }, cacheKey)
  const total = lineCount(content)
  let annotations = []

  // options: { display (pierre-runtime displayOptions()), themeType, commentable }
  function fileOptions({ display, themeType, commentable }) {
    return Object.assign(adapter.baseOptions(themeType, isDiff ? mode : 'unified'), display, {
      disableFileHeader: true,
      enableGutterUtility: commentable,
      unsafeCSS: pierreDOM.unsafeCSS,
      renderAnnotation(annotation) {
        return handlers.buildAnnotation(annotation.metadata) || undefined
      },
      onGutterUtilityClick(range) {
        const r = adapter.formRangeFromSelection(range)
        if (r && isDiff && r.side === 'old') {
          requestAnimationFrame(() => { if (instance) instance.setSelectedLines(null) })
          return
        }
        if (r) handlers.onGutterRange({ startLine: r.startLine, endLine: r.endLine })
        // Pierre keeps the clicked range selected and would extend it on the
        // next gutter press; the form marks the range from here on.
        requestAnimationFrame(() => { if (instance) instance.setSelectedLines(null) })
      },
      onLineNumberClick(props) {
        // Touch has no hover "+": a tap on a line number comments on it.
        if (!commentable || !props.event || props.event.pointerType !== 'touch') return
        if (isDiff && props.annotationSide === 'deletions') return
        props.event.preventDefault()
        handlers.onTouchLine(props.lineNumber)
      },
      onLineEnter(props) {
        // Pierre creates the hover "+" on first hover, after the post-render
        // labelling pass (crit-pierre-dom.js); give it its name now.
        requestAnimationFrame(() => {
          const host = element.querySelector('diffs-container')
          if (host) pierreDOM.labelPierreControls(host.shadowRoot)
        })
        if (handlers.onLineEnter) handlers.onLineEnter(props)
      },
      onPostRender(node, _instance, phase) {
        handlers.onPostRender(pierreDOM.hostFor(node), phase)
      },
    })
  }

  let instance = isDiff ? new P.FileDiff(fileOptions(options), pool) : new P.File(fileOptions(options), pool)

  const metadata = new Map() // "kind:id" → metadata object handed to Pierre
  function stableAnnotations(list) {
    const keep = new Set()
    const out = list.map(a => {
      const key = a.metadata.kind + ':' + a.metadata.id
      keep.add(key)
      let m = metadata.get(key)
      if (!m || (m.kind === 'thread' && (!a.metadata.editingForm || m.editingForm !== a.metadata.editingForm))) {
        m = { ...a.metadata }
        metadata.set(key, m)
      }
      return isDiff
        ? { side: 'additions', lineNumber: a.lineNumber, metadata: m }
        : { lineNumber: a.lineNumber, metadata: m }
    })
    for (const key of metadata.keys()) {
      if (!keep.has(key)) metadata.delete(key)
    }
    return out
  }

  // After destroy() every method is a no-op: a caller holding a stale view
  // (or a queued callback) must not reach the cleaned-up Pierre instance.
  function render() {
    if (!instance) return
    if (isDiff) instance.render({ fileDiff: contents, lineAnnotations: annotations, containerWrapper: element })
    else instance.render({ file: contents, lineAnnotations: annotations, containerWrapper: element })
  }

  return {
    element,
    path,
    content,
    prevContent: isDiff ? prevContent : null,
    diffMode: isDiff ? mode : null,
    lineTotal: total,
    // Re-publish annotations (comments/forms changed).
    update(next) {
      annotations = stableAnnotations(next)
      render()
    },
    // Display settings, theme or theme type changed.
    setOptions(next) {
      if (!instance) return
      instance.setOptions(fileOptions(next))
      instance.rerender()
    },
    // Keyboard focus / visual range (null clears).
    setSelectedLines(range) {
      if (!instance) return
      instance.setSelectedLines(range ? { start: range.start, end: range.end, side: 'additions', endSide: 'additions' } : null)
    },
    lineElement(line) {
      return pierreDOM.pierreLineElement(element, line, '')
    },
    destroy() {
      if (!instance) return
      instance.cleanUp()
      instance = null
      element.remove()
    },
  }
}
