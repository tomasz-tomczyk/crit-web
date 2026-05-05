import markdownit from "markdown-it"
import hljs from "highlight.js"
import { registerMarkdownPatch } from "./highlight-markdown-patch"
import { makeDiff, cleanupSemantic, DIFF_DELETE, DIFF_EQUAL, DIFF_INSERT } from "@sanity/diff-match-patch"

// Re-register hljs 'markdown' with patched grammar. Must run before any
// hljs.highlight() call. See highlight-markdown-patch.js for rationale.
registerMarkdownPatch(hljs)

// ---- Helpers ----------------------------------------------------------------

const IDENTITY_HUES = [200, 140, 30, 260, 350, 90, 175, 315, 55, 220, 0, 160]

function identityHue(identity) {
  if (!identity) return 200
  let hash = 0
  for (let i = 0; i < identity.length; i++) {
    hash = Math.imul(31, hash) + identity.charCodeAt(i) | 0
  }
  return IDENTITY_HUES[Math.abs(hash) % IDENTITY_HUES.length]
}

function isOwnComment(c, ctx) {
  if (ctx.userId) {
    return c.user_id != null && String(c.user_id) === String(ctx.userId)
  }
  return c.author_identity != null && c.author_identity !== "" && c.author_identity === ctx.identity
}

function isReviewOwner(ctx) {
  return ctx.userId !== "" && ctx.reviewOwnerId !== "" && String(ctx.userId) === String(ctx.reviewOwnerId)
}

function escapeHtml(str) {
  return str
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
}

const commentMd = markdownit({
  html: false,
  linkify: true,
  typographer: true,
  highlight(str, lang) {
    if (lang && hljs.getLanguage(lang)) {
      try { return hljs.highlight(str, { language: lang }).value } catch (_) {}
    }
    return ''
  },
})

// ===== File Reference Inline Rule =====
commentMd.inline.ruler.push('file_ref', function(state, silent) {
  var start = state.pos
  var max = state.posMax
  if (state.src.charCodeAt(start) !== 0x40 /* @ */) return false
  if (start > 0 && !/\s/.test(state.src[start - 1])) return false
  var end = start + 1
  while (end < max && /[a-zA-Z0-9._\-\/]/.test(state.src[end])) end++
  var path = state.src.substring(start + 1, end)
  if (path.length === 0 || (path.indexOf('.') === -1 && path.indexOf('/') === -1)) return false
  if (!silent) {
    var token = state.push('file_ref', '', 0)
    token.content = path
  }
  state.pos = end
  return true
})
commentMd.renderer.rules.file_ref = function(tokens, idx) {
  var path = tokens[idx].content
  return '<span class="file-ref">' + escapeHtml(path) + '</span>'
}

// ===== Word-Level Diff =====

// Split a line into tokens: words (alphanumeric + underscore) and individual non-word characters.
function tokenize(line) {
  var tokens = []
  var re = /[\w]+|[^\w]/g
  var match
  while ((match = re.exec(line)) !== null) {
    tokens.push(match[0])
  }
  return tokens
}

// Compute word-level diff between two lines using diff-match-patch.
// Returns { oldRanges, newRanges } where each range is [startCharIdx, endCharIdx] in the raw text.
// Returns null if lines are too long, identical, or completely different.
function wordDiff(oldLine, newLine) {
  // Skip for very long lines (perf guard)
  if (oldLine.length > 500 || newLine.length > 500) return null
  // Skip for lines with no spaces and >200 chars (likely minified/binary)
  if (oldLine.length > 200 && !oldLine.includes(' ')) return null
  if (newLine.length > 200 && !newLine.includes(' ')) return null

  // Lines are identical — nothing to highlight
  if (oldLine === newLine) return null

  const diffs = cleanupSemantic(makeDiff(oldLine, newLine))

  // If the diff is a single delete+insert with no equal parts, everything changed
  const hasEqual = diffs.some(d => d[0] === DIFF_EQUAL)
  if (!hasEqual) return null

  // Build character ranges for deletions (oldRanges) and insertions (newRanges)
  const oldRanges = []
  const newRanges = []
  let oldIdx = 0
  let newIdx = 0

  for (const [op, text] of diffs) {
    const len = text.length
    if (op === DIFF_EQUAL) {
      oldIdx += len
      newIdx += len
    } else if (op === DIFF_DELETE) {
      oldRanges.push([oldIdx, oldIdx + len])
      oldIdx += len
    } else if (op === DIFF_INSERT) {
      newRanges.push([newIdx, newIdx + len])
      newIdx += len
    }
  }

  // If no actual changes detected, skip
  if (oldRanges.length === 0 && newRanges.length === 0) return null

  return { oldRanges, newRanges }
}

// Overlay word-diff highlight ranges onto syntax-highlighted HTML.
// Walks the HTML string, tracking visible character position (skipping HTML tags),
// and inserts <span class="cssClass"> wrappers around the character ranges.
function applyWordDiffToHtml(html, ranges, cssClass) {
  if (!ranges || ranges.length === 0) return html

  var result = ''
  var charIdx = 0       // visible character index
  var rangeIdx = 0      // which range we're processing
  var inRange = false   // currently inside a word-diff span
  var i = 0             // position in html string

  while (i < html.length) {
    // Skip HTML tags (don't count them as visible characters)
    if (html[i] === '<') {
      // If we're in a word-diff range, close it before the tag, reopen after
      if (inRange) result += '</span>'
      var tagEnd = html.indexOf('>', i)
      if (tagEnd === -1) { result += html.slice(i); break }
      result += html.slice(i, tagEnd + 1)
      i = tagEnd + 1
      if (inRange) result += '<span class="' + cssClass + '">'
      continue
    }

    // Handle HTML entities (e.g., &amp; &lt; &gt; &quot;) as single visible characters
    var visibleChar
    if (html[i] === '&') {
      var semiIdx = html.indexOf(';', i)
      if (semiIdx !== -1 && semiIdx - i < 10) {
        visibleChar = html.slice(i, semiIdx + 1)
        i = semiIdx + 1
      } else {
        visibleChar = html[i]
        i++
      }
    } else {
      visibleChar = html[i]
      i++
    }

    // Check if we need to open a word-diff span
    if (!inRange && rangeIdx < ranges.length && charIdx >= ranges[rangeIdx][0]) {
      result += '<span class="' + cssClass + '">'
      inRange = true
    }

    result += visibleChar
    charIdx++

    // Check if we need to close a word-diff span
    if (inRange && rangeIdx < ranges.length && charIdx >= ranges[rangeIdx][1]) {
      result += '</span>'
      inRange = false
      rangeIdx++
      // Check if immediately entering next range
      if (rangeIdx < ranges.length && charIdx >= ranges[rangeIdx][0]) {
        result += '<span class="' + cssClass + '">'
        inRange = true
      }
    }
  }

  if (inRange) result += '</span>'
  return result
}

// ===== Suggestion Diff Renderer =====
function renderSuggestionDiff(suggestionContent, originalLines) {
  let sugLines = suggestionContent.replace(/\n$/, '').split('\n')
  let html = '<div class="suggestion-diff">'
  html += '<div class="suggestion-header">Suggested change</div>'

  const origLen = (originalLines && originalLines.length > 0) ? originalLines.length : 0
  const isEmptySuggestion = sugLines.length === 1 && sugLines[0] === '' && origLen > 0
  const sugLen = isEmptySuggestion ? 0 : sugLines.length
  const pairedLen = Math.min(origLen, sugLen)
  // Compute word-level diffs for paired lines
  const delContents = []
  const addContents = []
  for (let i = 0; i < pairedLen; i++) {
    const wd = wordDiff(originalLines[i], sugLines[i])
    if (wd) {
      delContents.push(applyWordDiffToHtml(escapeHtml(originalLines[i]), wd.oldRanges, 'diff-word-del'))
      addContents.push(applyWordDiffToHtml(escapeHtml(sugLines[i]), wd.newRanges, 'diff-word-add'))
    } else {
      delContents.push(escapeHtml(originalLines[i]))
      addContents.push(escapeHtml(sugLines[i]))
    }
  }

  // All deletion lines first (paired + unpaired)
  for (let j = 0; j < origLen; j++) {
    const dc = j < pairedLen ? delContents[j] : escapeHtml(originalLines[j])
    html += '<div class="suggestion-line suggestion-line-del">'
      + '<span class="suggestion-line-sign">\u2212</span>'
      + '<span class="suggestion-line-content">' + dc + '</span></div>'
  }

  // All addition lines (paired + unpaired)
  for (let k = 0; k < sugLen; k++) {
    const ac = k < pairedLen ? addContents[k] : escapeHtml(sugLines[k])
    html += '<div class="suggestion-line suggestion-line-add">'
      + '<span class="suggestion-line-sign">+</span>'
      + '<span class="suggestion-line-content">' + ac + '</span></div>'
  }

  html += '</div>'
  return html
}

;(function() {
  const defaultFence = commentMd.renderer.rules.fence
  commentMd.renderer.rules.fence = function(tokens, idx, options, env, self) {
    const token = tokens[idx]
    const info = token.info ? token.info.trim() : ''
    if (info === 'suggestion') {
      return renderSuggestionDiff(token.content, env && env.originalLines)
    }
    if (defaultFence) {
      return defaultFence(tokens, idx, options, env, self)
    }
    return self.renderToken(tokens, idx, options)
  }
})()

function showToast(message, duration = 3000) {
  const toast = document.createElement('div')
  toast.className = 'mini-toast'
  toast.textContent = message
  document.body.appendChild(toast)
  requestAnimationFrame(() => toast.classList.add('mini-toast-visible'))
  trackedSetTimeout(__activeCtx, () => {
    toast.classList.remove('mini-toast-visible')
    trackedSetTimeout(__activeCtx, () => toast.remove(), 300)
  }, duration)
}

// ---- Multi-form helpers -----------------------------------------------------

function formKey(form) {
  if (form.editingId) return 'edit:' + form.editingId
  const prefix = form.filePath ? form.filePath + ':' : ''
  return prefix + form.startLine + ':' + form.endLine
}

function addForm(ctx, form) {
  form.formKey = formKey(form)
  const idx = ctx.activeForms.findIndex(f => f.formKey === form.formKey)
  if (idx >= 0) {
    ctx.activeForms[idx] = form
  } else {
    ctx.activeForms.push(form)
  }
}

function removeForm(ctx, key) {
  ctx.activeForms = ctx.activeForms.filter(f => f.formKey !== key)
}

function findFormForEdit(ctx, commentId) {
  return ctx.activeForms.find(f => f.editingId === commentId)
}

// ===== Text Selection → Line Range Mapping =====

function getLineRangeFromSelection(selection) {
  if (!selection || selection.isCollapsed || !selection.toString().trim()) return null

  const anchorNode = selection.anchorNode
  const focusNode = selection.focusNode
  if (!anchorNode || !focusNode) return null

  // Walk up from a node to find the nearest commentable element.
  function findLineInfo(node) {
    const el = node.nodeType === Node.TEXT_NODE ? node.parentElement : node
    if (!el) return null

    // Check if inside a comment — don't trigger on existing comment text
    if (el.closest('.comment-form-wrapper') || el.closest('.comment-card')) return null

    // Check if inside non-commentable UI (header, file tree, buttons)
    if (el.closest('.header') || el.closest('.file-tree') || el.closest('.toc-panel')) return null

    // Try markdown line-block
    const lineBlock = el.closest('.line-block[data-file-path]')
    if (lineBlock) {
      return {
        filePath: lineBlock.dataset.filePath,
        startLine: parseInt(lineBlock.dataset.startLine),
        endLine: parseInt(lineBlock.dataset.endLine),
        blockIndex: lineBlock.dataset.blockIndex != null ? parseInt(lineBlock.dataset.blockIndex) : null,
      }
    }

    return null
  }

  const anchorInfo = findLineInfo(anchorNode)
  const focusInfo = findLineInfo(focusNode)

  if (!anchorInfo || !focusInfo) return null

  // Both ends must be in the same file
  if (anchorInfo.filePath !== focusInfo.filePath) return null

  // Compute union range
  const startLine = Math.min(anchorInfo.startLine, focusInfo.startLine)
  const endLine = Math.max(anchorInfo.endLine, focusInfo.endLine)
  const filePath = anchorInfo.filePath

  // Determine afterBlockIndex: use the larger blockIndex (form appears after last block in range)
  let afterBlockIndex = null
  if (anchorInfo.blockIndex != null && focusInfo.blockIndex != null) {
    afterBlockIndex = Math.max(anchorInfo.blockIndex, focusInfo.blockIndex)
  }

  return { filePath, startLine, endLine, afterBlockIndex }
}

function closeEmptyForms(ctx, exceptKey) {
  const toClose = []
  ctx.activeForms.forEach(function(f) {
    if (f.formKey === exceptKey) return
    if (f.editingId) return
    const ta = ctx.el.querySelector('.comment-form[data-form-key="' + f.formKey + '"] textarea')
    const text = ta ? ta.value : (f.draftBody || '')
    if (!text.trim()) toClose.push(f)
  })
  toClose.forEach(function(f) { removeForm(ctx, f.formKey) })
}

function openForm(ctx, newForm) {
  const fk = formKey(newForm)
  const existing = ctx.activeForms.find(f => f.formKey === fk)
  if (existing) {
    ctx.selectionStart = newForm.startLine
    ctx.selectionEnd = newForm.endLine
    render(ctx)
    focusCommentTextarea(ctx, existing.formKey)
    return
  }
  closeEmptyForms(ctx, fk)
  closeEmptyReviewForm(ctx)
  addForm(ctx, newForm)
  ctx.selectionStart = newForm.startLine
  ctx.selectionEnd = newForm.endLine
  render(ctx)
  focusCommentTextarea(ctx, newForm.formKey)
}

function focusCommentTextarea(ctx, targetFormKey) {
  requestAnimationFrame(() => {
    if (targetFormKey) {
      const ta = ctx.el.querySelector('.comment-form[data-form-key="' + targetFormKey + '"] textarea')
      if (ta) { ta.focus(); return }
    }
    const forms = ctx.el.querySelectorAll('.comment-form textarea')
    if (forms.length > 0) forms[forms.length - 1].focus()
  })
}

function saveOpenFormContent(ctx) {
  for (const formObj of ctx.activeForms) {
    const ta = ctx.el.querySelector('.comment-form[data-form-key="' + formObj.formKey + '"] textarea')
    if (ta) formObj.draftBody = ta.value
  }
}

// ---- Draft autosave ---------------------------------------------------------

let commentCollapseOverrides = {}
let draftTimers = {}

function getDraftKey(reviewToken, formObj) {
  const prefix = formObj.filePath ? formObj.filePath + ':' : ''
  return `crit-draft-${reviewToken}-${prefix}${formObj.startLine}-${formObj.endLine}`
}

function saveDraft(reviewToken, body, formObj) {
  const key = getDraftKey(reviewToken, formObj)
  localStorage.setItem(key, JSON.stringify({ body, savedAt: Date.now(), startLine: formObj.startLine, endLine: formObj.endLine, filePath: formObj.filePath || null }))
}

function loadDraft(reviewToken, formObj) {
  const key = getDraftKey(reviewToken, formObj)
  const raw = localStorage.getItem(key)
  if (!raw) return null
  try {
    const draft = JSON.parse(raw)
    if (Date.now() - draft.savedAt > 24 * 60 * 60 * 1000) {
      localStorage.removeItem(key)
      return null
    }
    return draft.body
  } catch (_) {
    localStorage.removeItem(key)
    return null
  }
}

function clearDraft(reviewToken, formObj) {
  const key = getDraftKey(reviewToken, formObj)
  if (draftTimers[key]) {
    clearTimeout(draftTimers[key])
    delete draftTimers[key]
  }
  localStorage.removeItem(key)
}

function scheduleDraftSave(reviewToken, body, formObj) {
  const key = getDraftKey(reviewToken, formObj)
  clearTimeout(draftTimers[key])
  draftTimers[key] = setTimeout(() => { saveDraft(reviewToken, body, formObj) }, 500)
}

function flushDrafts(ctx) {
  for (const formObj of ctx.activeForms) {
    const el = ctx.el.querySelector('.comment-form[data-form-key="' + formObj.formKey + '"] textarea')
    if (el && el.value.trim()) {
      saveDraft(ctx.reviewToken, el.value, formObj)
    }
  }
}

function getTemplates() {
  try {
    return JSON.parse(localStorage.getItem('crit-templates') || '[]')
  } catch (_) { return [] }
}

function saveTemplates(templates) {
  localStorage.setItem('crit-templates', JSON.stringify(templates))
}

function populateTemplateBar(bar, textarea) {
  bar.innerHTML = ''
  const templates = getTemplates()

  if (templates.length === 0) {
    bar.style.display = 'none'
    return
  }
  bar.style.display = ''

  for (let i = 0; i < templates.length; i++) {
    const chip = document.createElement('button')
    chip.className = 'template-chip'
    chip.type = 'button'
    chip.title = templates[i]

    const label = document.createElement('span')
    label.className = 'template-chip-label'
    label.textContent = templates[i]
    chip.appendChild(label)

    const del = document.createElement('span')
    del.className = 'template-chip-delete'
    del.textContent = '\u00d7'
    del.addEventListener('click', (e) => {
      e.stopPropagation()
      const t = getTemplates()
      t.splice(i, 1)
      saveTemplates(t)
      populateTemplateBar(bar, textarea)
    })
    chip.appendChild(del)

    chip.addEventListener('click', () => {
      const start = textarea.selectionStart
      textarea.value = textarea.value.substring(0, start) + templates[i] + textarea.value.substring(textarea.selectionEnd)
      textarea.selectionStart = textarea.selectionEnd = start + templates[i].length
      textarea.focus()
    })

    bar.appendChild(chip)
  }
}

function showSaveTemplateDialog(textarea, templateBar) {
  const text = textarea.value.trim()
  if (!text) { textarea.focus(); return }

  const overlay = document.createElement('div')
  overlay.className = 'save-template-overlay active'

  const dialog = document.createElement('div')
  dialog.className = 'save-template-dialog'

  const title = document.createElement('h3')
  title.textContent = 'Save as template'
  dialog.appendChild(title)

  const desc = document.createElement('p')
  desc.textContent = 'Edit the template text, then save.'
  dialog.appendChild(desc)

  const input = document.createElement('textarea')
  input.className = 'save-template-input'
  input.value = text
  input.rows = 3
  dialog.appendChild(input)

  const btns = document.createElement('div')
  btns.className = 'save-template-actions'

  const cancelBtn = document.createElement('button')
  cancelBtn.className = 'btn btn-sm'
  cancelBtn.textContent = 'Cancel'
  cancelBtn.addEventListener('click', () => { overlay.remove(); textarea.focus() })

  const saveBtn = document.createElement('button')
  saveBtn.className = 'btn btn-sm btn-primary'
  saveBtn.textContent = 'Save'
  saveBtn.addEventListener('click', () => {
    const val = input.value.trim()
    if (!val) return
    const t = getTemplates()
    t.push(val)
    saveTemplates(t)
    overlay.remove()
    populateTemplateBar(templateBar, textarea)
    textarea.focus()
  })

  btns.appendChild(cancelBtn)
  btns.appendChild(saveBtn)
  dialog.appendChild(btns)

  input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) { e.preventDefault(); saveBtn.click() }
    else if (e.key === 'Escape') { e.preventDefault(); cancelBtn.click() }
  })

  overlay.appendChild(dialog)
  overlay.addEventListener('click', (e) => { if (e.target === overlay) { overlay.remove(); textarea.focus() } })
  document.body.appendChild(overlay)
  requestAnimationFrame(() => { input.focus(); input.select() })
}

function restoreDrafts(ctx) {
  const prefix = `crit-draft-${ctx.reviewToken}-`
  let restored = false
  for (let i = 0; i < localStorage.length; i++) {
    const key = localStorage.key(i)
    if (!key || !key.startsWith(prefix)) continue
    try {
      const raw = localStorage.getItem(key)
      if (!raw) continue
      const draft = JSON.parse(raw)

      if (Date.now() - draft.savedAt > 24 * 60 * 60 * 1000) {
        localStorage.removeItem(key)
        continue
      }

      const startLine = draft.startLine
      const endLine = draft.endLine
      if (!startLine || !endLine) continue

      let lineBlocks, totalLines
      if (ctx.multiFile && draft.filePath) {
        const file = ctx.files.find(f => f.path === draft.filePath)
        if (!file) { localStorage.removeItem(key); continue }
        lineBlocks = file.lineBlocks
        totalLines = file.content.split('\n').length
      } else {
        lineBlocks = ctx.lineBlocks
        totalLines = ctx.rawContent.split('\n').length
      }

      if (startLine < 1 || endLine > totalLines) {
        localStorage.removeItem(key)
        continue
      }

      let afterBlockIndex = -1
      for (let bi = 0; bi < lineBlocks.length; bi++) {
        if (lineBlocks[bi].startLine >= startLine && lineBlocks[bi].endLine <= endLine) {
          afterBlockIndex = bi
        }
      }
      if (afterBlockIndex < 0) {
        localStorage.removeItem(key)
        continue
      }

      const formObj = {
        afterBlockIndex,
        startLine,
        endLine,
        editingId: null,
        draftBody: draft.body || '',
        filePath: draft.filePath || null,
      }
      formObj.formKey = formKey(formObj)
      addForm(ctx, formObj)
      restored = true
      localStorage.removeItem(key)
    } catch (_) {
      localStorage.removeItem(key)
    }
  }
  if (restored) {
    render(ctx)
    showToast('Draft restored')
  }
}

function getFocusedLineBlocks(ctx) {
  if (!ctx.multiFile) return ctx.lineBlocks
  const file = ctx.files.find(f => f.path === ctx.focusedFilePath)
  return file ? file.lineBlocks : []
}

function focusBlock(ctx, index) {
  const prev = ctx.el.querySelector('.line-block.focused')
  if (prev) prev.classList.remove('focused')

  const blocks = ctx.el.querySelectorAll('.line-block')
  if (index < 0 || index >= blocks.length) return

  ctx.focusedBlockIndex = index
  const block = blocks[index]
  block.classList.add('focused')

  // Track which file has focus in multi-file mode
  if (ctx.multiFile && block.dataset.filePath) {
    ctx.focusedFilePath = block.dataset.filePath
  }

  const header = document.querySelector('.crit-header')
  const offset = header ? header.offsetHeight + 16 : 68
  const rect = block.getBoundingClientRect()
  if (rect.top < offset || rect.bottom > window.innerHeight) {
    window.scrollTo({ top: rect.top + window.scrollY - offset, behavior: 'smooth' })
  }
}

function clearFocus(ctx) {
  ctx.focusedBlockIndex = -1
  const prev = ctx.el.querySelector('.line-block.focused')
  if (prev) prev.classList.remove('focused')
}

function formatTime(isoStr) {
  if (!isoStr) return ""
  const d = new Date(isoStr)
  return d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
}

function authorColorIndex(author) {
  if (!author) return 0
  let hash = 0
  for (let i = 0; i < author.length; i++) {
    hash = ((hash << 5) - hash) + author.charCodeAt(i)
    hash |= 0
  }
  return Math.abs(hash) % 6
}

// Split highlighted code HTML into per-line chunks,
// properly handling <span> tags that cross line boundaries.
function splitHighlightedCode(html) {
  const rawLines = html.split("\n")
  const result = []
  let openTags = []

  for (const rawLine of rawLines) {
    const prefix = openTags.join("")
    const newOpenTags = [...openTags]
    const re = /<(\/?span)([^>]*)>/g
    let m
    while ((m = re.exec(rawLine)) !== null) {
      if (m[1] === "/span") {
        newOpenTags.pop()
      } else {
        newOpenTags.push("<span" + m[2] + ">")
      }
    }
    const suffix = "</span>".repeat(newOpenTags.length)
    result.push(prefix + rawLine + suffix)
    openTags = newOpenTags
  }
  return result
}

// ---- Code file detection ----------------------------------------------------

// Most extensions are resolved via hljs's built-in alias system
// (e.g. .feature → gherkin, .md → markdown, .tsx → typescript, .toml → ini,
// .scss → scss, .h/.hpp → c/cpp, .yml → yaml, .kt → kotlin, .rb → ruby,
// .dockerfile → dockerfile, .makefile → makefile). Only extensions that hljs
// does NOT cover via aliases need entries here.
const EXT_OVERRIDES = {
  tf: 'hcl',         // Terraform — hljs has no .tf alias
  htm: 'xml',        // hljs aliases html but not htm
  svg: 'xml',
  cs: 'csharp',
  sh: 'bash',
  zig: 'zig',
  md: 'markdown',    // normalize: callers compare lang against 'markdown'
}
// Files identified by basename rather than extension.
const BASENAME_LANG = {
  dockerfile: 'dockerfile',
  makefile: 'makefile',
  gemfile: 'ruby',
  rakefile: 'ruby',
}
function langFromPath(filePath) {
  if (!filePath) return null
  const base = filePath.split('/').pop() || ''
  const baseLower = base.toLowerCase()
  if (!baseLower.includes('.') && BASENAME_LANG[baseLower]) {
    return BASENAME_LANG[baseLower]
  }
  const ext = baseLower.includes('.') ? baseLower.split('.').pop() : ''
  if (ext && EXT_OVERRIDES[ext]) return EXT_OVERRIDES[ext]
  if (ext && hljs.getLanguage(ext)) return ext
  return BASENAME_LANG[baseLower] || null
}

function isCodeFile(filePath) {
  const lang = langFromPath(filePath)
  return lang !== null && lang !== 'markdown'
}

function buildCodeLineBlocks(content, filePath) {
  const lines = content.split('\n')
  const lang = langFromPath(filePath)
  let highlightedLines = null

  if (lang && hljs.getLanguage(lang)) {
    try {
      const highlighted = hljs.highlight(content, { language: lang, ignoreIllegals: true }).value
      highlightedLines = splitHighlightedCode(highlighted)
    } catch (_) {}
  }

  const blocks = []
  for (let i = 0; i < lines.length; i++) {
    const lineNum = i + 1
    let html
    if (highlightedLines && highlightedLines[i]) {
      html = '<code class="hljs">' + highlightedLines[i] + '</code>'
    } else {
      html = '<code class="hljs">' + escapeHtml(lines[i] || '') + '</code>'
    }
    blocks.push({
      startLine: lineNum,
      endLine: lineNum,
      html: html,
      isEmpty: lines[i].trim() === '',
      cssClass: 'code-line'
    })
  }
  return blocks
}

// ---- Mermaid ----------------------------------------------------------------

let mermaidReady = false
let mermaidCounter = 0

async function initMermaid() {
  if (mermaidReady) return
  const { default: mermaid } = await import("mermaid")
  const theme = document.documentElement.getAttribute("data-theme") === "light" ? "default" : "dark"
  mermaid.initialize({ startOnLoad: false, theme })
  window.__critMermaid = mermaid
  mermaidReady = true
}

async function renderMermaidBlocks(container) {
  await initMermaid()
  const mermaid = window.__critMermaid
  if (!mermaid) return
  const els = container.querySelectorAll(".mermaid-pending")
  if (els.length === 0) return
  for (const el of els) {
    const source = el.dataset.mermaidSrc
    if (!source) continue
    const renderId = "mermaid-svg-" + mermaidCounter++
    try {
      const { svg } = await mermaid.render(renderId, source)
      el.innerHTML = svg
      el.classList.remove("mermaid-pending")
      el.classList.add("mermaid-rendered")
    } catch (_) {
      el.innerHTML = "<pre><code>" + escapeHtml(source) + "</code></pre>"
      el.classList.remove("mermaid-pending")
    }
  }
}

// ---- Markdown parsing & line-block building ---------------------------------

function buildLineBlocks(md, rawContent) {
  const tokens = md.parse(rawContent, {})
  const sourceLines = rawContent.split("\n")
  const totalLines = sourceLines.length
  const blocks = []
  let coveredUpTo = 0

  function addGapLines(upTo) {
    for (let ln = coveredUpTo; ln < upTo; ln++) {
      blocks.push({
        startLine: ln + 1,
        endLine: ln + 1,
        html: sourceLines[ln].trim() === "" ? "" : escapeHtml(sourceLines[ln]),
        isEmpty: sourceLines[ln].trim() === "",
      })
    }
    if (upTo > coveredUpTo) coveredUpTo = upTo
  }

  function findClose(startIdx) {
    let depth = 1
    for (let j = startIdx + 1; j < tokens.length; j++) {
      depth += tokens[j].nesting
      if (depth === 0) return j
    }
    return startIdx
  }

  let i = 0
  while (i < tokens.length) {
    const token = tokens[i]
    if (token.nesting === -1 || !token.map) { i++; continue }

    const blockStart = token.map[0]
    const blockEnd = token.map[1]
    addGapLines(blockStart)

    // Lists: split into individual items
    if (token.type === "bullet_list_open" || token.type === "ordered_list_open") {
      const isOrdered = token.type === "ordered_list_open"
      const listTag = isOrdered ? "ol" : "ul"
      const listCloseIdx = findClose(i)
      let orderNum = 1
      let j = i + 1
      while (j < listCloseIdx) {
        if (tokens[j].type === "list_item_open") {
          const itemCloseIdx = findClose(j)
          const itemMap = tokens[j].map
          if (itemMap) {
            addGapLines(itemMap[0])
            let contentEnd = itemMap[1]
            for (let ln = itemMap[1] - 1; ln > itemMap[0]; ln--) {
              if (sourceLines[ln].trim() === "") { contentEnd = ln } else { break }
            }
            const itemTokens = tokens.slice(j, itemCloseIdx + 1)
            const startAttr = isOrdered ? ' start="' + orderNum + '"' : ""
            const itemHtml =
              "<" + listTag + startAttr + ">" +
              md.renderer.render(itemTokens, md.options, {}) +
              "</" + listTag + ">"
            blocks.push({ startLine: itemMap[0] + 1, endLine: contentEnd, html: itemHtml, isEmpty: false })
            coveredUpTo = contentEnd
            orderNum++
          }
          j = itemCloseIdx + 1
        } else {
          j++
        }
      }
      i = listCloseIdx + 1
      addGapLines(blockEnd)
      continue
    }

    // Code fences: split per line
    if (token.type === "fence") {
      const lang = token.info ? token.info.trim().split(/\s+/)[0] : ""
      const code = token.content

      // Mermaid: render as single block
      if (lang === "mermaid") {
        blocks.push({
          startLine: blockStart + 1,
          endLine: blockEnd,
          html: '<div class="mermaid-pending" data-mermaid-src="' + escapeHtml(code.trim()) + '"></div>',
          isEmpty: false,
          cssClass: "mermaid-block",
        })
        i++
        coveredUpTo = blockEnd
        continue
      }

      let highlighted
      if (lang && hljs.getLanguage(lang)) {
        try { highlighted = hljs.highlight(code, { language: lang }).value } catch (_) { highlighted = escapeHtml(code) }
      } else {
        highlighted = escapeHtml(code)
      }

      const codeLines = splitHighlightedCode(highlighted)
      while (codeLines.length > 0 && codeLines[codeLines.length - 1].replace(/<[^>]*>/g, "").trim() === "") {
        codeLines.pop()
      }

      const fenceOpen = blockStart
      const fenceClose = blockEnd - 1

      blocks.push({
        startLine: fenceOpen + 1, endLine: fenceOpen + 1,
        html: '<span class="fence-marker">' + escapeHtml(sourceLines[fenceOpen]) + "</span>",
        isEmpty: false, cssClass: "code-line code-first",
      })

      for (let ci = 0; ci < codeLines.length; ci++) {
        blocks.push({
          startLine: fenceOpen + 2 + ci, endLine: fenceOpen + 2 + ci,
          html: '<code class="hljs">' + (codeLines[ci] || "&nbsp;") + "</code>",
          isEmpty: false, cssClass: "code-line code-mid",
        })
      }

      blocks.push({
        startLine: fenceClose + 1, endLine: fenceClose + 1,
        html: '<span class="fence-marker">' + escapeHtml(sourceLines[fenceClose]) + "</span>",
        isEmpty: false, cssClass: "code-line code-last",
      })

      i++
      coveredUpTo = blockEnd
      continue
    }

    // Tables: split per row
    if (token.type === "table_open") {
      const tableCloseIdx = findClose(i)
      let numCols = 0
      for (let j = i + 1; j < tableCloseIdx; j++) {
        if (tokens[j].type === "th_open") numCols++
        if (tokens[j].type === "tr_close") break
      }
      const colWidth = numCols > 0 ? (100 / numCols).toFixed(2) + "%" : "auto"
      const colgroup = "<colgroup>" + ('<col style="width:' + colWidth + '">').repeat(numCols) + "</colgroup>"

      let rowIndex = 0
      let bodyRowIndex = 0
      let inThead = false
      let j = i + 1
      while (j < tableCloseIdx) {
        if (tokens[j].type === "thead_open") { inThead = true; j++; continue }
        if (tokens[j].type === "thead_close") { inThead = false; j++; continue }
        if (tokens[j].type === "tbody_open" || tokens[j].type === "tbody_close") { j++; continue }

        if (tokens[j].type === "tr_open") {
          const trCloseIdx = findClose(j)
          const trMap = tokens[j].map
          if (trMap) {
            for (let ln = coveredUpTo; ln < trMap[0]; ln++) {
              const lineText = sourceLines[ln].trim()
              if (/^\|[\s\-:|]+\|$/.test(lineText) || /^[-:|][\s\-:|]*$/.test(lineText)) {
                blocks.push({ startLine: ln + 1, endLine: ln + 1, html: "", isEmpty: false, cssClass: "table-separator" })
              } else {
                blocks.push({ startLine: ln + 1, endLine: ln + 1, html: lineText === "" ? "" : escapeHtml(lineText), isEmpty: lineText === "" })
              }
            }
            coveredUpTo = trMap[0]

            const trTokens = tokens.slice(j, trCloseIdx + 1)
            const section = inThead ? "thead" : "tbody"
            const rowHtml = '<table class="split-table">' + colgroup +
              "<" + section + ">" + md.renderer.render(trTokens, md.options, {}) + "</" + section + "></table>"

            let cls = "table-row"
            if (rowIndex === 0) cls += " table-first"
            if (!inThead && bodyRowIndex % 2 === 1) cls += " table-even"
            blocks.push({ startLine: trMap[0] + 1, endLine: trMap[1], html: rowHtml, isEmpty: false, cssClass: cls })
            coveredUpTo = trMap[1]
            rowIndex++
            if (!inThead) bodyRowIndex++
          }
          j = trCloseIdx + 1
        } else {
          j++
        }
      }
      if (blocks.length > 0 && blocks[blocks.length - 1].cssClass?.includes("table-row")) {
        blocks[blocks.length - 1].cssClass += " table-last"
      }
      i = tableCloseIdx + 1
      addGapLines(blockEnd)
      continue
    }

    // Blockquotes: split into child blocks
    if (token.type === "blockquote_open") {
      const bqCloseIdx = findClose(i)
      let j = i + 1
      let hasChildren = false
      while (j < bqCloseIdx) {
        if (tokens[j].nesting === -1 || !tokens[j].map) { j++; continue }
        hasChildren = true
        const childMap = tokens[j].map
        let childCloseIdx = j
        if (tokens[j].nesting === 1) childCloseIdx = findClose(j)
        addGapLines(childMap[0])
        const childTokens = tokens.slice(j, childCloseIdx + 1)
        const childHtml = "<blockquote>" + md.renderer.render(childTokens, md.options, {}) + "</blockquote>"
        blocks.push({ startLine: childMap[0] + 1, endLine: childMap[1], html: childHtml, isEmpty: false })
        coveredUpTo = childMap[1]
        j = childCloseIdx + 1
      }
      if (!hasChildren) {
        const bqTokens = tokens.slice(i, bqCloseIdx + 1)
        blocks.push({ startLine: blockStart + 1, endLine: blockEnd, html: md.renderer.render(bqTokens, md.options, {}), isEmpty: false })
        coveredUpTo = blockEnd
      }
      i = bqCloseIdx + 1
      addGapLines(blockEnd)
      continue
    }

    // Default: single block
    let closeIdx = token.nesting === 1 ? findClose(i) : i
    const blockTokens = tokens.slice(i, closeIdx + 1)
    let html
    try { html = md.renderer.render(blockTokens, md.options, {}) }
    catch (_) { html = escapeHtml(blockTokens.map(t => t.content || "").join("")) }

    blocks.push({ startLine: blockStart + 1, endLine: blockEnd, html, isEmpty: false })
    i = closeIdx + 1
    coveredUpTo = blockEnd
  }

  addGapLines(totalLines)
  return blocks
}

function processTaskLists(html) {
  return html
    .replace(/(<li[^>]*class="task-list-item"[^>]*>)\s*<p>\[([ x])\]\s*/gi, (_, liTag, checked) =>
      liTag + "<p>" + (checked === "x" ? '<input type="checkbox" checked disabled>' : '<input type="checkbox" disabled>'))
    .replace(/(<li[^>]*class="task-list-item"[^>]*>)\[([ x])\]\s*/gi, (_, liTag, checked) =>
      liTag + (checked === "x" ? '<input type="checkbox" checked disabled>' : '<input type="checkbox" disabled>'))
}

// ---- Viewed state (localStorage) --------------------------------------------

function viewedStorageKey(ctx) {
  const paths = ctx.files.map(f => f.path).sort().join('\n')
  let hash = 0
  for (let i = 0; i < paths.length; i++) {
    hash = ((hash << 5) - hash + paths.charCodeAt(i)) | 0
  }
  return 'crit-viewed-' + (hash >>> 0).toString(36)
}

function saveViewedState(ctx) {
  const viewed = {}
  for (const f of ctx.files) {
    if (f.viewed) viewed[f.path] = true
  }
  try { localStorage.setItem(viewedStorageKey(ctx), JSON.stringify(viewed)) } catch (_) {}
}

function restoreViewedState(ctx) {
  if (!ctx.multiFile) return
  try {
    const data = JSON.parse(localStorage.getItem(viewedStorageKey(ctx)) || '{}')
    for (const f of ctx.files) {
      f.viewed = !!data[f.path]
      if (f.viewed) f.collapsed = true
    }
  } catch (_) {}
}

function toggleViewed(ctx, filePath) {
  const file = ctx.files.find(f => f.path === filePath)
  if (!file) return
  file.viewed = !file.viewed
  saveViewedState(ctx)
  updateFileTree(ctx)
  updateViewedCount(ctx)

  const section = document.getElementById('file-section-' + CSS.escape(filePath))
  if (section) {
    const cb = section.querySelector('.file-header-viewed input')
    if (cb) cb.checked = file.viewed
    if (file.viewed && section.open) {
      if (section.getBoundingClientRect().top < 0) {
        section.scrollIntoView({ behavior: 'instant' })
      }
      section.open = false
      file.collapsed = true
    }
  }
}

// ---- File tree panel --------------------------------------------------------

function buildFileTree(fileList) {
  const root = { children: {}, files: [] }
  for (const f of fileList) {
    const parts = f.path.split('/')
    let node = root
    for (let j = 0; j < parts.length - 1; j++) {
      const dirName = parts[j]
      if (!node.children[dirName]) {
        node.children[dirName] = { children: {}, files: [] }
      }
      node = node.children[dirName]
    }
    node.files.push(f)
  }
  return root
}

function collapseCommonPrefixes(tree) {
  const dirs = Object.keys(tree.children)
  const result = { children: {}, files: tree.files }
  for (const dir of dirs) {
    let name = dir
    let child = collapseCommonPrefixes(tree.children[dir])
    let childDirs = Object.keys(child.children)
    while (childDirs.length === 1 && child.files.length === 0) {
      name = name + '/' + childDirs[0]
      child = collapseCommonPrefixes(child.children[childDirs[0]])
      childDirs = Object.keys(child.children)
    }
    result.children[name] = child
  }
  return result
}

function renderTreeNode(ctx, container, node, depth, pathPrefix) {
  const folderSVG = '<svg viewBox="0 0 16 16" fill="currentColor"><path d="M1.75 1A1.75 1.75 0 0 0 0 2.75v10.5C0 14.216.784 15 1.75 15h12.5A1.75 1.75 0 0 0 16 13.25v-8.5A1.75 1.75 0 0 0 14.25 3H7.5a.25.25 0 0 1-.2-.1l-.9-1.2C6.07 1.26 5.55 1 5 1H1.75Z"/></svg>'
  const fileSVG = '<svg viewBox="0 0 16 16" fill="currentColor"><path fill-rule="evenodd" d="M3.75 1.5a.25.25 0 0 0-.25.25v12.5c0 .138.112.25.25.25h8.5a.25.25 0 0 0 .25-.25V6H9.75A1.75 1.75 0 0 1 8 4.25V1.5H3.75zm5.75.56v2.19c0 .138.112.25.25.25h2.19L9.5 2.06zM2 1.75C2 .784 2.784 0 3.75 0h5.086c.464 0 .909.184 1.237.513l3.414 3.414c.329.328.513.773.513 1.237v8.086A1.75 1.75 0 0 1 12.25 15h-8.5A1.75 1.75 0 0 1 2 13.25V1.75z"/></svg>'

  // Render subdirectories
  const dirs = Object.keys(node.children).sort()
  for (const dirName of dirs) {
    const fullPath = pathPrefix ? pathPrefix + '/' + dirName : dirName
    const child = node.children[dirName]
    const isCollapsed = ctx.treeFolderState[fullPath] === true

    const folder = document.createElement('div')
    folder.className = 'tree-folder' + (isCollapsed ? ' collapsed' : '')
    folder.dataset.folderPath = fullPath

    const row = document.createElement('div')
    row.className = 'tree-folder-row'
    row.style.paddingLeft = (8 + depth * 16) + 'px'

    row.innerHTML =
      '<span class="tree-folder-chevron">&#9662;</span>' +
      '<span class="tree-folder-icon">' + folderSVG + '</span>' +
      '<span class="tree-folder-name">' + escapeHtml(dirName) + '</span>'

    ;(function(fp, folderEl) {
      row.addEventListener('click', function() {
        ctx.treeFolderState[fp] = !ctx.treeFolderState[fp]
        folderEl.classList.toggle('collapsed')
      })
    })(fullPath, folder)

    folder.appendChild(row)

    const childContainer = document.createElement('div')
    childContainer.className = 'tree-folder-children'
    renderTreeNode(ctx, childContainer, child, depth + 1, fullPath)
    folder.appendChild(childContainer)

    container.appendChild(folder)
  }

  // Render files
  const sortedFiles = node.files.slice().sort(function(a, b) { return a.path.localeCompare(b.path) })
  for (const f of sortedFiles) {
    const fileName = f.path.split('/').pop()
    const fileEl = document.createElement('div')
    fileEl.className = 'tree-file' + (f.viewed ? ' viewed' : '')
    fileEl.dataset.path = f.path
    fileEl.style.paddingLeft = (24 + depth * 16) + 'px'

    let innerHtml =
      '<span class="tree-file-icon">' + fileSVG + '</span>' +
      '<span class="tree-file-name">' + escapeHtml(fileName) + '</span>'

    if (f.viewed) {
      innerHtml += '<span class="tree-viewed-check" title="Viewed">&#10003;</span>'
    }
    const unresolvedCount = f.comments.filter(c => !c.resolved).length
    if (unresolvedCount > 0) {
      innerHtml += '<span class="tree-comment-badge">' + unresolvedCount + '</span>'
    }

    fileEl.innerHTML = innerHtml

    ;(function(path) {
      fileEl.addEventListener('click', function() {
        const section = document.getElementById('file-section-' + CSS.escape(path))
        if (section) {
          if (!section.open) section.open = true
          section.scrollIntoView({ behavior: 'smooth', block: 'start' })
        }
      })
    })(f.path)

    container.appendChild(fileEl)
  }
}

function renderFileTree(ctx) {
  const panel = document.getElementById('fileTreePanel')
  if (!panel || !ctx.multiFile) return

  panel.style.display = ''

  const stats = document.getElementById('fileTreeStats')
  const viewedCount = ctx.files.filter(f => f.viewed).length
  stats.textContent = viewedCount + '/' + ctx.files.length + ' viewed'

  // Collapse/expand all button
  const headerEl = panel.querySelector('.tree-header')
  let existingBtn = headerEl.querySelector('.file-tree-collapse-btn')
  if (existingBtn) existingBtn.remove()
  if (ctx.files.length > 1) {
    const collapseBtn = document.createElement('button')
    collapseBtn.className = 'file-tree-collapse-btn'
    collapseBtn.title = 'Collapse all files'
    collapseBtn.innerHTML = '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path d="M4.22 3.22a.75.75 0 0 1 1.06 0L8 5.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 4.28a.75.75 0 0 1 0-1.06zm0 5a.75.75 0 0 1 1.06 0L8 10.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 9.28a.75.75 0 0 1 0-1.06z"/></svg>'
    collapseBtn.addEventListener('click', function() {
      const sections = document.querySelectorAll('.file-section')
      const anyExpanded = Array.from(sections).some(s => s.open)
      sections.forEach(function(s) { s.open = !anyExpanded })
      collapseBtn.title = anyExpanded ? 'Expand all files' : 'Collapse all files'
      collapseBtn.classList.toggle('all-collapsed', anyExpanded)
    })
    headerEl.appendChild(collapseBtn)
  }

  // Review conversation pseudo-row sits in its own section above FILES.
  const conversationSection = document.getElementById('treeConversationSection')
  if (conversationSection) {
    conversationSection.innerHTML = ''
    conversationSection.appendChild(buildReviewConversationTreeRow(ctx))
  }

  // Build and render tree
  const tree = collapseCommonPrefixes(buildFileTree(ctx.files))
  const body = document.getElementById('fileTreeBody')
  body.innerHTML = ''
  renderTreeNode(ctx, body, tree, 0, '')
}

function updateFileTree(ctx) {
  renderFileTree(ctx)
}

function updateViewedCount(ctx) {
  const el = document.getElementById('viewedCount')
  if (!el || !ctx.multiFile) return
  const viewed = ctx.files.filter(f => f.viewed).length
  el.style.display = ''
  el.textContent = viewed + ' / ' + ctx.files.length + ' files viewed'
  el.classList.toggle('all-viewed', viewed === ctx.files.length)
}

// ---- Render dispatcher ------------------------------------------------------

let __activeCtx = null

// ---- hide-resolved cache ----------------------------------------------------
// Cache the localStorage value on ctx to avoid repeated reads in render paths.

function readHideResolved() {
  return localStorage.getItem('crit-hide-resolved') === 'true'
}

function isHideResolved(ctx) {
  if (!ctx) return readHideResolved()
  if (typeof ctx._hideResolved !== 'boolean') {
    ctx._hideResolved = readHideResolved()
  }
  return ctx._hideResolved
}

function setHideResolved(ctx, value) {
  const next = !!value
  if (ctx) ctx._hideResolved = next
  localStorage.setItem('crit-hide-resolved', next ? 'true' : 'false')
  applyHideResolved(ctx)
  if (ctx) refreshCommentHighlights(ctx)
}

// ---- Tracked timers ---------------------------------------------------------
// Wraps setTimeout so destroyed() can clear pending callbacks. Avoids late
// callbacks running against a torn-down hook (and any DOM nodes it owned).

function trackedSetTimeout(ctx, fn, ms) {
  if (!ctx) return setTimeout(fn, ms)
  if (!ctx._timers) ctx._timers = new Set()
  const id = setTimeout(() => {
    if (ctx._timers) ctx._timers.delete(id)
    fn()
  }, ms)
  ctx._timers.add(id)
  return id
}

function render(ctx) {
  __activeCtx = ctx
  if (ctx.multiFile) {
    renderMultiFile(ctx)
  } else {
    renderDocument(ctx)
  }
  renderReviewConversation(ctx)
  applyHideResolved(ctx)
}

// ---- Multi-file rendering ---------------------------------------------------

function renderMultiFile(ctx) {
  saveOpenFormContent(ctx)
  const container = ctx.el
  container.classList.add('multi-file')

  // Measure actual header height and set CSS variable for sticky positioning.
  // Uses getBoundingClientRect (sub-pixel accurate) and updates on resize so
  // the mobile browser chrome appearing/disappearing doesn't create a gap.
  const header = document.querySelector('.crit-header')
  function updateHeaderHeight() {
    if (header) {
      document.documentElement.style.setProperty('--crit-header-height', header.getBoundingClientRect().height + 'px')
    }
  }
  updateHeaderHeight()
  // Store reference so destroyed() can clean it up
  ctx._resizeHandler = updateHeaderHeight
  window.addEventListener('resize', updateHeaderHeight)

  // Remove only the files container, preserving loading text on first render
  const existing = container.querySelector('.files-container')
  if (existing) {
    existing.remove()
  } else {
    // First render — clear the loading placeholder
    container.innerHTML = ''
  }

  const filesContainer = document.createElement('div')
  filesContainer.className = 'files-container'
  filesContainer.id = 'filesContainer'

  for (const file of ctx.files) {
    filesContainer.appendChild(renderFileSection(ctx, file))
  }

  container.appendChild(filesContainer)

  // Update comment count
  updateCommentCount(ctx)
  // Update file tree
  renderFileTree(ctx)
  // Render mermaid
  renderMermaidBlocks(container)
  // Hide TOC only in multi-file mode (file tree replaces it)
  if (ctx.files.length > 1) {
    const tocToggle = document.getElementById('crit-toc-toggle')
    if (tocToggle) tocToggle.style.display = 'none'
    const tocPanel = document.getElementById('crit-toc')
    if (tocPanel) tocPanel.style.display = 'none'
  }
  // Update viewed counter in header
  updateViewedCount(ctx)
}

// ---- Round diff helpers (ported from crit local) ----------------------------

function htmlToText(html) {
  const tmp = document.createElement('div')
  tmp.innerHTML = html
  return tmp.textContent || ''
}

function lineSimilarity(a, b) {
  if (a === b) return 1
  if (!a || !b) return 0
  const wordRe = /^\w+$/
  const tokA = tokenize(a).filter(t => wordRe.test(t))
  const tokB = tokenize(b).filter(t => wordRe.test(t))
  if (tokA.length === 0 && tokB.length === 0) return 1
  if (tokA.length === 0 || tokB.length === 0) return 0
  const counts = {}
  for (let i = 0; i < tokA.length; i++) {
    counts[tokA[i]] = (counts[tokA[i]] || 0) + 1
  }
  let common = 0
  for (let i = 0; i < tokB.length; i++) {
    if (counts[tokB[i]] > 0) { common++; counts[tokB[i]]-- }
  }
  return (2 * common) / (tokA.length + tokB.length)
}

function bestWordDiffPairing(delTexts, addTexts) {
  const delCount = delTexts.length
  const addCount = addTexts.length
  const pairCount = Math.min(delCount, addCount)
  if (pairCount === 0) return []
  if (delCount + addCount > 8) return []
  if (delCount === 1 && addCount === 1) {
    return lineSimilarity(delTexts[0], addTexts[0]) >= 0.4 ? [[0, 0]] : []
  }
  const candidates = []
  for (let d = 0; d < delCount; d++) {
    for (let a = 0; a < addCount; a++) {
      candidates.push({ d, a, score: lineSimilarity(delTexts[d], addTexts[a]) })
    }
  }
  candidates.sort((x, y) => y.score - x.score)
  const usedDels = {}
  const usedAdds = {}
  const pairs = []
  for (let i = 0; i < candidates.length; i++) {
    const c = candidates[i]
    if (usedDels[c.d] || usedAdds[c.a]) continue
    if (c.score < 0.4) break
    pairs.push([c.d, c.a])
    usedDels[c.d] = true
    usedAdds[c.a] = true
    if (pairs.length === pairCount) break
  }
  return pairs
}

function applyWordDiffPairBlocks(oldBlock, newBlock) {
  const oldText = htmlToText(oldBlock.html).replace(/\n/g, ' ')
  const newText = htmlToText(newBlock.html).replace(/\n/g, ' ')
  const wd = wordDiff(oldText, newText)
  if (!wd) return
  const oldChangedChars = wd.oldRanges.reduce((s, r) => s + r[1] - r[0], 0)
  const newChangedChars = wd.newRanges.reduce((s, r) => s + r[1] - r[0], 0)
  if (oldText.length > 0 && oldChangedChars / oldText.length > 0.7) return
  if (newText.length > 0 && newChangedChars / newText.length > 0.7) return
  oldBlock.wordDiffHtml = applyWordDiffToHtml(oldBlock.html, wd.oldRanges, 'diff-word-del')
  newBlock.wordDiffHtml = applyWordDiffToHtml(newBlock.html, wd.newRanges, 'diff-word-add')
}

function classifyBlock(block, changedLines) {
  for (let ln = block.startLine; ln <= block.endLine; ln++) {
    if (changedLines.has(ln)) return true
  }
  return false
}

function annotateBlocksWithDiff(blocks, changedLines) {
  return blocks.map(b => Object.assign({}, b, { isDiff: classifyBlock(b, changedLines) }))
}

// Build sets of added/removed line numbers by diffing prev vs current content line by line.
// Uses a simple LCS approach on the line arrays to detect which lines changed.
function buildRoundDiffLineSets(prevContent, currContent) {
  const prevLines = prevContent.split('\n')
  const currLines = currContent.split('\n')

  // Build LCS table
  const m = prevLines.length
  const n = currLines.length
  // Use rolling two-row DP to reduce memory
  let prev = new Uint16Array(n + 1)
  let curr = new Uint16Array(n + 1)
  for (let i = 1; i <= m; i++) {
    for (let j = 1; j <= n; j++) {
      if (prevLines[i - 1] === currLines[j - 1]) {
        curr[j] = prev[j - 1] + 1
      } else {
        curr[j] = Math.max(prev[j], curr[j - 1])
      }
    }
    // Swap rows
    const tmp = prev
    prev = curr
    curr = tmp
    curr.fill(0)
  }

  // Backtrack — need full DP for this, rebuild with a more compact approach
  // Actually for backtracking we need the full table. Use a column-based approach.
  const dp = []
  for (let i = 0; i <= m; i++) dp[i] = new Uint16Array(n + 1)
  for (let i = 1; i <= m; i++) {
    for (let j = 1; j <= n; j++) {
      if (prevLines[i - 1] === currLines[j - 1]) {
        dp[i][j] = dp[i - 1][j - 1] + 1
      } else {
        dp[i][j] = Math.max(dp[i - 1][j], dp[i][j - 1])
      }
    }
  }

  const removedSet = new Set()
  const addedSet = new Set()
  let i = m, j = n
  while (i > 0 && j > 0) {
    if (prevLines[i - 1] === currLines[j - 1]) {
      i--; j--
    } else if (dp[i - 1][j] >= dp[i][j - 1]) {
      removedSet.add(i) // 1-based line number in prev
      i--
    } else {
      addedSet.add(j) // 1-based line number in curr
      j--
    }
  }
  while (i > 0) { removedSet.add(i); i-- }
  while (j > 0) { addedSet.add(j); j-- }

  return { added: addedSet, removed: removedSet }
}

function renderRoundDiffBlock(ctx, block, diffClass, file, commentable, blockIndex, commentsMap, commentedLineSet) {
  const frag = document.createDocumentFragment()
  const lineBlockEl = document.createElement('div')
  lineBlockEl.className = 'line-block'
  lineBlockEl.dataset.filePath = file.path
  if (commentable) {
    lineBlockEl.dataset.blockIndex = blockIndex
    lineBlockEl.dataset.startLine = block.startLine
    lineBlockEl.dataset.endLine = block.endLine
  }
  if (diffClass) lineBlockEl.classList.add(diffClass)

  let blockComments = null
  if (commentable) {
    blockComments = getCommentsForBlock(block, commentsMap)
    if (blockHasComment(block, commentedLineSet)) lineBlockEl.classList.add('has-comment')

    const hasFormForBlock = ctx.activeForms.some(f =>
      !f.editingId && block.startLine >= f.startLine && block.endLine <= f.endLine &&
      (f.filePath || null) === (file.path || null)
    )
    const inCurrentSelection = ctx.selectionStart !== null && ctx.selectionEnd !== null &&
      block.startLine >= ctx.selectionStart && block.endLine <= ctx.selectionEnd
    if (inCurrentSelection) lineBlockEl.classList.add('selected')
    if (hasFormForBlock && !inCurrentSelection) lineBlockEl.classList.add('form-selected')
    if (inCurrentSelection && ctx.dragState) {
      const ds = ctx.dragState
      const isAnchor = block.startLine <= ds.anchorEndLine && block.endLine >= ds.anchorStartLine
      const isCurrent = block.startLine <= ds.currentEndLine && block.endLine >= ds.currentStartLine
      if (isAnchor || isCurrent) lineBlockEl.classList.add('drag-endpoint')
      lineBlockEl.classList.add('drag-range')
      if (block.startLine === ctx.selectionStart) lineBlockEl.classList.add('drag-range-start')
      if (block.endLine === ctx.selectionEnd) lineBlockEl.classList.add('drag-range-end')
    }

    // Comment gutter
    const commentGutter = document.createElement('div')
    commentGutter.className = 'line-comment-gutter'
    commentGutter.dataset.startLine = block.startLine
    commentGutter.dataset.endLine = block.endLine
    commentGutter.dataset.filePath = file.path
    if (ctx.canComment !== false) {
      const lineAdd = document.createElement('span')
      lineAdd.className = 'line-add'
      lineAdd.textContent = '+'
      commentGutter.appendChild(lineAdd)
      commentGutter.addEventListener('mousedown', (e) => handleGutterMouseDown(e, ctx))
    }
    lineBlockEl.appendChild(commentGutter)
  } else {
    const roGutter = document.createElement('div')
    roGutter.className = 'line-comment-gutter diff-no-comment'
    lineBlockEl.appendChild(roGutter)
  }

  // Line number gutter
  const gutter = document.createElement('div')
  gutter.className = 'line-gutter'
  const lineNum = document.createElement('span')
  lineNum.className = 'line-num'
  lineNum.textContent = block.startLine
  gutter.appendChild(lineNum)
  lineBlockEl.insertBefore(gutter, lineBlockEl.firstChild)

  // Content
  const contentEl = document.createElement('div')
  let contentClasses = 'line-content'
  if (block.isEmpty) contentClasses += ' empty-line'
  if (block.cssClass) contentClasses += ' ' + block.cssClass
  contentEl.className = contentClasses
  let html = block.wordDiffHtml || block.html
  html = processTaskLists(html)
  contentEl.innerHTML = html
  lineBlockEl.appendChild(contentEl)

  frag.appendChild(lineBlockEl)

  // Comments after block (only on commentable/new side)
  if (commentable && blockComments) {
    for (const comment of blockComments) {
      frag.appendChild(createCommentElement(comment, ctx))
    }
    const formsHere = ctx.activeForms.filter(f =>
      !f.editingId && f.afterBlockIndex === blockIndex &&
      (f.filePath || null) === (file.path || null)
    )
    for (const formObj of formsHere) {
      frag.appendChild(createCommentForm(formObj, ctx))
    }
  }

  return frag
}

function renderRenderedDiffSplit(ctx, md, file, prevContent) {
  const container = document.createElement('div')
  container.className = 'diff-view'

  const prevBlocks = buildLineBlocks(md, prevContent)
  const currBlocks = file.lineBlocks
  const lineSets = buildRoundDiffLineSets(prevContent, file.content)
  const prevAnnotated = annotateBlocksWithDiff(prevBlocks, lineSets.removed)
  const currAnnotated = annotateBlocksWithDiff(currBlocks, lineSets.added)

  // Word-level diffs for paired changed blocks
  const prevDiffBlocks = prevAnnotated.filter(b => b.isDiff)
  const currDiffBlocks = currAnnotated.filter(b => b.isDiff)
  const pairCount = Math.min(prevDiffBlocks.length, currDiffBlocks.length)
  for (let p = 0; p < pairCount; p++) {
    applyWordDiffPairBlocks(prevDiffBlocks[p], currDiffBlocks[p])
  }

  // Labels row
  const leftLabel = document.createElement('div')
  leftLabel.className = 'diff-view-side-label'
  leftLabel.textContent = 'Previous round'
  container.appendChild(leftLabel)
  const rightLabel = document.createElement('div')
  rightLabel.className = 'diff-view-side-label'
  rightLabel.textContent = 'Current round'
  container.appendChild(rightLabel)

  // Two-pointer merge for horizontal alignment
  const commentsMap = buildCommentsMap(file.comments)
  const commentedLineSet = buildCommentedLineSet(file.comments, ctx)
  let oldIdx = 0, newIdx = 0

  while (oldIdx < prevAnnotated.length || newIdx < currAnnotated.length) {
    const leftCell = document.createElement('div')
    leftCell.className = 'diff-view-cell'
    const rightCell = document.createElement('div')
    rightCell.className = 'diff-view-cell'

    if (oldIdx >= prevAnnotated.length) {
      rightCell.appendChild(renderRoundDiffBlock(ctx, currAnnotated[newIdx], 'diff-added', file, true, newIdx, commentsMap, commentedLineSet))
      newIdx++
    } else if (newIdx >= currAnnotated.length) {
      leftCell.appendChild(renderRoundDiffBlock(ctx, prevAnnotated[oldIdx], 'diff-removed', file, false, oldIdx, null, null))
      oldIdx++
    } else if (prevAnnotated[oldIdx].isDiff && currAnnotated[newIdx].isDiff) {
      leftCell.appendChild(renderRoundDiffBlock(ctx, prevAnnotated[oldIdx], 'diff-removed', file, false, oldIdx, null, null))
      rightCell.appendChild(renderRoundDiffBlock(ctx, currAnnotated[newIdx], 'diff-added', file, true, newIdx, commentsMap, commentedLineSet))
      oldIdx++
      newIdx++
    } else if (prevAnnotated[oldIdx].isDiff) {
      leftCell.appendChild(renderRoundDiffBlock(ctx, prevAnnotated[oldIdx], 'diff-removed', file, false, oldIdx, null, null))
      oldIdx++
    } else if (currAnnotated[newIdx].isDiff) {
      rightCell.appendChild(renderRoundDiffBlock(ctx, currAnnotated[newIdx], 'diff-added', file, true, newIdx, commentsMap, commentedLineSet))
      newIdx++
    } else {
      leftCell.appendChild(renderRoundDiffBlock(ctx, prevAnnotated[oldIdx], null, file, false, oldIdx, null, null))
      rightCell.appendChild(renderRoundDiffBlock(ctx, currAnnotated[newIdx], null, file, true, newIdx, commentsMap, commentedLineSet))
      oldIdx++
      newIdx++
    }

    container.appendChild(leftCell)
    container.appendChild(rightCell)
  }

  return container
}

function renderRenderedDiffUnified(ctx, md, file, prevContent) {
  const container = document.createElement('div')
  container.className = 'diff-view-unified'

  const prevBlocks = buildLineBlocks(md, prevContent)
  const currBlocks = file.lineBlocks
  const lineSets = buildRoundDiffLineSets(prevContent, file.content)

  const commentsMap = buildCommentsMap(file.comments)
  const commentedLineSet = buildCommentedLineSet(file.comments, ctx)

  let oldIdx = 0, newIdx = 0

  while (oldIdx < prevBlocks.length || newIdx < currBlocks.length) {
    if (oldIdx >= prevBlocks.length) {
      container.appendChild(renderRoundDiffBlock(ctx, currBlocks[newIdx], 'diff-added', file, true, newIdx, commentsMap, commentedLineSet))
      newIdx++
    } else if (newIdx >= currBlocks.length) {
      container.appendChild(renderRoundDiffBlock(ctx, prevBlocks[oldIdx], 'diff-removed', file, false, oldIdx, null, null))
      oldIdx++
    } else if (classifyBlock(prevBlocks[oldIdx], lineSets.removed)) {
      // Collect consecutive removed blocks
      const removedRun = []
      while (oldIdx < prevBlocks.length && classifyBlock(prevBlocks[oldIdx], lineSets.removed)) {
        removedRun.push(oldIdx)
        oldIdx++
      }
      // Collect consecutive added blocks
      const addedRun = []
      while (newIdx < currBlocks.length && classifyBlock(currBlocks[newIdx], lineSets.added)) {
        addedRun.push(newIdx)
        newIdx++
      }
      // Pair removed/added blocks by similarity for word diff
      const rmTexts = removedRun.map(idx => htmlToText(prevBlocks[idx].html))
      const adTexts = addedRun.map(idx => htmlToText(currBlocks[idx].html))
      const mdPairs = bestWordDiffPairing(rmTexts, adTexts)
      for (const [rIdx, aIdx] of mdPairs) {
        applyWordDiffPairBlocks(prevBlocks[removedRun[rIdx]], currBlocks[addedRun[aIdx]])
      }
      // Emit all removed then all added
      for (const ri of removedRun) {
        container.appendChild(renderRoundDiffBlock(ctx, prevBlocks[ri], 'diff-removed', file, false, ri, null, null))
      }
      for (const ai of addedRun) {
        container.appendChild(renderRoundDiffBlock(ctx, currBlocks[ai], 'diff-added', file, true, ai, commentsMap, commentedLineSet))
      }
    } else if (classifyBlock(currBlocks[newIdx], lineSets.added)) {
      container.appendChild(renderRoundDiffBlock(ctx, currBlocks[newIdx], 'diff-added', file, true, newIdx, commentsMap, commentedLineSet))
      newIdx++
    } else {
      container.appendChild(renderRoundDiffBlock(ctx, currBlocks[newIdx], null, file, true, newIdx, commentsMap, commentedLineSet))
      newIdx++
      oldIdx++
    }
  }

  return container
}

function renderFileSection(ctx, file) {
  const section = document.createElement('details')
  section.className = 'file-section'
  section.id = 'file-section-' + CSS.escape(file.path)
  if (!file.collapsed) section.open = true

  const header = document.createElement('summary')
  header.className = 'file-header'

  // Scroll correction on collapse
  header.addEventListener('click', function(e) {
    if (e.target.closest('.file-header-viewed') || e.target.closest('.file-comment-btn')) {
      e.preventDefault()
      return
    }
    if (section.open) {
      e.preventDefault()
      if (section.getBoundingClientRect().top < 0) {
        section.scrollIntoView({ behavior: 'instant' })
      }
      section.open = false
      file.collapsed = true
    }
  })
  section.addEventListener('toggle', function() {
    file.collapsed = !section.open
  })

  const fileComments = file.comments.filter(c => c.scope === 'file')
  const dirParts = file.path.split('/')
  const fileName = dirParts.pop()
  const dirPath = dirParts.length > 0 ? dirParts.join('/') + '/' : ''

  header.innerHTML =
    '<div class="file-header-chevron"><svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path d="M12.78 5.22a.749.749 0 0 1 0 1.06l-4.25 4.25a.749.749 0 0 1-1.06 0L3.22 6.28a.749.749 0 1 1 1.06-1.06L8 8.939l3.72-3.719a.749.749 0 0 1 1.06 0Z"/></svg></div>' +
    '<svg class="file-header-icon" viewBox="0 0 16 16" fill="var(--crit-editor-fg-muted)"><path fill-rule="evenodd" d="M3.75 1.5a.25.25 0 0 0-.25.25v12.5c0 .138.112.25.25.25h8.5a.25.25 0 0 0 .25-.25V6H9.75A1.75 1.75 0 0 1 8 4.25V1.5H3.75zm5.75.56v2.19c0 .138.112.25.25.25h2.19L9.5 2.06zM2 1.75C2 .784 2.784 0 3.75 0h5.086c.464 0 .909.184 1.237.513l3.414 3.414c.329.328.513.773.513 1.237v8.086A1.75 1.75 0 0 1 12.25 15h-8.5A1.75 1.75 0 0 1 2 13.25V1.75z"/></svg>' +
    '<span class="file-header-name"><span class="dir">' + escapeHtml(dirPath) + '</span>' + escapeHtml(fileName) + '</span>' +
    (file.orphaned ? '<span class="file-header-badge removed">Removed</span>' : '')

  // File comment button — not for orphaned files (no point adding comments to removed files).
  // Also gated on canComment: when policy disallows new comments, don't create the
  // affordance or its click handler.
  if (!file.orphaned && ctx.canComment !== false) {
    const fileCommentBtn = document.createElement('button')
    fileCommentBtn.className = 'file-comment-btn'
    fileCommentBtn.title = 'Add file comment'
    fileCommentBtn.innerHTML = '<svg viewBox="0 0 16 16" fill="currentColor"><path d="M1 2.75C1 1.784 1.784 1 2.75 1h10.5c.966 0 1.75.784 1.75 1.75v7.5A1.75 1.75 0 0 1 13.25 12H9.06l-2.573 2.573A1.458 1.458 0 0 1 4 13.543V12H2.75A1.75 1.75 0 0 1 1 10.25Zm1.75-.25a.25.25 0 0 0-.25.25v7.5c0 .138.112.25.25.25h2a.75.75 0 0 1 .75.75v2.19l2.72-2.72a.749.749 0 0 1 .53-.22h4.5a.25.25 0 0 0 .25-.25v-7.5a.25.25 0 0 0-.25-.25Z"/></svg>'
    fileCommentBtn.addEventListener('click', function(e) {
      e.preventDefault()
      e.stopPropagation()
      openFileCommentForm(ctx, file.path)
    })
    header.appendChild(fileCommentBtn)
  }

  // Viewed checkbox
  const viewedLabel = document.createElement('label')
  viewedLabel.className = 'file-header-viewed'
  viewedLabel.title = 'Viewed'
  viewedLabel.innerHTML = '<input type="checkbox"' + (file.viewed ? ' checked' : '') + '><span>Viewed</span>'
  viewedLabel.addEventListener('click', function(e) {
    e.stopPropagation()
  })
  viewedLabel.querySelector('input').addEventListener('change', function() {
    toggleViewed(ctx, file.path)
  })
  header.appendChild(viewedLabel)

  section.appendChild(header)

  // File-level comments (between header and body)
  // For orphaned files, render ALL comments here (no line blocks to anchor to)
  const isOrphaned = file.orphaned
  const displayComments = isOrphaned ? file.comments : fileComments
  if (displayComments.length > 0 || (!isOrphaned && ctx.activeForms.some(f => f.scope === 'file' && f.filePath === file.path))) {
    const fileCommentsContainer = document.createElement('div')
    fileCommentsContainer.className = 'file-comments'
    for (const c of displayComments) {
      const card = renderPanelCard(ctx, c, file.path)
      card.style.cursor = ''
      fileCommentsContainer.appendChild(card)
    }
    // Render file comment form if active (not for orphaned files)
    if (!isOrphaned) {
      const fileForm = ctx.activeForms.find(f => f.scope === 'file' && f.filePath === file.path)
      if (fileForm) {
        fileCommentsContainer.appendChild(renderCommentFormUI(ctx, fileForm))
      }
    }
    section.appendChild(fileCommentsContainer)
  }

  // File body — render using renderBlock per block, or diff view if round diff is active
  const body = document.createElement('div')
  body.className = 'file-body' + (file.fileType === 'code' ? ' code-document' : '')

  if (file.orphaned) {
    // Orphaned files show a placeholder instead of content
    const placeholder = document.createElement('div')
    placeholder.className = 'diff-deleted-placeholder orphaned-placeholder'
    placeholder.textContent = 'This file is no longer part of the review.'
    body.appendChild(placeholder)
  } else {
    const prevContent = ctx.prevRoundSnapshots[file.path]
    if (ctx.showRoundDiff && prevContent != null && file.fileType !== 'code') {
      // Round diff mode — render split or unified diff view
      const isSplit = ctx.diffMode === 'split'
      body.classList.toggle('diff-split', isSplit)
      const diffContainer = isSplit
        ? renderRenderedDiffSplit(ctx, ctx.md, file, prevContent)
        : renderRenderedDiffUnified(ctx, ctx.md, file, prevContent)
      body.appendChild(diffContainer)
    } else {
      const commentsMap = buildCommentsMap(file.comments)
      const commentedLineSet = buildCommentedLineSet(file.comments, ctx)
      const lineBlocks = file.lineBlocks

      for (let i = 0; i < lineBlocks.length; i++) {
        const block = lineBlocks[i]
        const blockEl = renderBlock(ctx, block, i, commentsMap, commentedLineSet, file.path)
        body.appendChild(blockEl)
      }
    }

    if (file.fileType !== 'code') {
      replaceBrokenImages(body)
    }
  }

  section.appendChild(body)
  highlightQuotesInSection(section, file, ctx.activeForms)
  return section
}

// ===== Quote Highlighting in Document Body =====

function highlightQuotesInSection(sectionEl, file, activeForms) {
  var quotedComments = file.comments.filter(function(c) { return c.quote && !c.resolved })

  // Include quotes from open comment forms (shown before the comment is saved)
  if (activeForms) {
    activeForms.forEach(function(f) {
      if (f.quote && !f.editingId && (f.filePath || null) === (file.path || null)) {
        quotedComments.push({
          quote: f.quote,
          start_line: f.startLine,
          end_line: f.endLine,
          id: f.formKey,
          resolved: false,
        })
      }
    })
  }

  if (quotedComments.length === 0) return

  quotedComments.forEach(function(comment) {
    // Find the content elements in this comment's line range
    var contentEls = []
    for (var ln = comment.start_line; ln <= comment.end_line; ln++) {
      sectionEl.querySelectorAll('.line-block[data-file-path="' + CSS.escape(file.path) + '"]').forEach(function(el) {
        var s = parseInt(el.dataset.startLine)
        var e = parseInt(el.dataset.endLine)
        if (s <= ln && e >= ln) {
          var content = el.querySelector('.line-content')
          if (content && contentEls.indexOf(content) === -1) contentEls.push(content)
        }
      })
    }

    if (contentEls.length === 0) return

    // Collect all text nodes across the content elements
    var textNodes = []
    contentEls.forEach(function(el) {
      var walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT, null)
      var node
      while ((node = walker.nextNode())) {
        if (node.textContent.length > 0) textNodes.push(node)
      }
    })

    if (textNodes.length === 0) return

    // Build concatenated text and find the quote within it.
    // Normalize the quote: collapse whitespace/newlines so cross-line selections match.
    var fullText = textNodes.map(function(n) { return n.textContent }).join('')
    var normalizedQuote = comment.quote.replace(/\s+/g, ' ')
    var normalizedFull = fullText.replace(/\s+/g, ' ')
    var quoteIdx = -1
    // Use quote_offset when available to disambiguate duplicate substrings
    if (comment.quote_offset != null) {
      var candidateIdx = comment.quote_offset
      if (normalizedFull.substring(candidateIdx, candidateIdx + normalizedQuote.length) === normalizedQuote) {
        quoteIdx = candidateIdx
      }
    }
    if (quoteIdx === -1) {
      quoteIdx = normalizedFull.indexOf(normalizedQuote)
    }
    if (quoteIdx === -1) {
      quoteIdx = normalizedFull.toLowerCase().indexOf(normalizedQuote.toLowerCase())
    }
    if (quoteIdx === -1) return

    // Map the normalized index back to the original fullText position.
    var origIdx = 0, normIdx = 0
    while (normIdx < quoteIdx && origIdx < fullText.length) {
      if (/\s/.test(fullText[origIdx])) {
        while (origIdx < fullText.length && /\s/.test(fullText[origIdx])) origIdx++
        normIdx++
      } else {
        origIdx++
        normIdx++
      }
    }
    quoteIdx = origIdx
    // Find the end position similarly
    var matchLen = 0, ni = 0
    while (ni < normalizedQuote.length && (origIdx + matchLen) < fullText.length) {
      if (/\s/.test(fullText[origIdx + matchLen])) {
        while ((origIdx + matchLen) < fullText.length && /\s/.test(fullText[origIdx + matchLen])) matchLen++
        ni++
      } else {
        matchLen++
        ni++
      }
    }

    // Walk text nodes to find which ones overlap with the quote range
    var quoteEnd = quoteIdx + matchLen
    var pos = 0
    for (var i = 0; i < textNodes.length; i++) {
      var node = textNodes[i]
      var nodeEnd = pos + node.textContent.length
      if (nodeEnd <= quoteIdx) { pos = nodeEnd; continue }
      if (pos >= quoteEnd) break

      // This node overlaps with the quote range
      var startInNode = Math.max(0, quoteIdx - pos)
      var endInNode = Math.min(node.textContent.length, quoteEnd - pos)

      // Skip wrapping whitespace-only matches (e.g. newlines between blocks)
      var matchText = node.textContent.slice(startInNode, endInNode)
      if (!matchText.trim()) { pos = nodeEnd; continue }

      if (startInNode === 0 && endInNode === node.textContent.length) {
        // Wrap entire text node
        var mark = document.createElement('mark')
        mark.className = 'quote-highlight'
        mark.dataset.commentId = comment.id
        node.parentNode.replaceChild(mark, node)
        mark.appendChild(node)
      } else {
        // Split and wrap partial text
        var before = node.textContent.slice(0, startInNode)
        var middle = node.textContent.slice(startInNode, endInNode)
        var after = node.textContent.slice(endInNode)
        var frag = document.createDocumentFragment()
        if (before) frag.appendChild(document.createTextNode(before))
        var mark = document.createElement('mark')
        mark.className = 'quote-highlight'
        mark.dataset.commentId = comment.id
        mark.textContent = middle
        frag.appendChild(mark)
        if (after) frag.appendChild(document.createTextNode(after))
        node.parentNode.replaceChild(frag, node)
      }
      pos = nodeEnd
    }
  })
}

// ---- Render document --------------------------------------------------------

function buildCommentsMap(comments) {
  const map = {}
  for (const c of comments) {
    if (c.scope === 'file' || c.scope === 'review') continue
    if (!c.end_line) continue
    if (!map[c.end_line]) map[c.end_line] = []
    map[c.end_line].push(c)
  }
  return map
}

function buildCommentedLineSet(comments, ctx) {
  const set = new Set()
  const hideResolved = ctx ? isHideResolved(ctx) : readHideResolved()
  for (const c of comments) {
    if (c.scope === 'file' || c.scope === 'review') continue
    if (!c.start_line || !c.end_line) continue
    if (hideResolved && c.resolved) continue
    for (let ln = c.start_line; ln <= c.end_line; ln++) set.add(ln)
  }
  return set
}

function refreshCommentHighlights(ctx) {
  if (!ctx || !ctx.el || !ctx.comments) return
  // Build per-file commented line sets so we can include/exclude file paths.
  const byPath = new Map()
  const hideResolved = isHideResolved(ctx)
  for (const c of ctx.comments) {
    if (c.scope === 'file' || c.scope === 'review') continue
    if (!c.start_line || !c.end_line) continue
    if (hideResolved && c.resolved) continue
    const fp = c.file_path || null
    let set = byPath.get(fp)
    if (!set) { set = new Set(); byPath.set(fp, set) }
    for (let ln = c.start_line; ln <= c.end_line; ln++) set.add(ln)
  }
  ctx.el.querySelectorAll('.line-block').forEach(function(lb) {
    const start = parseInt(lb.dataset.startLine)
    const end = parseInt(lb.dataset.endLine)
    if (Number.isNaN(start) || Number.isNaN(end)) return
    const fp = lb.dataset.filePath || null
    const set = byPath.get(fp)
    let has = false
    if (set) {
      for (let ln = start; ln <= end; ln++) {
        if (set.has(ln)) { has = true; break }
      }
    }
    lb.classList.toggle('has-comment', has)
  })
}

function getCommentsForBlock(block, commentsMap) {
  const result = []
  for (let ln = block.startLine; ln <= block.endLine; ln++) {
    if (commentsMap[ln]) result.push(...commentsMap[ln])
  }
  return result
}

function blockHasComment(block, commentedLineSet) {
  for (let ln = block.startLine; ln <= block.endLine; ln++) {
    if (commentedLineSet.has(ln)) return true
  }
  return false
}

function renderBlock(ctx, block, index, commentsMap, commentedLineSet, filePath) {
  const fragment = document.createDocumentFragment()

  const lineBlockEl = document.createElement("div")
  lineBlockEl.className = "line-block"
  lineBlockEl.dataset.blockIndex = index
  lineBlockEl.dataset.startLine = block.startLine
  lineBlockEl.dataset.endLine = block.endLine
  lineBlockEl.dataset.filePath = filePath || ''

  const blockComments = getCommentsForBlock(block, commentsMap)
  if (blockHasComment(block, commentedLineSet)) lineBlockEl.classList.add("has-comment")

  // Check if any active form covers this block for selection highlighting
  const hasFormForBlock = ctx.activeForms.some(f =>
    !f.editingId && block.startLine >= f.startLine && block.endLine <= f.endLine &&
    (f.filePath || null) === (filePath || null)
  )
  const inCurrentSelection = ctx.selectionStart !== null && ctx.selectionEnd !== null &&
    block.startLine >= ctx.selectionStart && block.endLine <= ctx.selectionEnd
  if (inCurrentSelection) {
    lineBlockEl.classList.add("selected")
  }
  if (hasFormForBlock && !inCurrentSelection) {
    lineBlockEl.classList.add("form-selected")
  }
  if (inCurrentSelection && ctx.dragState) {
    const ds = ctx.dragState
    const isAnchor = block.startLine <= ds.anchorEndLine && block.endLine >= ds.anchorStartLine
    const isCurrent = block.startLine <= ds.currentEndLine && block.endLine >= ds.currentStartLine
    if (isAnchor || isCurrent) lineBlockEl.classList.add("drag-endpoint")
    lineBlockEl.classList.add("drag-range")
    if (block.startLine === ctx.selectionStart) lineBlockEl.classList.add("drag-range-start")
    if (block.endLine === ctx.selectionEnd) lineBlockEl.classList.add("drag-range-end")
  }

  // Gutter
  const gutter = document.createElement("div")
  gutter.className = "line-gutter"
  gutter.dataset.startLine = block.startLine
  gutter.dataset.endLine = block.endLine

  const lineNum = document.createElement("span")
  lineNum.className = "line-num"
  lineNum.textContent = block.startLine === block.endLine ? block.startLine : String(block.startLine)

  const commentGutter = document.createElement("div")
  commentGutter.className = "line-comment-gutter"
  if (ctx.canComment !== false) {
    const lineAdd = document.createElement("span")
    lineAdd.className = "line-add"
    lineAdd.textContent = "+"
    commentGutter.appendChild(lineAdd)
  }

  gutter.appendChild(lineNum)
  gutter.appendChild(commentGutter)
  if (ctx.canComment !== false) {
    gutter.addEventListener("mousedown", (e) => handleGutterMouseDown(e, ctx))
  }

  // Content
  const content = document.createElement("div")
  let contentClasses = "line-content"
  if (block.isEmpty) contentClasses += " empty-line"
  if (block.cssClass) contentClasses += " " + block.cssClass
  content.className = contentClasses
  let html = block.html
  html = processTaskLists(html)
  content.innerHTML = html

  lineBlockEl.appendChild(gutter)
  lineBlockEl.appendChild(content)
  fragment.appendChild(lineBlockEl)

  // Comments after this block
  for (const comment of blockComments) {
    fragment.appendChild(createCommentElement(comment, ctx))
  }

  // New comment forms after this block
  const formsHere = ctx.activeForms.filter(f =>
    !f.editingId && f.afterBlockIndex === index &&
    (f.filePath || null) === (filePath || null)
  )
  for (const formObj of formsHere) {
    fragment.appendChild(createCommentForm(formObj, ctx))
  }

  return fragment
}

function renderDocument(ctx) {
  saveOpenFormContent(ctx)
  const container = ctx.el
  container.innerHTML = ""

  // Round diff mode for single-file reviews
  if (ctx.showRoundDiff && ctx.singleFilePath && !isCodeFile(ctx.singleFilePath)) {
    const prevContent = ctx.prevRoundSnapshots[ctx.singleFilePath]
    if (prevContent != null) {
      const file = {
        path: ctx.singleFilePath,
        content: ctx.rawContent,
        fileType: 'markdown',
        lineBlocks: ctx.lineBlocks,
        comments: ctx.comments,
      }
      const isSplit = ctx.diffMode === 'split'
      container.classList.toggle('round-diff-split', isSplit)
      const diffEl = isSplit
        ? renderRenderedDiffSplit(ctx, ctx.md, file, prevContent)
        : renderRenderedDiffUnified(ctx, ctx.md, file, prevContent)
      container.appendChild(diffEl)
      renderMermaidBlocks(container)
      replaceBrokenImages(container)
      updateCommentCount(ctx)
      return
    }
  }
  container.classList.remove('round-diff-split')

  const commentsMap = buildCommentsMap(ctx.comments)
  const commentedLineSet = buildCommentedLineSet(ctx.comments, ctx)

  for (let bi = 0; bi < ctx.lineBlocks.length; bi++) {
    const block = ctx.lineBlocks[bi]
    container.appendChild(renderBlock(ctx, block, bi, commentsMap, commentedLineSet, ctx.singleFilePath || null))
  }

  renderMermaidBlocks(container)
  replaceBrokenImages(container)
  highlightQuotesInSection(container, { path: ctx.singleFilePath, comments: ctx.comments }, ctx.activeForms)
  updateCommentCount(ctx)

  if (ctx.focusedBlockIndex >= 0) {
    const blocks = container.querySelectorAll('.line-block')
    if (ctx.focusedBlockIndex < blocks.length) {
      blocks[ctx.focusedBlockIndex].classList.add('focused')
    }
  }
}

function replaceBrokenImages(container) {
  container.querySelectorAll("img").forEach(img => {
    const replace = () => {
      const span = document.createElement("span")
      span.className = "img-placeholder"
      span.textContent = img.alt ? `[image: ${img.alt}]` : "[image]"
      img.replaceWith(span)
    }
    if (!img.complete || img.naturalWidth === 0) {
      img.addEventListener("error", replace, { once: true })
    }
  })
}

function updateCommentCount(ctx) {
  const el = document.getElementById('comment-count')
  if (!el) return
  const numEl = document.getElementById('commentCountNumber')
  const unresolvedCount = ctx.comments.filter(c => !c.resolved).length
  const resolvedCount = ctx.comments.filter(c => c.resolved).length
  const total = unresolvedCount + resolvedCount
  if (total === 0) {
    el.title = 'Toggle comments panel'
    el.classList.remove('comment-count-resolved')
    if (numEl) numEl.textContent = ''
  } else if (unresolvedCount > 0) {
    el.classList.remove('comment-count-resolved')
    el.title = unresolvedCount + ' unresolved comment' + (unresolvedCount === 1 ? '' : 's') + ' — toggle panel'
    if (numEl) numEl.textContent = unresolvedCount
  } else {
    el.classList.add('comment-count-resolved')
    el.title = resolvedCount + ' resolved comment' + (resolvedCount === 1 ? '' : 's') + ' — toggle panel'
    if (numEl) numEl.textContent = '\u2713'
  }
  const navGroup = document.getElementById('comment-nav-group')
  if (navGroup) navGroup.classList.toggle('has-comments', total > 0)
}

// ---- Gutter drag selection --------------------------------------------------

function handleGutterMouseDown(e, ctx) {
  e.preventDefault()
  const gutter = e.currentTarget
  const startLine = parseInt(gutter.dataset.startLine)
  const endLine = parseInt(gutter.dataset.endLine)
  const blockEl = gutter.parentElement
  const blockIndex = parseInt(blockEl.dataset.blockIndex)
  const filePath = blockEl.dataset.filePath || null

  // Shift+click: extend selection from previous anchor
  if (e.shiftKey && ctx.selectionStart !== null) {
    const lineBlocks = filePath ? (ctx.files.find(f => f.path === filePath)?.lineBlocks || ctx.lineBlocks) : ctx.lineBlocks
    const rangeStart = Math.min(ctx.selectionStart, startLine)
    const rangeEnd = Math.max(ctx.selectionEnd, endLine)
    let lastBlockIndex = 0
    for (let i = 0; i < lineBlocks.length; i++) {
      if (lineBlocks[i].startLine >= rangeStart && lineBlocks[i].endLine <= rangeEnd) {
        lastBlockIndex = i
      }
    }
    openForm(ctx, { afterBlockIndex: lastBlockIndex, startLine: rangeStart, endLine: rangeEnd, editingId: null, filePath: filePath })
    return
  }

  ctx.dragState = {
    anchorStartLine: startLine,
    anchorEndLine: endLine,
    anchorBlockIndex: blockIndex,
    currentStartLine: startLine,
    currentEndLine: endLine,
    currentBlockIndex: blockIndex,
    filePath: filePath,
  }

  ctx.selectionStart = startLine
  ctx.selectionEnd = endLine
  render(ctx)

  document.body.classList.add("dragging")

  const onMove = (e) => handleDragMove(e, ctx)
  const onUp = (_e) => handleDragEnd(_e, ctx, onMove, onUp)
  document.addEventListener("mousemove", onMove)
  document.addEventListener("mouseup", onUp)
}

function handleDragMove(e, ctx) {
  if (!ctx.dragState) return
  const el = document.elementFromPoint(e.clientX, e.clientY)
  if (!el) return
  const lineBlock = el.closest(".line-block")
  if (!lineBlock) return

  // Reject cross-file drag selections
  const blockFilePath = lineBlock.dataset.filePath || null
  if (blockFilePath !== (ctx.dragState.filePath || null)) return

  ctx.dragState.currentStartLine = parseInt(lineBlock.dataset.startLine)
  ctx.dragState.currentEndLine = parseInt(lineBlock.dataset.endLine)
  ctx.dragState.currentBlockIndex = parseInt(lineBlock.dataset.blockIndex)

  ctx.selectionStart = Math.min(ctx.dragState.anchorStartLine, ctx.dragState.currentStartLine)
  ctx.selectionEnd = Math.max(ctx.dragState.anchorEndLine, ctx.dragState.currentEndLine)
  render(ctx)
}

function handleDragEnd(_e, ctx, onMove, onUp) {
  document.removeEventListener("mousemove", onMove)
  document.removeEventListener("mouseup", onUp)
  document.body.classList.remove("dragging")

  if (!ctx.dragState) return

  const rangeStart = Math.min(ctx.dragState.anchorStartLine, ctx.dragState.currentStartLine)
  const rangeEnd = Math.max(ctx.dragState.anchorEndLine, ctx.dragState.currentEndLine)
  const filePath = ctx.dragState.filePath || null

  const lineBlocks = filePath ? (ctx.files.find(f => f.path === filePath)?.lineBlocks || ctx.lineBlocks) : ctx.lineBlocks
  let lastBlockIndex = 0
  for (let i = 0; i < lineBlocks.length; i++) {
    if (lineBlocks[i].startLine >= rangeStart && lineBlocks[i].endLine <= rangeEnd) {
      lastBlockIndex = i
    }
  }

  ctx.dragState = null
  openForm(ctx, { afterBlockIndex: lastBlockIndex, startLine: rangeStart, endLine: rangeEnd, editingId: null, filePath: filePath })
}

// ---- Comment elements -------------------------------------------------------

function createCommentElement(comment, ctx) {
  // Dispatch resolved comments to their own renderer
  if (comment.resolved) {
    return createResolvedElement(comment, ctx)
  }

  const editForm = findFormForEdit(ctx, comment.id)
  if (editForm) {
    return createInlineEditor(comment, editForm, ctx)
  }

  const isOwn = isOwnComment(comment, ctx)
  const canResolve = isOwn || isReviewOwner(ctx)

  const wrapper = document.createElement("div")
  wrapper.className = "comment-block"

  const card = document.createElement("div")
  card.className = "comment-card"
  card.dataset.commentId = comment.id

  // Apply saved collapse state (unresolved defaults to expanded)
  if (commentCollapseOverrides[comment.id] === true) card.classList.add('collapsed')

  const header = document.createElement("div")
  header.className = "comment-header"

  const lineRef = document.createElement("span")
  lineRef.className = "comment-line-ref"
  lineRef.textContent = comment.start_line === comment.end_line
    ? `Line ${comment.start_line}`
    : `Lines ${comment.start_line}–${comment.end_line}`

  const time = document.createElement("span")
  time.className = "comment-time"
  time.textContent = formatTime(comment.created_at)

  const collapseBtn = document.createElement('button')
  collapseBtn.className = 'comment-collapse-btn'
  collapseBtn.title = card.classList.contains('collapsed') ? 'Expand comment' : 'Collapse comment'
  collapseBtn.innerHTML = '<svg viewBox="0 0 16 16" fill="currentColor" width="16" height="16"><path d="M12.78 5.22a.75.75 0 0 1 0 1.06l-4.25 4.25a.75.75 0 0 1-1.06 0L3.22 6.28a.75.75 0 0 1 1.06-1.06L8 8.94l3.72-3.72a.75.75 0 0 1 1.06 0Z"/></svg>'
  collapseBtn.addEventListener('click', function(e) {
    e.stopPropagation()
    card.classList.toggle('collapsed')
    commentCollapseOverrides[comment.id] = card.classList.contains('collapsed')
    collapseBtn.title = card.classList.contains('collapsed') ? 'Expand comment' : 'Collapse comment'
  })

  const headerLeft = document.createElement("div")
  headerLeft.className = "comment-header-left"
  headerLeft.appendChild(collapseBtn)

  if (comment.author_display_name) {
    const authorBadge = document.createElement('span')
    authorBadge.className = 'comment-author-badge author-color-' + authorColorIndex(comment.author_display_name)
    authorBadge.textContent = '@' + comment.author_display_name
    headerLeft.appendChild(authorBadge)
  } else {
    const author = document.createElement("span")
    author.className = "comment-author" + (isOwn ? " comment-author-you" : "")
    author.innerHTML =
      `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="comment-author-icon"><path fill-rule="evenodd" d="M18.685 19.097A9.723 9.723 0 0 0 21.75 12c0-5.385-4.365-9.75-9.75-9.75S2.25 6.615 2.25 12a9.723 9.723 0 0 0 3.065 7.097A9.716 9.716 0 0 0 12 21.75a9.716 9.716 0 0 0 6.685-2.653Zm-12.54-1.285A7.486 7.486 0 0 1 12 15a7.486 7.486 0 0 1 5.855 2.812A8.224 8.224 0 0 1 12 20.25a8.224 8.224 0 0 1-5.855-2.438ZM15.75 9a3.75 3.75 0 1 1-7.5 0 3.75 3.75 0 0 1 7.5 0Z" clip-rule="evenodd"/></svg>` +
      (isOwn ? (ctx.displayName || "You") : (comment.author_identity || "?").slice(0, 20))
    headerLeft.appendChild(author)
  }

  if (comment.review_round >= 1) {
    const roundBadge = document.createElement("span")
    const rc = comment.review_round === ctx.reviewRound ? " round-current" : comment.review_round === ctx.reviewRound - 1 ? " round-latest" : ""
    roundBadge.className = "comment-round-badge" + rc
    roundBadge.textContent = "R" + comment.review_round
    headerLeft.appendChild(roundBadge)
  }
  headerLeft.appendChild(lineRef)
  headerLeft.appendChild(time)

  header.appendChild(headerLeft)

  const actions = document.createElement("div")
  actions.className = "comment-actions"

  if (canResolve) {
    const resolveBtn = document.createElement('button')
    resolveBtn.className = 'resolve-btn'
    resolveBtn.title = 'Resolve'
    resolveBtn.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg><span>Resolve</span>'
    resolveBtn.addEventListener('click', function() {
      ctx.pushEvent("resolve_comment", { id: comment.id, resolved: true })
    })
    actions.appendChild(resolveBtn)
  }

  if (isOwn) {
    const editBtn = document.createElement("button")
    editBtn.title = "Edit"
    editBtn.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z"/><path d="m15 5 4 4"/></svg>'
    editBtn.addEventListener("click", () => {
      const editFormObj = { afterBlockIndex: null, startLine: comment.start_line, endLine: comment.end_line, editingId: comment.id, filePath: comment.file_path || null }
      addForm(ctx, editFormObj)
      render(ctx)
    })

    const deleteBtn = document.createElement("button")
    deleteBtn.className = "delete-btn"
    deleteBtn.title = "Delete"
    deleteBtn.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/></svg>'
    deleteBtn.addEventListener("click", () => {
      ctx.pushEvent("delete_comment", { id: comment.id })
    })

    actions.appendChild(editBtn)
    actions.appendChild(deleteBtn)
  }

  header.appendChild(actions)

  const body = document.createElement("div")
  body.className = "comment-body"
  const env = {}
  if (ctx && comment.start_line && comment.end_line && !comment.side) {
    if (comment.quote) {
      env.originalLines = comment.quote.split('\n')
    } else {
      let fileContent = ctx.rawContent
      if (ctx.multiFile && comment.file_path) {
        const file = ctx.files && ctx.files.find(f => f.path === comment.file_path)
        if (file) fileContent = file.content
      }
      if (fileContent) {
        env.originalLines = fileContent.split('\n').slice(comment.start_line - 1, comment.end_line)
      }
    }
  }
  body.innerHTML = commentMd.render(comment.body, env)

  card.appendChild(header)
  card.appendChild(body)

  // Render replies (threading)
  if (comment.replies && comment.replies.length > 0) {
    card.appendChild(renderReplyList(comment, ctx))
  }

  // Inline reply input (GitHub-style: compact, expands on focus).
  // A reply is a new comment, so respect comment policy.
  if (ctx.canComment !== false) {
    card.appendChild(createReplyInput(comment.id, ctx))
  }

  wrapper.appendChild(card)
  return wrapper
}

function createCommentForm(formObj, ctx) {
  const wrapper = document.createElement("div")
  wrapper.className = "comment-form-wrapper"

  const form = document.createElement("div")
  form.className = "comment-form"
  form.dataset.formKey = formObj.formKey

  const header = document.createElement("div")
  header.className = "comment-form-header"
  const lineRef = formObj.startLine === formObj.endLine
    ? `Line ${formObj.startLine}`
    : `Lines ${formObj.startLine}–${formObj.endLine}`
  header.textContent = `Comment on ${lineRef}`

  const templateBar = document.createElement('div')
  templateBar.className = 'comment-template-bar'

  const textarea = document.createElement("textarea")
  textarea.placeholder = "Leave a review comment… (Ctrl+Enter to submit, Escape to cancel)"
  textarea.dataset.formKey = formObj.formKey

  // Restore draft
  const savedDraft = loadDraft(ctx.reviewToken, formObj)
  if (savedDraft) {
    textarea.value = savedDraft
  } else if (formObj.draftBody) {
    textarea.value = formObj.draftBody
  }

  // Autosave draft
  textarea.addEventListener('input', () => {
    scheduleDraftSave(ctx.reviewToken, textarea.value, formObj)
  })

  textarea.addEventListener("keydown", (e) => {
    if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) {
      e.preventDefault()
      e.stopPropagation()
      submitNewComment(textarea.value, formObj, ctx)
    } else if (e.key === "Escape") {
      e.preventDefault()
      e.stopPropagation()
      if (confirmDiscardIfDirty(formObj)) cancelComment(formObj, ctx)
    }
  })

  const actions = document.createElement("div")
  actions.className = "comment-form-actions"

  const leftGroup = document.createElement('div')
  leftGroup.className = 'comment-form-actions-left'
  leftGroup.style.marginRight = 'auto'

  const suggestBtn = document.createElement("button")
  suggestBtn.className = "btn btn-sm"
  suggestBtn.textContent = "\u00B1 Suggest"
  suggestBtn.title = "Insert the selected lines as a suggestion"
  suggestBtn.addEventListener("click", () => insertSuggestion(textarea, formObj, ctx))
  leftGroup.appendChild(suggestBtn)

  const saveTemplateBtn = document.createElement('button')
  saveTemplateBtn.className = 'btn btn-sm'
  saveTemplateBtn.textContent = '+ Template'
  saveTemplateBtn.addEventListener('click', (e) => {
    e.preventDefault()
    showSaveTemplateDialog(textarea, templateBar)
  })
  leftGroup.appendChild(saveTemplateBtn)

  const cancelBtn = document.createElement("button")
  cancelBtn.className = "btn btn-sm"
  cancelBtn.textContent = "Cancel"
  cancelBtn.addEventListener("click", () => cancelComment(formObj, ctx))

  const submitBtn = document.createElement("button")
  submitBtn.className = "btn btn-sm btn-primary"
  submitBtn.textContent = "Comment"
  submitBtn.addEventListener("click", () => submitNewComment(textarea.value, formObj, ctx))

  actions.appendChild(leftGroup)
  actions.appendChild(cancelBtn)
  actions.appendChild(submitBtn)
  populateTemplateBar(templateBar, textarea)
  form.appendChild(header)
  form.appendChild(templateBar)
  form.appendChild(textarea)
  form.appendChild(actions)
  wrapper.appendChild(form)
  return wrapper
}

function createInlineEditor(comment, formObj, ctx) {
  const wrapper = document.createElement("div")
  wrapper.className = "comment-form-wrapper"

  const form = document.createElement("div")
  form.className = "comment-form"
  form.dataset.formKey = formObj.formKey

  const header = document.createElement("div")
  header.className = "comment-form-header"
  const lineRef = comment.start_line === comment.end_line
    ? `Line ${comment.start_line}`
    : `Lines ${comment.start_line}–${comment.end_line}`
  header.textContent = `Editing comment on ${lineRef}`

  const textarea = document.createElement("textarea")
  textarea.placeholder = "Leave a review comment… (Ctrl+Enter to submit, Escape to cancel)"
  textarea.value = comment.body
  textarea.dataset.formKey = formObj.formKey

  textarea.addEventListener("keydown", (e) => {
    if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) {
      e.preventDefault()
      e.stopPropagation()
      submitEditComment(comment.id, textarea.value, formObj, ctx)
    } else if (e.key === "Escape") {
      e.preventDefault()
      e.stopPropagation()
      if (confirmDiscardIfDirty(formObj)) cancelComment(formObj, ctx)
    }
  })

  const actions = document.createElement("div")
  actions.className = "comment-form-actions"

  const suggestBtn = document.createElement("button")
  suggestBtn.className = "btn btn-sm"
  suggestBtn.textContent = "\u00B1 Suggest"
  suggestBtn.title = "Insert the selected lines as a suggestion"
  suggestBtn.style.marginRight = "auto"
  suggestBtn.addEventListener("click", () => insertSuggestion(textarea, formObj, ctx))

  const cancelBtn = document.createElement("button")
  cancelBtn.className = "btn btn-sm"
  cancelBtn.textContent = "Cancel"
  cancelBtn.addEventListener("click", () => cancelComment(formObj, ctx))

  const submitBtn = document.createElement("button")
  submitBtn.className = "btn btn-sm btn-primary"
  submitBtn.textContent = "Update"
  submitBtn.addEventListener("click", () => submitEditComment(comment.id, textarea.value, formObj, ctx))

  actions.appendChild(suggestBtn)
  actions.appendChild(cancelBtn)
  actions.appendChild(submitBtn)
  form.appendChild(header)
  form.appendChild(textarea)
  form.appendChild(actions)

  // Keep replies visible below the edit form, inside the form's card
  if (comment.replies && comment.replies.length > 0) {
    form.appendChild(renderReplyList(comment, ctx))
  }

  wrapper.appendChild(form)

  requestAnimationFrame(() => textarea.focus())
  return wrapper
}

function submitNewComment(body, formObj, ctx) {
  if (!body.trim()) return
  clearDraft(ctx.reviewToken, formObj)
  const payload = {
    body: body.trim(),
    file_path: formObj.filePath || null,
    scope: formObj.scope || 'line',
  }
  if (formObj.scope !== 'file' && formObj.scope !== 'review') {
    payload.start_line = formObj.startLine
    payload.end_line = formObj.endLine
  }
  if (formObj.quote) payload.quote = formObj.quote
  ctx.pushEvent("add_comment", payload)
  removeForm(ctx, formObj.formKey)
  if (ctx.activeForms.length === 0) {
    ctx.selectionStart = null
    ctx.selectionEnd = null
    ctx.focusedBlockIndex = -1
  }
  render(ctx)
}

function submitEditComment(id, body, formObj, ctx) {
  if (!body.trim()) return
  ctx.pushEvent("edit_comment", { id, body: body.trim() })
  removeForm(ctx, formObj.formKey)
  render(ctx)
}

// Returns true if the user confirms discarding (or the draft is empty).
// Returns false if the user cancels the confirm — caller should keep the form open.
function confirmDiscardIfDirty(formObj) {
  const ta = document.querySelector('textarea[data-form-key="' + formObj.formKey + '"]')
  if (!ta) return true
  if (!ta.value.trim()) return true
  return window.confirm("Discard comment?")
}

function cancelComment(formObj, ctx) {
  removeForm(ctx, formObj.formKey)
  if (ctx.activeForms.length === 0) {
    ctx.selectionStart = null
    ctx.selectionEnd = null
    ctx.focusedBlockIndex = -1
  }
  render(ctx)
}

// ===== Sidebar Resize =====
// File-tree and comments-panel widths are user-resizable via drag handles.
// Persisted in localStorage (crit-web is served from a stable origin, unlike
// the local CLI which uses a random port). Only a minimum is enforced —
// no upper bound; ultrawide users may legitimately want very wide sidebars.
const SIDEBAR_RESIZE = [
  { handleId: 'fileTreeResizer',     targetId: 'fileTreePanel',  storageKey: 'crit-file-tree-width',     min: 180, edge: 'right', step: 16 },
  { handleId: 'commentsPanelResizer', targetId: 'commentsPanel', storageKey: 'crit-comments-panel-width', min: 300, edge: 'left',  step: 16 },
]

function initSidebarWidths() {
  SIDEBAR_RESIZE.forEach(function(cfg) {
    const target = document.getElementById(cfg.targetId)
    if (!target) return
    const raw = localStorage.getItem(cfg.storageKey)
    const saved = raw == null ? NaN : parseInt(raw, 10)
    if (Number.isFinite(saved) && saved >= cfg.min) {
      target.style.width = saved + 'px'
    }
    const handle = document.getElementById(cfg.handleId)
    if (handle && !handle.dataset.resizeWired) {
      attachSidebarResizeHandle(handle, target, cfg)
      handle.dataset.resizeWired = '1'
    }
  })
}

function attachSidebarResizeHandle(handle, target, cfg) {
  // Pointer events + setPointerCapture: the handle keeps receiving move/up
  // events even if the pointer leaves the window, devtools opens, or the
  // user alt-tabs. Avoids the "stuck dragging" leak that document-level
  // mousemove listeners suffer from.
  handle.addEventListener('pointerdown', function(e) {
    if (e.button !== 0) return
    e.preventDefault()
    handle.setPointerCapture(e.pointerId)
    const startX = e.clientX
    const startWidth = target.getBoundingClientRect().width
    // For a left-edge handle (comments panel), dragging right shrinks the panel.
    const dir = cfg.edge === 'left' ? -1 : 1
    handle.classList.add('dragging')
    document.body.classList.add('sidebar-resizing')
    let lastWidth = startWidth

    function onMove(ev) {
      const delta = (ev.clientX - startX) * dir
      const w = Math.max(cfg.min, startWidth + delta)
      target.style.width = w + 'px'
      lastWidth = w
    }
    function onEnd() {
      handle.removeEventListener('pointermove', onMove)
      handle.removeEventListener('pointerup', onEnd)
      handle.removeEventListener('pointercancel', onEnd)
      handle.classList.remove('dragging')
      document.body.classList.remove('sidebar-resizing')
      try {
        localStorage.setItem(cfg.storageKey, String(Math.round(lastWidth)))
      } catch { /* storage unavailable; ignore */ }
    }
    handle.addEventListener('pointermove', onMove)
    handle.addEventListener('pointerup', onEnd)
    handle.addEventListener('pointercancel', onEnd)
  })

  // Keyboard resize for a11y: ArrowLeft / ArrowRight nudges by `step` px.
  // For left-edge handles the direction flips so ArrowRight always shrinks
  // the controlled panel — matching pointer drag semantics.
  handle.addEventListener('keydown', function(e) {
    if (e.key !== 'ArrowLeft' && e.key !== 'ArrowRight') return
    e.preventDefault()
    const dir = cfg.edge === 'left' ? -1 : 1
    const sign = e.key === 'ArrowRight' ? 1 : -1
    const current = target.getBoundingClientRect().width
    const w = Math.max(cfg.min, current + sign * dir * cfg.step)
    target.style.width = w + 'px'
    try {
      localStorage.setItem(cfg.storageKey, String(Math.round(w)))
    } catch { /* storage unavailable; ignore */ }
  })
}

function insertSuggestion(textarea, formObj, ctx) {
  let lines
  if (formObj.quote) {
    lines = formObj.quote.split('\n')
  } else {
    let rawContent = ctx.rawContent
    if (formObj.filePath && ctx.multiFile) {
      const file = ctx.files.find(f => f.path === formObj.filePath)
      if (file) rawContent = file.content
    }
    lines = rawContent.split("\n").slice(formObj.startLine - 1, formObj.endLine)
  }
  const suggestion = "```suggestion\n" + lines.join("\n") + "\n```"
  const start = textarea.selectionStart
  const end = textarea.selectionEnd
  textarea.value = textarea.value.substring(0, start) + suggestion + textarea.value.substring(end)
  const cursorPos = start + "```suggestion\n".length
  textarea.selectionStart = cursorPos
  textarea.selectionEnd = cursorPos + lines.join("\n").length
  textarea.focus()
}

// ---- Threading: replies & resolved ------------------------------------------

function renderReplyList(comment, ctx) {
  const repliesContainer = document.createElement('div')
  repliesContainer.className = 'comment-replies'
  comment.replies.forEach(function(reply) {
    const replyEl = document.createElement('div')
    replyEl.className = 'comment-reply'
    replyEl.dataset.replyId = reply.id

    const replyHeader = document.createElement('div')
    replyHeader.className = 'reply-header'

    const replyMeta = document.createElement('div')
    replyMeta.className = 'reply-meta'
    const isOwnReply = isOwnComment(reply, ctx)
    if (reply.author_display_name) {
      const replyAuthorBadge = document.createElement('span')
      replyAuthorBadge.className = 'comment-author-badge author-color-' + authorColorIndex(reply.author_display_name)
      replyAuthorBadge.textContent = '@' + reply.author_display_name
      replyMeta.appendChild(replyAuthorBadge)
    } else {
      const author = document.createElement('span')
      author.className = 'comment-author' + (isOwnReply ? ' comment-author-you' : '')
      author.innerHTML =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="comment-author-icon"><path fill-rule="evenodd" d="M18.685 19.097A9.723 9.723 0 0 0 21.75 12c0-5.385-4.365-9.75-9.75-9.75S2.25 6.615 2.25 12a9.723 9.723 0 0 0 3.065 7.097A9.716 9.716 0 0 0 12 21.75a9.716 9.716 0 0 0 6.685-2.653Zm-12.54-1.285A7.486 7.486 0 0 1 12 15a7.486 7.486 0 0 1 5.855 2.812A8.224 8.224 0 0 1 12 20.25a8.224 8.224 0 0 1-5.855-2.438ZM15.75 9a3.75 3.75 0 1 1-7.5 0 3.75 3.75 0 0 1 7.5 0Z" clip-rule="evenodd"/></svg>' +
        (isOwnReply ? (ctx.displayName || 'You') : (reply.author_identity || '?').slice(0, 20))
      replyMeta.appendChild(author)
    }
    const replyTime = document.createElement('span')
    replyTime.className = 'reply-time'
    replyTime.textContent = formatTime(reply.created_at)
    replyMeta.appendChild(replyTime)
    replyHeader.appendChild(replyMeta)

    if (isOwnReply) {
      const replyActions = document.createElement('div')
      replyActions.className = 'reply-actions'

      const replyEditBtn = document.createElement('button')
      replyEditBtn.title = 'Edit'
      replyEditBtn.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z"/><path d="m15 5 4 4"/></svg>'
      replyEditBtn.addEventListener('click', function(e) { e.stopPropagation(); editReply(comment.id, reply, ctx) })

      const replyDeleteBtn = document.createElement('button')
      replyDeleteBtn.className = 'delete-btn'
      replyDeleteBtn.title = 'Delete'
      replyDeleteBtn.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/></svg>'
      replyDeleteBtn.addEventListener('click', function(e) {
        e.stopPropagation()
        ctx.pushEvent("delete_reply", { id: reply.id })
      })

      replyActions.appendChild(replyEditBtn)
      replyActions.appendChild(replyDeleteBtn)
      replyHeader.appendChild(replyActions)
    }

    replyEl.appendChild(replyHeader)

    const replyBody = document.createElement('div')
    replyBody.className = 'reply-body'
    replyBody.dataset.rawBody = reply.body
    replyBody.innerHTML = commentMd.render(reply.body)
    replyEl.appendChild(replyBody)

    repliesContainer.appendChild(replyEl)
  })
  return repliesContainer
}

function createReplyInput(commentId, ctx) {
  const form = document.createElement('div')
  form.className = 'reply-form'

  const input = document.createElement('input')
  input.type = 'text'
  input.className = 'reply-input'
  input.placeholder = 'Write a reply\u2026'
  form.appendChild(input)

  // Expanded state elements (hidden initially)
  const textarea = document.createElement('textarea')
  textarea.className = 'reply-textarea'
  textarea.placeholder = 'Write a reply\u2026'
  textarea.rows = 3

  const buttons = document.createElement('div')
  buttons.className = 'reply-form-buttons'

  const cancelBtn = document.createElement('button')
  cancelBtn.className = 'btn btn-sm'
  cancelBtn.textContent = 'Cancel'

  const submitBtn = document.createElement('button')
  submitBtn.className = 'btn btn-sm btn-primary'
  submitBtn.textContent = 'Reply'

  buttons.appendChild(cancelBtn)
  buttons.appendChild(submitBtn)

  function expand() {
    if (form.classList.contains('expanded')) return
    closeEmptyReviewForm(ctx)
    closeEmptyForms(ctx, null)
    form.classList.add('expanded')
    textarea.value = input.value
    input.replaceWith(textarea)
    form.appendChild(buttons)
    textarea.focus()
  }

  function collapse() {
    if (!form.classList.contains('expanded')) return
    form.classList.remove('expanded')
    textarea.replaceWith(input)
    input.value = ''
    if (buttons.parentNode) buttons.remove()
  }

  input.addEventListener('focus', expand)
  cancelBtn.addEventListener('click', collapse)

  // Collapse on blur if empty (with delay to allow button clicks)
  textarea.addEventListener('blur', function() {
    trackedSetTimeout(ctx, function() {
      if (form.classList.contains('expanded') && !textarea.value.trim() && !form.contains(document.activeElement)) {
        collapse()
      }
    }, 150)
  })

  submitBtn.addEventListener('click', function() {
    const body = textarea.value.trim()
    if (!body) return
    submitBtn.disabled = true
    ctx.pushEvent("add_reply", { comment_id: commentId, body: body })
    collapse()
    submitBtn.disabled = false
  })

  textarea.addEventListener('keydown', function(e) {
    if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) {
      e.preventDefault()
      e.stopPropagation()
      submitBtn.click()
    }
    if (e.key === 'Escape') {
      e.preventDefault()
      e.stopPropagation()
      if (!textarea.value.trim()) {
        collapse()
      }
    }
  })

  return form
}

function editReply(commentId, reply, ctx) {
  const replyEl = document.querySelector('[data-reply-id="' + reply.id + '"]')
  if (!replyEl) return
  const bodyEl = replyEl.querySelector('.reply-body')
  if (!bodyEl) return
  const currentText = bodyEl.dataset.rawBody || bodyEl.textContent

  // Hide the "Write a reply..." form while editing
  const card = replyEl.closest('.comment-card')
  const replyForm = card && card.querySelector('.reply-form')
  if (replyForm) replyForm.style.display = 'none'

  const textarea = document.createElement('textarea')
  textarea.className = 'comment-textarea'
  textarea.value = currentText
  textarea.rows = 3
  bodyEl.replaceWith(textarea)
  textarea.focus()

  const saveBtn = document.createElement('button')
  saveBtn.className = 'btn btn-sm btn-primary'
  saveBtn.textContent = 'Save'
  const cancelBtn = document.createElement('button')
  cancelBtn.className = 'btn btn-sm'
  cancelBtn.textContent = 'Cancel'

  const btnRow = document.createElement('div')
  btnRow.className = 'reply-edit-actions'
  btnRow.appendChild(saveBtn)
  btnRow.appendChild(cancelBtn)
  replyEl.appendChild(btnRow)

  cancelBtn.addEventListener('click', () => {
    // Cancel button is an explicit, labeled discard — no confirm.
    render(ctx)
  })

  saveBtn.addEventListener('click', () => {
    const newBody = textarea.value.trim()
    if (!newBody) return
    ctx.pushEvent("edit_reply", { id: reply.id, body: newBody })
  })

  textarea.addEventListener('keydown', function(e) {
    if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) {
      e.preventDefault()
      e.stopPropagation()
      saveBtn.click()
    }
    if (e.key === 'Escape') {
      e.preventDefault()
      e.stopPropagation()
      const changed = textarea.value !== currentText
      if (changed && textarea.value.trim() && !window.confirm("Discard comment?")) return
      render(ctx)
    }
  })
}

function createResolvedElement(comment, ctx) {
  const wrapper = document.createElement('div')
  wrapper.className = 'comment-block'

  const card = document.createElement('div')
  // Apply saved collapse state (resolved defaults to collapsed)
  const isCollapsed = commentCollapseOverrides[comment.id] !== undefined ? commentCollapseOverrides[comment.id] : true
  card.className = 'comment-card resolved-card' + (isCollapsed ? ' collapsed' : '')
  card.dataset.commentId = comment.id

  const header = document.createElement('div')
  header.className = 'comment-header'

  const collapseBtn = document.createElement('button')
  collapseBtn.className = 'comment-collapse-btn'
  collapseBtn.title = isCollapsed ? 'Expand comment' : 'Collapse comment'
  collapseBtn.innerHTML = '<svg viewBox="0 0 16 16" fill="currentColor" width="16" height="16"><path d="M12.78 5.22a.75.75 0 0 1 0 1.06l-4.25 4.25a.75.75 0 0 1-1.06 0L3.22 6.28a.75.75 0 0 1 1.06-1.06L8 8.94l3.72-3.72a.75.75 0 0 1 1.06 0Z"/></svg>'
  collapseBtn.addEventListener('click', function(e) {
    e.stopPropagation()
    card.classList.toggle('collapsed')
    commentCollapseOverrides[comment.id] = card.classList.contains('collapsed')
    collapseBtn.title = card.classList.contains('collapsed') ? 'Expand comment' : 'Collapse comment'
  })

  const lineRef = document.createElement('span')
  lineRef.className = 'comment-line-ref'
  lineRef.textContent = comment.start_line === comment.end_line
    ? 'Line ' + comment.start_line
    : 'Lines ' + comment.start_line + '\u2013' + comment.end_line

  const time = document.createElement('span')
  time.className = 'comment-time'
  time.textContent = formatTime(comment.created_at)

  const headerLeft = document.createElement('div')
  headerLeft.className = 'comment-header-left'
  headerLeft.appendChild(collapseBtn)

  if (comment.author_display_name) {
    const authorBadge = document.createElement('span')
    authorBadge.className = 'comment-author-badge author-color-' + authorColorIndex(comment.author_display_name)
    authorBadge.textContent = '@' + comment.author_display_name
    headerLeft.appendChild(authorBadge)
  }
  if (comment.review_round >= 1) {
    const roundBadge = document.createElement('span')
    const rc = comment.review_round === ctx.reviewRound ? ' round-current' : comment.review_round === ctx.reviewRound - 1 ? ' round-latest' : ''
    roundBadge.className = 'comment-round-badge' + rc
    roundBadge.textContent = 'R' + comment.review_round
    headerLeft.appendChild(roundBadge)
  }
  headerLeft.appendChild(lineRef)
  headerLeft.appendChild(time)

  const actions = document.createElement('div')
  actions.className = 'comment-actions'

  const isOwn = isOwnComment(comment, ctx)
  const canResolve = isOwn || isReviewOwner(ctx)

  if (canResolve) {
    const unresolveBtn = document.createElement('button')
    unresolveBtn.className = 'resolve-btn resolve-btn--active'
    unresolveBtn.title = 'Unresolve'
    unresolveBtn.setAttribute('aria-label', 'Unresolve thread')
    unresolveBtn.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12a9 9 0 0 1 9-9 9 9 0 0 1 6.36 2.64M21 12a9 9 0 0 1-9 9 9 9 0 0 1-6.36-2.64"/><polyline points="21 3 21 8 16 8"/><polyline points="3 21 3 16 8 16"/></svg><span>Unresolve</span>'
    unresolveBtn.addEventListener('click', function() {
      ctx.pushEvent("resolve_comment", { id: comment.id, resolved: false })
    })
    actions.appendChild(unresolveBtn)
  }

  if (isOwn) {
    const deleteBtn = document.createElement('button')
    deleteBtn.className = 'delete-btn'
    deleteBtn.title = 'Delete'
    deleteBtn.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/></svg>'
    deleteBtn.addEventListener('click', function() {
      ctx.pushEvent("delete_comment", { id: comment.id })
    })
    actions.appendChild(deleteBtn)
  }

  header.appendChild(headerLeft)
  header.appendChild(actions)

  const body = document.createElement('div')
  body.className = 'comment-body'
  const env = {}
  if (ctx && comment.start_line && comment.end_line && !comment.side) {
    if (comment.quote) {
      env.originalLines = comment.quote.split('\n')
    } else {
      let fileContent = ctx.rawContent
      if (ctx.multiFile && comment.file_path) {
        const file = ctx.files && ctx.files.find(f => f.path === comment.file_path)
        if (file) fileContent = file.content
      }
      if (fileContent) {
        env.originalLines = fileContent.split('\n').slice(comment.start_line - 1, comment.end_line)
      }
    }
  }
  body.innerHTML = commentMd.render(comment.body, env)

  card.appendChild(header)
  card.appendChild(body)

  // Render replies
  if (comment.replies && comment.replies.length > 0) {
    card.appendChild(renderReplyList(comment, ctx))
  }

  // Reply input — gated on comment policy (a reply is a new comment).
  if (ctx.canComment !== false) {
    card.appendChild(createReplyInput(comment.id, ctx))
  }

  wrapper.appendChild(card)
  return wrapper
}

// ---- Table of Contents ------------------------------------------------------

function extractTocItems(md, rawContent) {
  const tokens = md.parse(rawContent, {})
  const items = []
  for (let i = 0; i < tokens.length; i++) {
    const t = tokens[i]
    if (t.type === "heading_open" && t.map) {
      const level = parseInt(t.tag.slice(1))
      const inline = tokens[i + 1]
      items.push({ level, text: inline ? inline.content : "", startLine: t.map[0] + 1 })
    }
  }
  return items
}

function buildToc(tocEl, toggleBtn, items) {
  const listEl = tocEl.querySelector(".crit-toc-list")
  listEl.innerHTML = ""

  // A single-heading TOC has nothing to navigate to — hide it.
  if (items.length < 2) {
    toggleBtn.style.display = "none"
    tocEl.classList.add("crit-toc-hidden")
    return
  }
  toggleBtn.style.display = ""

  const minLevel = Math.min(...items.map(i => i.level))
  for (const item of items) {
    const li = document.createElement("li")
    const a = document.createElement("a")
    a.href = "#"
    a.textContent = item.text
    a.dataset.startLine = item.startLine
    a.style.paddingLeft = (12 + (item.level - minLevel) * 10) + "px"
    a.addEventListener("click", (e) => {
      e.preventDefault()
      scrollToLine(item.startLine)
    })
    li.appendChild(a)
    listEl.appendChild(li)
  }
}

function scrollToLine(line) {
  const el = document.querySelector(`.line-block[data-start-line="${line}"]`)
  if (!el) return
  const headerEl = document.querySelector(".crit-header")
  const offset = headerEl ? headerEl.offsetHeight + 8 : 60
  window.scrollTo({ top: el.getBoundingClientRect().top + window.scrollY - offset, behavior: "smooth" })
}

function updateTocActive(tocItems) {
  if (tocItems.length === 0) return
  const headerEl = document.querySelector(".crit-header")
  const threshold = (headerEl ? headerEl.offsetHeight : 52) + 10

  let activeLine = null
  for (const item of tocItems) {
    const el = document.querySelector(`.line-block[data-start-line="${item.startLine}"]`)
    if (el && el.getBoundingClientRect().top <= threshold) activeLine = item.startLine
  }

  document.querySelectorAll(".crit-toc-list a").forEach(a => {
    a.classList.toggle("crit-toc-active", parseInt(a.dataset.startLine) === activeLine)
  })
}

// ---- File & Review comment helpers ------------------------------------------

function openFileCommentForm(ctx, filePath) {
  const fk = 'file:' + filePath
  if (ctx.activeForms.find(f => f.formKey === fk)) return
  closeEmptyForms(ctx, fk)
  closeEmptyReviewForm(ctx)
  const form = { formKey: fk, scope: 'file', filePath: filePath, startLine: null, endLine: null, editingId: null }
  ctx.activeForms.push(form)
  render(ctx)
  requestAnimationFrame(() => {
    const ta = ctx.el.querySelector('.file-comment-form textarea')
    if (ta) ta.focus()
  })
}

function openReviewCommentForm(ctx) {
  const fk = 'review:general'
  if (ctx.activeForms.find(f => f.formKey === fk)) return
  closeEmptyForms(ctx, fk)
  const form = { formKey: fk, scope: 'review', filePath: null, startLine: null, endLine: null, editingId: null }
  ctx.activeForms.push(form)
  renderReviewConversation(ctx)
  scrollToReviewConversation(ctx)
  requestAnimationFrame(() => {
    const section = document.getElementById('reviewConversation')
    const ta = section && section.querySelector('.comment-form textarea')
    if (ta) ta.focus()
  })
}

function openReviewCommentEditForm(ctx, comment) {
  // Close any other forms (matches crit/ behaviour)
  closeEmptyForms(ctx, null)
  const fk = 'review:edit:' + comment.id
  if (ctx.activeForms.find(f => f.formKey === fk)) return
  // Drop any existing review compose/edit form
  ctx.activeForms = ctx.activeForms.filter(f => f.scope !== 'review')
  const form = {
    formKey: fk,
    scope: 'review',
    filePath: null,
    startLine: null,
    endLine: null,
    editingId: comment.id,
    draftBody: comment.body,
  }
  ctx.activeForms.push(form)
  renderReviewConversation(ctx)
  scrollToReviewConversation(ctx)
  requestAnimationFrame(() => {
    const section = document.getElementById('reviewConversation')
    const ta = section && section.querySelector('.comment-form textarea')
    if (ta) ta.focus()
  })
}

// Auto-close an empty review compose form when the user starts another form.
// Mirrors crit/'s closeEmptyReviewForm.
function closeEmptyReviewForm(ctx) {
  const reviewForm = ctx.activeForms.find(f => f.scope === 'review' && !f.editingId)
  if (!reviewForm) return
  const section = document.getElementById('reviewConversation')
  const ta = section && section.querySelector('.comment-form textarea')
  if (ta && ta.value.trim()) return
  removeForm(ctx, reviewForm.formKey)
  renderReviewConversation(ctx)
}

function renderCommentFormUI(ctx, formObj) {
  const wrapper = document.createElement('div')
  wrapper.className = 'comment-form-wrapper'

  const form = document.createElement('div')
  form.className = 'comment-form'
  form.dataset.formKey = formObj.formKey

  const isEdit = !!formObj.editingId

  const textarea = document.createElement('textarea')
  textarea.dataset.formKey = formObj.formKey
  textarea.placeholder = formObj.scope === 'review'
    ? 'Leave a comment\u2026 (Ctrl+Enter to submit, Escape to cancel)'
    : 'Add a file comment\u2026 (Ctrl+Enter to submit, Escape to cancel)'
  textarea.value = formObj.draftBody || ''
  function submitForm() {
    if (isEdit) submitEditComment(formObj.editingId, textarea.value, formObj, ctx)
    else submitNewComment(textarea.value, formObj, ctx)
  }
  textarea.addEventListener('keydown', function(e) {
    e.stopPropagation()
    if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
      e.preventDefault()
      submitForm()
    }
    if (e.key === 'Escape') {
      e.preventDefault()
      if (confirmDiscardIfDirty(formObj)) cancelComment(formObj, ctx)
    }
  })
  form.appendChild(textarea)

  const actions = document.createElement('div')
  actions.className = 'comment-form-actions'
  const cancelBtn = document.createElement('button')
  cancelBtn.className = 'btn btn-sm'
  cancelBtn.textContent = 'Cancel'
  cancelBtn.addEventListener('click', () => cancelComment(formObj, ctx))
  const submitBtn = document.createElement('button')
  submitBtn.className = 'btn btn-sm btn-primary'
  submitBtn.textContent = isEdit ? 'Save' : 'Comment'
  submitBtn.addEventListener('click', submitForm)
  actions.appendChild(cancelBtn)
  actions.appendChild(submitBtn)
  form.appendChild(actions)

  wrapper.appendChild(form)
  return wrapper
}

// ---- Delta sync DOM helpers -------------------------------------------------

function insertInlineComment(ctx, comment) {
  if (comment.scope === 'review') return // review-scope comments are panel-only
  if (comment.scope === 'file') {
    // File-scope: append to .file-comments container
    if (ctx.multiFile && comment.file_path) {
      const section = document.getElementById('file-section-' + CSS.escape(comment.file_path))
      if (section) {
        let container = section.querySelector('.file-comments')
        if (!container) {
          container = document.createElement('div')
          container.className = 'file-comments'
          const header = section.querySelector('.file-header')
          if (header) header.after(container)
          else section.prepend(container)
        }
        const card = renderPanelCard(ctx, comment, comment.file_path)
        card.style.cursor = ''
        container.appendChild(card)
      }
    }
    return
  }
  // Line-scope: find the .line-block for end_line, append after it
  if (!comment.end_line) return
  const lineBlocks = ctx.el.querySelectorAll('.line-block')
  let targetBlock = null
  for (const lb of lineBlocks) {
    const start = parseInt(lb.dataset.startLine)
    const end = parseInt(lb.dataset.endLine)
    const fp = lb.dataset.filePath || null
    if (comment.end_line >= start && comment.end_line <= end &&
        (comment.file_path || null) === (fp || null)) {
      targetBlock = lb
      break
    }
  }
  if (!targetBlock) return

  // Mark lines as having comments
  for (const lb of lineBlocks) {
    const start = parseInt(lb.dataset.startLine)
    const end = parseInt(lb.dataset.endLine)
    const fp = lb.dataset.filePath || null
    if ((comment.file_path || null) === (fp || null) &&
        comment.start_line <= end && comment.end_line >= start) {
      lb.classList.add('has-comment')
    }
  }

  // Insert after any existing comment blocks following the target line block
  let insertAfter = targetBlock
  while (insertAfter.nextElementSibling &&
         (insertAfter.nextElementSibling.classList.contains('comment-block') ||
          insertAfter.nextElementSibling.classList.contains('comment-form-wrapper'))) {
    insertAfter = insertAfter.nextElementSibling
  }
  const newEl = createCommentElement(comment, ctx)
  insertAfter.after(newEl)
}

function removeInlineComment(ctx, comment) {
  // Remove inline DOM
  const card = ctx.el.querySelector(`.comment-card[data-comment-id="${comment.id}"]`)
  if (card) {
    const block = card.closest('.comment-block')
    if (block) {
      // Don't remove panel cards, only inline ones
      const panel = ctx._commentsPanel
      if (!panel || !panel.contains(block)) {
        block.remove()
      }
    }
  }
  // Update has-comment classes on line blocks
  if (comment.start_line && comment.end_line) {
    const commentedLineSet = buildCommentedLineSet(ctx.comments, ctx)
    const lineBlocks = ctx.el.querySelectorAll('.line-block')
    for (const lb of lineBlocks) {
      const start = parseInt(lb.dataset.startLine)
      const end = parseInt(lb.dataset.endLine)
      const fp = lb.dataset.filePath || null
      if ((comment.file_path || null) !== (fp || null)) continue
      let hasComment = false
      for (let ln = start; ln <= end; ln++) {
        if (commentedLineSet.has(ln)) { hasComment = true; break }
      }
      if (!hasComment) lb.classList.remove('has-comment')
    }
  }
}

function updateTreeBadge(ctx, filePath) {
  if (!ctx.multiFile || !filePath) return
  const treeFile = document.querySelector(`.tree-file[data-path="${CSS.escape(filePath)}"]`)
  if (!treeFile) return
  const f = ctx.files.find(fl => fl.path === filePath)
  if (!f) return
  const unresolvedCount = f.comments.filter(c => !c.resolved).length
  let badge = treeFile.querySelector('.tree-comment-badge')
  if (unresolvedCount > 0) {
    if (!badge) {
      badge = document.createElement('span')
      badge.className = 'tree-comment-badge'
      treeFile.appendChild(badge)
    }
    badge.textContent = unresolvedCount
  } else if (badge) {
    badge.remove()
  }
}

function rerenderPanel(ctx) {
  if (ctx._commentsPanel?.classList.contains('comments-panel-open')) {
    renderCommentsPanel(ctx)
  }
  // Keep the inline Review Conversation section + tree row in sync with any
  // comment change (additions, edits, resolves, replies). These are cheap.
  renderReviewConversation(ctx)
  const conversationSection = document.getElementById('treeConversationSection')
  if (conversationSection && ctx.multiFile) {
    conversationSection.innerHTML = ''
    conversationSection.appendChild(buildReviewConversationTreeRow(ctx))
  }
}

// ---- Comments panel helpers -------------------------------------------------

function renderCommentsPanel(ctx) {
  const panel = ctx._commentsPanel
  if (!panel) return
  const body = panel.querySelector('.comments-panel-body')
  const savedScroll = body.scrollTop
  body.innerHTML = ''

  const activeFilter = ctx._commentsActiveFilter || 'all'

  // Compute counts for badge and pill
  const totalCount = ctx.comments.length
  const openCount = ctx.comments.filter(c => !c.resolved).length
  const resolvedCount = ctx.comments.filter(c => c.resolved).length

  // Update count badge
  const badge = panel.querySelector('#commentsPanelCountBadge')
  if (badge) badge.textContent = totalCount

  // Update pill counts
  const pillBtns = panel.querySelectorAll('.crit-toggle-btn')
  pillBtns.forEach(btn => {
    const countEl = btn.querySelector('.filter-count')
    if (!countEl) return
    const f = btn.dataset.filter
    if (f === 'all') countEl.textContent = totalCount
    else if (f === 'open') countEl.textContent = openCount
    else if (f === 'resolved') countEl.textContent = resolvedCount
  })


  // Filter function based on active pill
  const visibleFilter = c => {
    if (activeFilter === 'open') return !c.resolved
    if (activeFilter === 'resolved') return c.resolved
    return true
  }

  // Review-level (general) comments are composed/edited from the inline
  // Review Conversation section at the top of the document; the panel only
  // mirrors them as read-only cards that link back to the inline section.

  // Separate and filter comments by scope
  const reviewComments = ctx.comments.filter(c => c.scope === 'review').filter(visibleFilter)
  const fileAndLineComments = ctx.comments.filter(c => c.scope !== 'review').filter(visibleFilter)

  if (ctx.comments.length === 0) {
    body.innerHTML += '<div class="comments-panel-empty">No comments yet</div>'
    updateExpandAllLabel(ctx)
    return
  }

  const filteredTotal = reviewComments.length + fileAndLineComments.length
  if (filteredTotal === 0) {
    const emptyMsg = activeFilter === 'open' ? 'No open comments' : activeFilter === 'resolved' ? 'No resolved comments' : 'No comments yet'
    body.innerHTML += '<div class="comments-panel-empty">' + emptyMsg + '</div>'
    updateExpandAllLabel(ctx)
    return
  }

  // Review comments first
  if (reviewComments.length > 0) {
    const group = document.createElement('div')
    group.className = 'comments-panel-file-group'

    const groupName = createFileGroupHeader('Review conversation', reviewComments.length, group)
    group.appendChild(groupName)

    const cards = document.createElement('div')
    cards.className = 'comments-panel-file-cards'
    for (const c of reviewComments) {
      cards.appendChild(renderPanelCard(ctx, c, null))
    }
    group.appendChild(cards)
    body.appendChild(group)
  }

  // File and line comments
  if (fileAndLineComments.length > 0) {
    const sorted = [...fileAndLineComments].sort((a, b) => (a.start_line || 0) - (b.start_line || 0))

    if (ctx.multiFile) {
      const grouped = {}
      for (const c of sorted) {
        const fp = c.file_path || ''
        if (!grouped[fp]) grouped[fp] = []
        grouped[fp].push(c)
      }

      for (const file of ctx.files) {
        const fileComments = grouped[file.path]
        if (!fileComments || fileComments.length === 0) continue

        const group = document.createElement('div')
        group.className = 'comments-panel-file-group'

        const groupName = createFileGroupHeader(file.path, fileComments.length, group)
        group.appendChild(groupName)

        const cards = document.createElement('div')
        cards.className = 'comments-panel-file-cards'
        for (const c of fileComments) {
          cards.appendChild(renderPanelCard(ctx, c, file.path))
        }
        group.appendChild(cards)
        body.appendChild(group)
      }
    } else {
      const group = document.createElement('div')
      group.className = 'comments-panel-file-group'
      const cards = document.createElement('div')
      cards.className = 'comments-panel-file-cards'
      for (const c of sorted) {
        cards.appendChild(renderPanelCard(ctx, c, null))
      }
      group.appendChild(cards)
      body.appendChild(group)
    }
  }

  body.scrollTop = savedScroll
  updateExpandAllLabel(ctx)
}

function createFileGroupHeader(label, count, groupEl) {
  const groupName = document.createElement('div')
  groupName.className = 'comments-panel-file-name'

  const chevron = document.createElement('span')
  chevron.className = 'comments-panel-file-chevron'
  chevron.textContent = '\u25BC'
  groupName.appendChild(chevron)

  const nameText = document.createElement('span')
  nameText.className = 'comments-panel-file-name-text'
  nameText.textContent = label
  nameText.title = label
  groupName.appendChild(nameText)

  const countEl = document.createElement('span')
  countEl.className = 'comments-panel-file-count'
  countEl.textContent = count
  groupName.appendChild(countEl)

  groupName.setAttribute('role', 'button')
  groupName.setAttribute('tabindex', '0')
  groupName.setAttribute('aria-expanded', 'true')

  const toggleGroup = () => {
    groupEl.classList.toggle('collapsed')
    const expanded = !groupEl.classList.contains('collapsed')
    groupName.setAttribute('aria-expanded', String(expanded))
  }

  groupName.addEventListener('click', toggleGroup)
  groupName.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault()
      toggleGroup()
    }
  })

  return groupName
}



function updateExpandAllLabel(ctx) {
  const panel = ctx._commentsPanel
  if (!panel) return
  const btn = panel.querySelector('#commentsPanelExpandAll')
  if (!btn) return
  // Check if any visible card is expanded (not collapsed)
  const panelCards = panel.querySelectorAll('.comment-card')
  const inlineCards = document.querySelectorAll('.comment-block:not(.panel-comment-block) .comment-card')
  const allCards = [...panelCards, ...inlineCards]
  const anyExpanded = allCards.some(c => !c.classList.contains('collapsed'))
  btn.textContent = anyExpanded ? 'Collapse all' : 'Expand all'
}

function toggleExpandAllComments(ctx) {
  const panel = ctx._commentsPanel
  if (!panel) return
  const panelCards = panel.querySelectorAll('.comment-card')
  const inlineCards = document.querySelectorAll('.comment-block:not(.panel-comment-block) .comment-card')
  const allCards = [...panelCards, ...inlineCards]
  const anyExpanded = allCards.some(c => !c.classList.contains('collapsed'))

  allCards.forEach(card => {
    if (anyExpanded) {
      card.classList.add('collapsed')
    } else {
      card.classList.remove('collapsed')
    }
    // Sync override state
    const id = card.dataset.commentId
    if (id) commentCollapseOverrides[id] = anyExpanded
  })

  updateExpandAllLabel(ctx)
}

function renderPanelCard(ctx, comment, filePath) {
  const isGeneral = comment.scope === 'review'
  const isResolved = comment.resolved

  const wrapper = document.createElement('div')
  wrapper.className = 'comment-block panel-comment-block'

  const card = document.createElement('div')
  card.className = 'comment-card' + (isResolved ? ' resolved-card' : '')
  card.dataset.commentId = comment.id

  // Collapse state
  const isCollapsed = isResolved
    ? (commentCollapseOverrides[comment.id] !== undefined ? commentCollapseOverrides[comment.id] : true)
    : (commentCollapseOverrides[comment.id] === true)
  if (isCollapsed) card.classList.add('collapsed')

  // Header
  const header = document.createElement('div')
  header.className = 'comment-header'

  const headerLeft = document.createElement('div')
  headerLeft.className = 'comment-header-left'

  const collapseBtn = document.createElement('button')
  collapseBtn.className = 'comment-collapse-btn'
  collapseBtn.title = isCollapsed ? 'Expand comment' : 'Collapse comment'
  collapseBtn.innerHTML = '<svg viewBox="0 0 16 16" fill="currentColor" width="16" height="16"><path d="M12.78 5.22a.75.75 0 0 1 0 1.06l-4.25 4.25a.75.75 0 0 1-1.06 0L3.22 6.28a.75.75 0 0 1 1.06-1.06L8 8.94l3.72-3.72a.75.75 0 0 1 1.06 0Z"/></svg>'
  collapseBtn.addEventListener('click', function(e) {
    e.stopPropagation()
    card.classList.toggle('collapsed')
    commentCollapseOverrides[comment.id] = card.classList.contains('collapsed')
    collapseBtn.title = card.classList.contains('collapsed') ? 'Expand comment' : 'Collapse comment'
  })
  headerLeft.appendChild(collapseBtn)

  // Author
  const isOwn = isOwnComment(comment, ctx)
  const canResolve = isOwn || isReviewOwner(ctx)
  if (comment.author_display_name) {
    const authorBadge = document.createElement('span')
    authorBadge.className = 'comment-author-badge author-color-' + authorColorIndex(comment.author_display_name)
    authorBadge.textContent = '@' + comment.author_display_name
    headerLeft.appendChild(authorBadge)
  } else {
    const author = document.createElement('span')
    author.className = 'comment-author' + (isOwn ? ' comment-author-you' : '')
    author.innerHTML =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="comment-author-icon"><path fill-rule="evenodd" d="M18.685 19.097A9.723 9.723 0 0 0 21.75 12c0-5.385-4.365-9.75-9.75-9.75S2.25 6.615 2.25 12a9.723 9.723 0 0 0 3.065 7.097A9.716 9.716 0 0 0 12 21.75a9.716 9.716 0 0 0 6.685-2.653Zm-12.54-1.285A7.486 7.486 0 0 1 12 15a7.486 7.486 0 0 1 5.855 2.812A8.224 8.224 0 0 1 12 20.25a8.224 8.224 0 0 1-5.855-2.438ZM15.75 9a3.75 3.75 0 1 1-7.5 0 3.75 3.75 0 0 1 7.5 0Z" clip-rule="evenodd"/></svg>' +
      (isOwn ? (ctx.displayName || 'You') : 'anonymous')
    headerLeft.appendChild(author)
  }

  // Round badge
  if (comment.review_round >= 1) {
    const rc = comment.review_round === ctx.reviewRound ? ' round-current' : comment.review_round === ctx.reviewRound - 1 ? ' round-latest' : ''
    const roundBadge = document.createElement('span')
    roundBadge.className = 'comment-round-badge' + rc
    roundBadge.textContent = 'R' + comment.review_round
    headerLeft.appendChild(roundBadge)
  }

  // Line reference / scope label (no label for file-scope or review-scope)
  if (!isGeneral && comment.scope !== 'file' && comment.start_line) {
    const ref = document.createElement('span')
    ref.className = 'comment-line-ref'
    ref.textContent = comment.start_line === comment.end_line
      ? 'L' + comment.start_line
      : 'L' + comment.start_line + '\u2013' + comment.end_line
    headerLeft.appendChild(ref)
  }

  // Time (inside headerLeft, as last child — matches crit local)
  const time = document.createElement('span')
  time.className = 'comment-time'
  time.textContent = formatTime(comment.created_at)
  headerLeft.appendChild(time)

  header.appendChild(headerLeft)

  // Actions appended to header (sibling to headerLeft — matches crit local)
  if (isGeneral && (canResolve || isOwn)) {
    const actions = document.createElement('div')
    actions.className = 'comment-actions'

    if (canResolve) {
      const resolveBtn = document.createElement('button')
      resolveBtn.className = isResolved ? 'resolve-btn resolve-btn--active' : 'resolve-btn'
      resolveBtn.title = isResolved ? 'Unresolve' : 'Resolve'
      resolveBtn.innerHTML = isResolved
        ? '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12a9 9 0 0 1 9-9 9 9 0 0 1 6.36 2.64M21 12a9 9 0 0 1-9 9 9 9 0 0 1-6.36-2.64"/><polyline points="21 3 21 8 16 8"/><polyline points="3 21 3 16 8 16"/></svg><span>Unresolve</span>'
        : '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg><span>Resolve</span>'
      resolveBtn.addEventListener('click', function(e) {
        e.stopPropagation()
        ctx.pushEvent('resolve_comment', { id: comment.id, resolved: !isResolved })
      })
      actions.appendChild(resolveBtn)
    }

    if (isOwn) {
      const deleteBtn = document.createElement('button')
      deleteBtn.className = 'delete-btn'
      deleteBtn.title = 'Delete'
      deleteBtn.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/></svg>'
      deleteBtn.addEventListener('click', function(e) {
        e.stopPropagation()
        ctx.pushEvent('delete_comment', { id: comment.id })
      })
      actions.appendChild(deleteBtn)
    }

    header.appendChild(actions)
  }

  card.appendChild(header)

  // Body
  const bodyEl = document.createElement('div')
  bodyEl.className = 'comment-body'
  const env = {}
  if (comment.start_line && comment.end_line) {
    if (comment.quote) {
      env.originalLines = comment.quote.split('\n')
    } else {
      let fileContent = ctx.rawContent
      if (ctx.multiFile && filePath) {
        const file = ctx.files.find(f => f.path === filePath)
        if (file) fileContent = file.content
      }
      if (fileContent) {
        env.originalLines = fileContent.split('\n').slice(comment.start_line - 1, comment.end_line)
      }
    }
  }
  bodyEl.innerHTML = commentMd.render(comment.body, env)
  card.appendChild(bodyEl)

  // Replies (read-only in panel)
  if (comment.replies && comment.replies.length > 0) {
    card.appendChild(renderReplyList(comment, ctx))
  }

  wrapper.appendChild(card)

  // Click-to-scroll
  if (isGeneral) {
    // Panel cards for review comments link back to the inline Review
    // Conversation section, mirroring crit/'s behaviour.
    wrapper.style.cursor = 'pointer'
    wrapper.addEventListener('click', function(e) {
      if (e.target.closest('button')) return
      scrollToReviewComment(ctx, comment.id)
    })
  } else {
    wrapper.style.cursor = 'pointer'
    wrapper.addEventListener('click', function(e) {
      if (e.target.closest('button')) return
      if (filePath) {
        const section = document.getElementById('file-section-' + CSS.escape(filePath))
        if (section && !section.open) section.open = true
      }
      if (comment.start_line) {
        scrollToInlineComment(comment, ctx)
      }
    })
  }

  return wrapper
}

function scrollToInlineComment(comment, ctx) {
  const card = ctx.el.querySelector(`.comment-card[data-comment-id="${comment.id}"]`)
  if (!card) return
  const header = document.querySelector('.crit-header')
  const offset = header ? header.offsetHeight + 16 : 68
  window.scrollTo({
    top: card.getBoundingClientRect().top + window.scrollY - offset,
    behavior: 'smooth'
  })
  card.classList.add('comment-flash')
  card.addEventListener('animationend', () => card.classList.remove('comment-flash'), { once: true })
}

// ===== Inline Review Conversation Section (top of document) =====

const REVIEW_CONVERSATION_PATH = '__review_conversation__'
const ICON_REVIEW_CONVERSATION =
  '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.25" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
  '<path d="M2 3.5A1.5 1.5 0 0 1 3.5 2h9A1.5 1.5 0 0 1 14 3.5v6A1.5 1.5 0 0 1 12.5 11H8.5l-3 2.75V11H3.5A1.5 1.5 0 0 1 2 9.5Z"/>' +
  '</svg>'
const ICON_REVIEW_CHEVRON =
  '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true">' +
  '<path d="M4 6l4 4 4-4" stroke-linecap="round" stroke-linejoin="round"/></svg>'

function isReviewConversationCollapsed() {
  return localStorage.getItem('crit-review-conversation-collapsed') === '1'
}

function setReviewConversationCollapsed(collapsed) {
  localStorage.setItem('crit-review-conversation-collapsed', collapsed ? '1' : '0')
}

function renderReviewConversation(ctx) {
  const section = document.getElementById('reviewConversation')
  if (!section) return

  if (!ctx || !Array.isArray(ctx.comments)) {
    section.hidden = true
    return
  }

  section.hidden = false
  section.innerHTML = ''

  // crit-web is always doc-centered (no git-mode side-by-side diff view).
  section.dataset.docLayout = 'centered'

  const reviewForm = ctx.activeForms.find(f => f.scope === 'review')
  const reviewComments = ctx.comments.filter(c => c.scope === 'review')

  // When commenting is disallowed AND there are no existing review-level
  // comments, the section has nothing to read and no affordance to offer —
  // hide it entirely instead of rendering an empty header. If a comment
  // exists, keep the section visible (users can still read/resolve threads;
  // the "Add comment" button stays gated by canComment below).
  if (ctx.canComment === false && reviewComments.length === 0 && !reviewForm) {
    section.hidden = true
    return
  }

  const collapsed = isReviewConversationCollapsed() && !reviewForm
  section.classList.toggle('collapsed', collapsed)

  // Header
  const header = document.createElement('div')
  header.className = 'review-conversation-header'

  const toggle = document.createElement('button')
  toggle.type = 'button'
  toggle.className = 'review-conversation-toggle'
  toggle.title = collapsed ? 'Expand review conversation' : 'Collapse review conversation'
  toggle.setAttribute('aria-expanded', collapsed ? 'false' : 'true')
  toggle.setAttribute('aria-label', toggle.title)
  toggle.innerHTML = ICON_REVIEW_CHEVRON
  toggle.addEventListener('click', function() {
    setReviewConversationCollapsed(!isReviewConversationCollapsed())
    renderReviewConversation(ctx)
  })
  header.appendChild(toggle)

  const iconSpan = document.createElement('span')
  iconSpan.className = 'icon'
  iconSpan.innerHTML = ICON_REVIEW_CONVERSATION
  header.appendChild(iconSpan)

  const labelText = document.createElement('span')
  labelText.className = 'label'
  labelText.textContent = 'Review conversation'
  header.appendChild(labelText)

  const unresolvedCount = reviewComments.filter(c => !c.resolved).length
  if (unresolvedCount > 0) {
    const count = document.createElement('span')
    count.className = 'count'
    count.textContent = String(unresolvedCount)
    header.appendChild(count)
  }
  section.appendChild(header)

  if (collapsed) return

  const body = document.createElement('div')
  body.className = 'review-conversation-body'
  section.appendChild(body)

  // Threads (existing comments). The editor renders inline at the matching
  // position when the user is editing one.
  for (const comment of reviewComments) {
    if (reviewForm && reviewForm.editingId === comment.id) {
      body.appendChild(renderCommentFormUI(ctx, reviewForm))
    } else {
      body.appendChild(createReviewConversationCard(ctx, comment))
    }
  }

  // Footer: compose form (when active) or ghost "Add comment" button.
  // Gate on canComment so the affordance physically isn't created when the
  // policy disallows new comments — the click handler triggers a re-render
  // that visibly removes the button (jankiness). CSS .crit-no-comments
  // hiding is defense in depth; skipping creation is the source of truth.
  if (reviewForm && !reviewForm.editingId) {
    body.appendChild(renderCommentFormUI(ctx, reviewForm))
  } else if (ctx.canComment !== false) {
    const addMore = document.createElement('button')
    addMore.className = 'review-conversation-add-more'
    if (reviewComments.length === 0) addMore.classList.add('review-conversation-empty')
    addMore.type = 'button'
    addMore.textContent = 'Add comment'
    addMore.addEventListener('click', function() { openReviewCommentForm(ctx) })
    body.appendChild(addMore)
  }
}

// A review-level card shown inline. Reuses renderPanelCard's structure (which
// already builds resolve/edit/delete actions for own review comments) but
// rewires the edit button to open the inline editor instead of a panel form.
function createReviewConversationCard(ctx, comment) {
  const wrapper = renderPanelCard(ctx, comment, null)
  // Drop the panel-comment-block class so width rules don't fight the inline section.
  wrapper.classList.remove('panel-comment-block')
  // The actual card lives inside the wrapper; we need it to append replies + reply input.
  const card = wrapper.querySelector('.comment-card') || wrapper
  card.style.cursor = ''
  // Append Edit button for owners (panel-card builds resolve+delete only for review scope).
  if (isOwnComment(comment, ctx)) {
    const actions = card.querySelector('.comment-actions')
    if (actions && !actions.querySelector('.edit-btn')) {
      const editBtn = document.createElement('button')
      editBtn.className = 'edit-btn'
      editBtn.title = 'Edit'
      editBtn.innerHTML = '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M11.5 2.5l2 2L5 13H3v-2L11.5 2.5z" stroke-linejoin="round"/></svg>'
      editBtn.addEventListener('click', function(e) {
        e.stopPropagation()
        openReviewCommentEditForm(ctx, comment)
      })
      actions.appendChild(editBtn)
    }
  }
  // Render existing replies + a reply input — review-level threads support replies
  // exactly like line-anchored ones (parity with crit local).
  // Reply input gated on comment policy (a reply is a new comment).
  if (comment.replies && comment.replies.length > 0) {
    card.appendChild(renderReplyList(comment, ctx))
  }
  if (ctx.canComment !== false) {
    card.appendChild(createReplyInput(comment.id, ctx))
  }
  return wrapper
}

function buildReviewConversationTreeRow(ctx) {
  const row = document.createElement('div')
  row.className = 'tree-conversation-row'
  row.dataset.treePath = REVIEW_CONVERSATION_PATH
  let inner =
    '<span class="tree-conversation-icon">' + ICON_REVIEW_CONVERSATION + '</span>' +
    '<span class="tree-conversation-name">Review conversation</span>'
  const reviewComments = ctx.comments.filter(c => c.scope === 'review')
  const unresolved = reviewComments.filter(c => !c.resolved).length
  if (unresolved > 0) {
    inner += '<span class="tree-conversation-badge">' + unresolved + '</span>'
  }
  row.innerHTML = inner
  row.addEventListener('click', function() { scrollToReviewConversation(ctx) })
  return row
}

function scrollToReviewConversation(ctx) {
  if (isReviewConversationCollapsed()) {
    setReviewConversationCollapsed(false)
    renderReviewConversation(ctx)
  }
  const section = document.getElementById('reviewConversation')
  if (!section) return
  const rect = section.getBoundingClientRect()
  const headerEl = document.querySelector('.crit-header')
  const headerOffset = headerEl ? headerEl.offsetHeight : 0
  if (rect.top < headerOffset || rect.top > window.innerHeight) {
    section.scrollIntoView({ block: 'start', behavior: 'instant' })
  }
}

function scrollToReviewComment(ctx, commentId) {
  if (isReviewConversationCollapsed()) {
    setReviewConversationCollapsed(false)
    renderReviewConversation(ctx)
  }
  const section = document.getElementById('reviewConversation')
  if (!section) return
  const card = section.querySelector(`.comment-card[data-comment-id="${CSS.escape(commentId)}"]`)
  if (!card) {
    scrollToReviewConversation(ctx)
    return
  }
  card.scrollIntoView({ behavior: 'smooth', block: 'center' })
  card.classList.remove('comment-flash')
  void card.offsetWidth
  card.classList.add('comment-flash')
  card.addEventListener('animationend', () => card.classList.remove('comment-flash'), { once: true })
}

function updateTocPosition(ctx) {
  const toc = document.getElementById('crit-toc')
  const panel = ctx._commentsPanel
  if (!toc || !panel) return
  const panelOpen = panel.classList.contains('comments-panel-open')
  toc.style.right = panelOpen ? (panel.offsetWidth + 16) + 'px' : ''
}

function syncCommentsPanelAria(isOpen) {
  const btn = document.getElementById('comment-count')
  if (btn) btn.setAttribute('aria-expanded', String(isOpen))
}

function toggleCommentsPanel(ctx) {
  const panel = ctx._commentsPanel
  if (!panel) return
  const isOpen = panel.classList.contains('comments-panel-open')
  if (isOpen) {
    panel.classList.remove('comments-panel-open')
  } else {
    renderCommentsPanel(ctx)
    panel.classList.add('comments-panel-open')
  }
  syncCommentsPanelAria(!isOpen)
  updateTocPosition(ctx)
}

// ---- Comment navigation -----------------------------------------------------

function getInlineCommentCards(ctx) {
  const panel = ctx._commentsPanel
  // Search the whole main-content area so review-conversation cards (which
  // live as siblings to ctx.el) are included in ] / [ navigation.
  const root = document.querySelector('.crit-main-content') || ctx.el
  return Array.from(root.querySelectorAll('.comment-card')).filter(card => {
    return !panel || !panel.contains(card)
  })
}

function navigateToComment(ctx, direction) {
  const cards = getInlineCommentCards(ctx)
  if (cards.length === 0) return

  const header = document.querySelector('.crit-header')
  const headerHeight = header ? header.offsetHeight : 52

  // Find current position by stored comment ID (immune to smooth-scroll race conditions)
  let idx = ctx._navCommentId
    ? cards.findIndex(c => c.dataset.commentId === ctx._navCommentId)
    : -1

  let targetIdx
  if (direction === 1) {
    if (idx < 0) {
      // First use: pick first card below the header area by viewport position
      const firstBelow = cards.findIndex(c => c.getBoundingClientRect().top > headerHeight + 8)
      targetIdx = firstBelow >= 0 ? firstBelow : 0
    } else {
      targetIdx = idx >= cards.length - 1 ? 0 : idx + 1
    }
  } else {
    if (idx < 0) {
      targetIdx = cards.length - 1
    } else {
      targetIdx = idx <= 0 ? cards.length - 1 : idx - 1
    }
  }

  const target = cards[targetIdx]
  ctx._navCommentId = target.dataset.commentId

  const rect = target.getBoundingClientRect()
  const fileSection = target.closest('.file-section')
  const fileHeader = fileSection ? fileSection.querySelector('.file-header') : null
  const fileHeaderHeight = fileHeader ? fileHeader.offsetHeight : 0
  window.scrollTo({ top: rect.top + window.scrollY - headerHeight - fileHeaderHeight - 16, behavior: 'smooth' })
  target.classList.add('comment-nav-highlight')
  trackedSetTimeout(ctx, () => target.classList.remove('comment-nav-highlight'), 1000)
}

// ---- Content Width ----------------------------------------------------------

function initWidth() {
  const saved = localStorage.getItem('crit-width') || 'default'
  applyWidth(saved)
}

function applyWidth(choice) {
  localStorage.setItem('crit-width', choice)
  if (choice === 'compact') document.documentElement.setAttribute('data-width', 'compact')
  else if (choice === 'wide') document.documentElement.setAttribute('data-width', 'wide')
  else document.documentElement.setAttribute('data-width', 'default')
}

// ---- Settings Panel ---------------------------------------------------------

let settingsPanelOpen = false
let settingsPanelTab = 'settings'

function openSettingsPanel(tab) {
  settingsPanelTab = tab || 'settings'
  settingsPanelOpen = true
  const overlay = document.getElementById('settingsOverlay')
  if (!overlay) return
  overlay.classList.add('active')
  // Ensure the sliding underline element exists
  if (!overlay.querySelector('.settings-tab-underline')) {
    const underline = document.createElement('div')
    underline.className = 'settings-tab-underline'
    overlay.querySelector('.settings-tabs').appendChild(underline)
  }
  switchSettingsTab(settingsPanelTab)
  renderShortcutsPane()
}

function closeSettingsPanel() {
  settingsPanelOpen = false
  const overlay = document.getElementById('settingsOverlay')
  if (overlay) overlay.classList.remove('active')
}

function switchSettingsTab(tab) {
  settingsPanelTab = tab
  let activeBtn = null
  document.querySelectorAll('.settings-tab[data-tab]').forEach(function(t) {
    const isActive = t.dataset.tab === tab
    t.classList.toggle('active', isActive)
    if (isActive) activeBtn = t
  })
  document.querySelectorAll('.settings-pane').forEach(function(p) {
    p.classList.toggle('active', p.dataset.pane === tab)
  })
  // Position the sliding underline
  const underline = document.querySelector('.settings-tab-underline')
  if (underline && activeBtn) {
    const tabsRect = activeBtn.parentElement.getBoundingClientRect()
    const btnRect = activeBtn.getBoundingClientRect()
    underline.style.left = (btnRect.left - tabsRect.left) + 'px'
    underline.style.width = btnRect.width + 'px'
  }
  // Render the active pane content
  if (tab === 'settings') renderSettingsPane()
  else if (tab === 'about') renderAboutPane()
}

function applyHideResolved(ctx) {
  const hide = ctx ? isHideResolved(ctx) : readHideResolved()
  document.querySelectorAll('.comment-block:not(.panel-comment-block)').forEach(function(block) {
    const card = block.querySelector('.resolved-card')
    if (card) {
      block.style.display = hide ? 'none' : ''
    }
  })
}

function updatePillIndicator(indicatorId, values, current) {
  const indicator = document.getElementById(indicatorId)
  if (!indicator) return
  const idx = values.indexOf(current)
  if (idx >= 0) {
    indicator.style.left = (idx * (100 / values.length)) + '%'
    indicator.style.width = (100 / values.length) + '%'
  }
}

function renderSettingsPane() {
  const pane = document.getElementById('settingsPane')
  if (!pane) return

  const currentTheme = localStorage.getItem('phx:theme') || 'system'
  const currentWidth = localStorage.getItem('crit-width') || 'default'
  const hideResolved = isHideResolved(__activeCtx)

  let html = ''

  // Display section
  html += '<div class="settings-section-label">Display</div>'
  html += '<div class="settings-display-group">'

  // Theme row
  html += '<div class="settings-display-row">'
  html += '<span class="settings-display-label">Theme</span>'
  html += '<div class="settings-pill settings-pill--theme" id="settingsThemePill" role="group" aria-label="Theme">'
  html += '<div class="settings-pill-indicator" id="settingsThemeIndicator"></div>'
  const themeIcons = {
    system: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="currentColor"><path fill-rule="evenodd" d="M2 4.25A2.25 2.25 0 0 1 4.25 2h7.5A2.25 2.25 0 0 1 14 4.25v5.5A2.25 2.25 0 0 1 11.75 12h-1.312c.1.128.21.248.328.36a.75.75 0 0 1 .234.545v.345a.75.75 0 0 1-.75.75h-4.5a.75.75 0 0 1-.75-.75v-.345a.75.75 0 0 1 .234-.545c.118-.111.228-.232.328-.36H4.25A2.25 2.25 0 0 1 2 9.75v-5.5Zm2.25-.75a.75.75 0 0 0-.75.75v4.5c0 .414.336.75.75.75h7.5a.75.75 0 0 0 .75-.75v-4.5a.75.75 0 0 0-.75-.75h-7.5Z" clip-rule="evenodd"/></svg>',
    light: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="currentColor"><path d="M8 1a.75.75 0 0 1 .75.75v1.5a.75.75 0 0 1-1.5 0v-1.5A.75.75 0 0 1 8 1ZM10.5 8a2.5 2.5 0 1 1-5 0 2.5 2.5 0 0 1 5 0ZM12.95 4.11a.75.75 0 1 0-1.06-1.06l-1.062 1.06a.75.75 0 0 0 1.061 1.062l1.06-1.061ZM15 8a.75.75 0 0 1-.75.75h-1.5a.75.75 0 0 1 0-1.5h1.5A.75.75 0 0 1 15 8ZM11.89 12.95a.75.75 0 0 0 1.06-1.06l-1.06-1.062a.75.75 0 0 0-1.062 1.061l1.061 1.06ZM8 12a.75.75 0 0 1 .75.75v1.5a.75.75 0 0 1-1.5 0v-1.5A.75.75 0 0 1 8 12ZM5.172 11.89a.75.75 0 0 0-1.061-1.062L3.05 11.89a.75.75 0 1 0 1.06 1.06l1.06-1.06ZM4 8a.75.75 0 0 1-.75.75h-1.5a.75.75 0 0 1 0-1.5h1.5A.75.75 0 0 1 4 8ZM4.11 5.172A.75.75 0 0 0 5.173 4.11L4.11 3.05a.75.75 0 1 0-1.06 1.06l1.06 1.06Z"/></svg>',
    dark: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="currentColor"><path d="M14.438 10.148c.19-.425-.321-.787-.748-.601A5.5 5.5 0 0 1 6.453 2.31c.186-.427-.176-.938-.6-.748a6.501 6.501 0 1 0 8.585 8.586Z"/></svg>'
  }
  ;['system', 'light', 'dark'].forEach(function(theme) {
    const active = theme === currentTheme ? ' active' : ''
    html += '<button class="settings-pill-btn' + active + '" data-settings-theme="' + theme + '" title="' + theme.charAt(0).toUpperCase() + theme.slice(1) + ' theme">' + themeIcons[theme] + '</button>'
  })
  html += '</div></div>'

  // Width row
  html += '<div class="settings-display-row">'
  html += '<span class="settings-display-label">Content Width</span>'
  html += '<div class="settings-pill settings-pill--width" id="settingsWidthPill" role="group" aria-label="Content width">'
  html += '<div class="settings-pill-indicator" id="settingsWidthIndicator"></div>'
  ;['compact', 'default', 'wide'].forEach(function(w) {
    const active = w === currentWidth ? ' active' : ''
    html += '<button class="settings-pill-btn' + active + '" data-settings-width="' + w + '">' + w.charAt(0).toUpperCase() + w.slice(1) + '</button>'
  })
  html += '</div></div>'

  // Hide resolved row
  html += '<div class="settings-display-row">'
  html += '<span class="settings-display-label">Hide resolved comments</span>'
  html += '<label class="comments-panel-switch">'
  html += '<input type="checkbox" id="hideResolvedToggle" aria-label="Hide resolved comments"' + (hideResolved ? ' checked' : '') + '>'
  html += '<span class="comments-panel-switch-track"><span class="comments-panel-switch-thumb"></span></span>'
  html += '</label>'
  html += '</div>'

  html += '</div>' // close settings-display-group

  pane.innerHTML = html

  // Wire up hide-resolved toggle
  const hideResolvedToggle = pane.querySelector('#hideResolvedToggle')
  if (hideResolvedToggle) {
    hideResolvedToggle.addEventListener('change', function() {
      setHideResolved(__activeCtx, hideResolvedToggle.checked)
    })
  }

  // Wire up theme pill clicks — call the same setTheme that app.js uses
  pane.querySelectorAll('[data-settings-theme]').forEach(function(btn) {
    btn.addEventListener('click', function() {
      const theme = btn.dataset.settingsTheme
      // Dispatch the same event that the header theme pill uses
      const event = new CustomEvent('phx:set-theme', { bubbles: true })
      btn.dataset.phxTheme = theme
      btn.dispatchEvent(event)
      pane.querySelectorAll('[data-settings-theme]').forEach(function(b) { b.classList.toggle('active', b.dataset.settingsTheme === theme) })
      updatePillIndicator('settingsThemeIndicator', ['system', 'light', 'dark'], theme)
    })
  })
  updatePillIndicator('settingsThemeIndicator', ['system', 'light', 'dark'], currentTheme)

  // Wire up width pill clicks
  pane.querySelectorAll('[data-settings-width]').forEach(function(btn) {
    btn.addEventListener('click', function() {
      const w = btn.dataset.settingsWidth
      applyWidth(w)
      pane.querySelectorAll('[data-settings-width]').forEach(function(b) { b.classList.toggle('active', b.dataset.settingsWidth === w) })
      updatePillIndicator('settingsWidthIndicator', ['compact', 'default', 'wide'], w)
    })
  })
  updatePillIndicator('settingsWidthIndicator', ['compact', 'default', 'wide'], currentWidth)
}

function renderShortcutsPane() {
  const pane = document.getElementById('shortcutsPane')
  if (!pane) return

  const groups = [
    { label: 'Navigation', shortcuts: [
      { key: '<kbd>j</kbd>', action: 'Next block' },
      { key: '<kbd>k</kbd>', action: 'Previous block' },
      { key: '<kbd>]</kbd>', action: 'Next comment' },
      { key: '<kbd>[</kbd>', action: 'Previous comment' },
    ]},
    { label: 'Comments', shortcuts: [
      { key: '<kbd>c</kbd>', action: 'Comment on focused block (or text selection, with quote)' },
      { key: '<kbd>e</kbd>', action: 'Edit comment on focused block' },
      { key: '<kbd>d</kbd>', action: 'Delete comment on focused block' },
      { key: '<kbd>Shift</kbd>+<kbd>G</kbd>', action: 'General comment' },
      { key: '<kbd>Ctrl</kbd>+<kbd>Enter</kbd>', action: 'Comment' },
    ]},
    { label: 'Review', shortcuts: [
      { key: '<kbd>Shift</kbd>+<kbd>C</kbd>', action: 'Toggle comments panel' },
    ]},
    { label: 'View', shortcuts: [
      { key: '<kbd>t</kbd>', action: 'Toggle table of contents' },
      { key: '<kbd>h</kbd>', action: 'Toggle hide resolved' },
      { key: '<kbd>Esc</kbd>', action: 'Cancel / clear focus' },
      { key: '<kbd>?</kbd>', action: 'Toggle shortcuts' },
    ]},
  ]

  let html = ''
  groups.forEach(function(group) {
    html += '<div class="shortcuts-group-label">' + group.label + '</div>'
    html += '<table class="shortcuts-table">'
    group.shortcuts.forEach(function(s) {
      const modeTag = s.mode ? '<span class="shortcut-mode-badge">' + s.mode + '</span>' : ''
      html += '<tr><td>' + s.key + '</td><td>' + s.action + modeTag + '</td></tr>'
    })
    html += '</table>'
  })

  pane.innerHTML = html
}

function renderAboutPane() {
  const pane = document.getElementById('aboutPane')
  if (!pane) return

  let html = ''

  // Header
  html += '<div class="about-header">'
  html += '<h2>Crit Web</h2>'
  html += '<div class="about-version">Your feedback loop with the agent.</div>'
  html += '</div>'

  // Links
  html += '<div class="settings-section-label">Links</div>'
  html += '<div class="about-links">'
  html += '<a class="about-link" href="https://crit.md" target="_blank" rel="noopener"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M8 1v4M5.5 3h5M3 7h10v6.5a.5.5 0 0 1-.5.5h-9a.5.5 0 0 1-.5-.5V7Z"/></svg>Homepage</a>'
  html += '<a class="about-link" href="https://github.com/tomasz-tomczyk/crit-web" target="_blank" rel="noopener"><svg viewBox="0 0 16 16" fill="currentColor"><path d="M8 0c4.42 0 8 3.58 8 8a8.013 8.013 0 0 1-5.45 7.59c-.4.08-.55-.17-.55-.38 0-.27.01-1.13.01-2.2 0-.75-.25-1.23-.54-1.48 1.78-.2 3.65-.88 3.65-3.95 0-.88-.31-1.59-.82-2.15.08-.2.36-1.02-.08-2.12 0 0-.67-.22-2.2.82-.64-.18-1.32-.27-2-.27-.68 0-1.36.09-2 .27-1.53-1.03-2.2-.82-2.2-.82-.44 1.1-.16 1.92-.08 2.12-.51.56-.82 1.28-.82 2.15 0 3.06 1.86 3.75 3.64 3.95-.23.2-.44.55-.51 1.07-.46.21-1.61.55-2.33-.66-.15-.24-.6-.83-1.23-.82-.67.01-.27.38.01.53.34.19.73.9.82 1.13.16.45.68 1.31 2.69.94 0 .67.01 1.3.01 1.49 0 .21-.15.45-.55.38A7.995 7.995 0 0 1 0 8c0-4.42 3.58-8 8-8Z"/></svg>GitHub</a>'
  html += '<a class="about-link" href="https://crit.md/changelog" target="_blank" rel="noopener"><svg viewBox="0 0 16 16" fill="currentColor"><path d="M1 7.775V2.75C1 1.784 1.784 1 2.75 1h5.025c.464 0 .91.184 1.238.513l6.25 6.25a1.75 1.75 0 0 1 0 2.474l-5.026 5.026a1.75 1.75 0 0 1-2.474 0l-6.25-6.25A1.752 1.752 0 0 1 1 7.775Zm1.5 0c0 .066.026.13.073.177l6.25 6.25a.25.25 0 0 0 .354 0l5.025-5.025a.25.25 0 0 0 0-.354l-6.25-6.25a.25.25 0 0 0-.177-.073H2.75a.25.25 0 0 0-.25.25ZM6 5a1 1 0 1 1 0 2 1 1 0 0 1 0-2Z"/></svg>Changelog</a>'
  html += '</div>'

  pane.innerHTML = html
}

function initSettingsPanel() {
  // Gear icon opens Settings tab
  const settingsToggle = document.getElementById('settingsToggle')
  if (settingsToggle) {
    settingsToggle.addEventListener('click', function() {
      if (settingsPanelOpen) closeSettingsPanel()
      else openSettingsPanel('settings')
    })
  }

  // Close button
  const settingsClose = document.getElementById('settingsClose')
  if (settingsClose) {
    settingsClose.addEventListener('click', closeSettingsPanel)
  }

  // Click outside to close
  const overlay = document.getElementById('settingsOverlay')
  if (overlay) {
    overlay.addEventListener('click', function(e) {
      if (e.target === overlay) closeSettingsPanel()
    })
  }

  // Tab switching
  document.querySelectorAll('.settings-tab[data-tab]').forEach(function(tab) {
    tab.addEventListener('click', function() { switchSettingsTab(tab.dataset.tab) })
  })
}

// ---- Phoenix LiveView hook --------------------------------------------------

export const DocumentRenderer = {
  mounted() {
    const ctx = this
    ctx.comments = []
    ctx.lineBlocks = []
    ctx.selectionStart = null
    ctx.selectionEnd = null
    ctx.activeForms = []
    ctx.dragState = null
    ctx.focusedBlockIndex = -1
    ctx.identity = ctx.el.dataset.identity || ""
    ctx.userId = ctx.el.dataset.userId || ""
    ctx.reviewOwnerId = ctx.el.dataset.reviewOwnerId || ""
    ctx.reviewRound = parseInt(ctx.el.dataset.reviewRound || "0", 10)
    ctx.multiFile = ctx.el.dataset.multiFile === 'true'
    ctx.files = []
    ctx.singleFilePath = null
    ctx.focusedFilePath = null
    ctx.treeFolderState = {}
    ctx.prevRoundSnapshots = {}
    ctx.showRoundDiff = false
    ctx.diffMode = 'split'
    ctx._navCommentId = null
    ctx._hideResolved = readHideResolved()
    ctx._timers = new Set()

    // Initialize content width and settings panel
    initWidth()
    initSettingsPanel()

    const rawContent = ctx.el.dataset.content || ""
    ctx.rawContent = rawContent
    ctx.reviewToken = window.location.pathname.split('/').pop()

    // Build the markdown parser (same config as crit)
    const md = markdownit({
      html: true,
      typographer: true,
      linkify: true,
      highlight(str, lang) {
        if (lang && hljs.getLanguage(lang)) {
          try { return hljs.highlight(str, { language: lang }).value } catch (_) {}
        }
        return ""
      },
    })

    // Task list support
    const defaultListItemOpen = md.renderer.rules.list_item_open ||
      function(tokens, idx, options, env, self) { return self.renderToken(tokens, idx, options) }
    md.renderer.rules.list_item_open = function(tokens, idx, options, _env, self) {
      for (let i = idx + 1; i < tokens.length; i++) {
        if (tokens[i].type === "list_item_close") break
        if (tokens[i].type === "inline" && /^\[[ x]\]\s/.test(tokens[i].content)) {
          tokens[idx].attrJoin("class", "task-list-item")
          break
        }
      }
      return defaultListItemOpen(tokens, idx, options, _env, self)
    }

    ctx.md = md
    ctx.lineBlocks = buildLineBlocks(md, rawContent)

    // Build table of contents. Content arrives via the "init" event, so on
    // mount the list is empty; rebuildToc() is called again from init to
    // populate items, run auto-open, and feed scroll spy.
    const tocEl = document.getElementById("crit-toc")
    const tocToggleBtn = document.getElementById("crit-toc-toggle")
    ctx.tocItems = []
    ctx.rebuildToc = (rawContentForToc) => {
      if (!tocEl || !tocToggleBtn) return
      const items = extractTocItems(md, rawContentForToc)
      ctx.tocItems = items
      buildToc(tocEl, tocToggleBtn, items)
      if (items.length >= 2) {
        const saved = localStorage.getItem("crit-toc")
        if (saved === "open" || (saved === null && window.innerWidth > 1200)) {
          tocEl.classList.remove("crit-toc-hidden")
        }
      }
    }
    ctx.rebuildToc(rawContent)
    if (tocEl && tocToggleBtn) {
      tocToggleBtn.addEventListener("click", () => {
        const isHidden = tocEl.classList.contains("crit-toc-hidden")
        tocEl.classList.toggle("crit-toc-hidden", !isHidden)
        localStorage.setItem("crit-toc", isHidden ? "open" : "closed")
      })
      tocEl.querySelector(".crit-toc-close").addEventListener("click", () => {
        tocEl.classList.add("crit-toc-hidden")
        localStorage.setItem("crit-toc", "closed")
      })
    }

    // Scroll spy for active TOC item
    let scrollSpyFrame = null
    ctx._scrollHandler = () => {
      if (scrollSpyFrame) return
      scrollSpyFrame = requestAnimationFrame(() => {
        scrollSpyFrame = null
        updateTocActive(ctx.tocItems)
      })
    }
    window.addEventListener("scroll", ctx._scrollHandler, { passive: true })

    const prevBtn = document.getElementById('comment-nav-prev')
    if (prevBtn) prevBtn.addEventListener('click', () => navigateToComment(ctx, -1))
    const nextBtn = document.getElementById('comment-nav-next')
    if (nextBtn) nextBtn.addEventListener('click', () => navigateToComment(ctx, 1))

    // Comments panel — append to #crit-main-layout (outside hook root) so it
    // survives LiveView DOM patches. Reuse an existing panel if mounted() runs
    // again with one already attached (defensive: prevents duplicate panels).
    const existingPanel = document.querySelector('#crit-main-layout > .comments-panel')
    if (existingPanel && !ctx._commentsPanel) {
      existingPanel.remove()
    }
    if (ctx._commentsPanel) {
      // Already created in this hook instance — nothing to do.
    } else {
    const commentsPanel = document.createElement('div')
    commentsPanel.id = 'commentsPanel'
    commentsPanel.className = 'comments-panel'
    commentsPanel.innerHTML = `
      <div class="comments-panel-header">
        <div class="comments-panel-header-row1">
          <div class="comments-panel-header-left">
            <span class="comments-panel-title">Comments</span>
            <span class="comments-panel-count-badge" id="commentsPanelCountBadge">0</span>
          </div>
          <div class="comments-panel-header-actions">
            <button class="comments-panel-close" title="Close comments panel" aria-label="Close comments panel">&#x2715;</button>
          </div>
        </div>
        <div class="comments-panel-header-row2">
          <div class="comments-filter-toggle crit-diff-mode-toggle" id="commentsFilterPill" role="radiogroup" aria-label="Filter comments">
            <button class="crit-toggle-btn crit-toggle-btn--active" data-filter="all" role="radio" aria-checked="true" tabindex="0">All <span class="filter-count">0</span></button>
            <button class="crit-toggle-btn" data-filter="open" role="radio" aria-checked="false" tabindex="-1">Open <span class="filter-count">0</span></button>
            <button class="crit-toggle-btn" data-filter="resolved" role="radio" aria-checked="false" tabindex="-1">Resolved <span class="filter-count">0</span></button>
          </div>
          <button class="comments-panel-expand-all" id="commentsPanelExpandAll">Expand all</button>
        </div>
      </div>
      <div class="comments-panel-body"></div>
    `
    // Track active filter: 'all', 'open', 'resolved'
    ctx._commentsActiveFilter = 'all'

    commentsPanel.querySelector('.comments-panel-close').addEventListener('click', () => {
      commentsPanel.classList.remove('comments-panel-open')
      syncCommentsPanelAria(false)
      updateTocPosition(ctx)
    })

    // Segmented pill filter (radiogroup with roving tabindex)
    const filterPill = commentsPanel.querySelector('#commentsFilterPill')
    function activateFilterBtn(btn, focus) {
      if (!btn) return
      const filter = btn.dataset.filter
      ctx._commentsActiveFilter = filter
      filterPill.querySelectorAll('.crit-toggle-btn').forEach(b => {
        const active = b === btn
        b.classList.toggle('crit-toggle-btn--active', active)
        b.setAttribute('aria-checked', active ? 'true' : 'false')
        b.setAttribute('tabindex', active ? '0' : '-1')
      })
      if (focus) btn.focus()
      renderCommentsPanel(ctx)
    }
    filterPill.addEventListener('click', (e) => {
      const btn = e.target.closest('.crit-toggle-btn')
      if (!btn) return
      activateFilterBtn(btn, false)
    })
    filterPill.addEventListener('keydown', (e) => {
      const btns = Array.from(filterPill.querySelectorAll('.crit-toggle-btn'))
      const currentIdx = btns.findIndex(b => b === document.activeElement)
      if (currentIdx === -1) return
      let nextIdx = null
      if (e.key === 'ArrowRight' || e.key === 'ArrowDown') {
        nextIdx = (currentIdx + 1) % btns.length
      } else if (e.key === 'ArrowLeft' || e.key === 'ArrowUp') {
        nextIdx = (currentIdx - 1 + btns.length) % btns.length
      } else if (e.key === 'Home') {
        nextIdx = 0
      } else if (e.key === 'End') {
        nextIdx = btns.length - 1
      } else {
        return
      }
      e.preventDefault()
      activateFilterBtn(btns[nextIdx], true)
    })

    // Expand all / Collapse all
    commentsPanel.querySelector('#commentsPanelExpandAll').addEventListener('click', () => {
      toggleExpandAllComments(ctx)
    })
    const mainLayout = document.getElementById('crit-main-layout')
    // Inject the comments-panel resize handle as a sibling immediately before
    // the panel — drag the handle to widen/narrow the panel.
    const commentsResizer = document.createElement('div')
    commentsResizer.id = 'commentsPanelResizer'
    commentsResizer.className = 'sidebar-resize-handle'
    commentsResizer.setAttribute('role', 'separator')
    commentsResizer.setAttribute('tabindex', '0')
    commentsResizer.setAttribute('aria-orientation', 'vertical')
    commentsResizer.setAttribute('aria-label', 'Resize comments panel')
    mainLayout.appendChild(commentsResizer)
    mainLayout.appendChild(commentsPanel)
    ctx._commentsPanel = commentsPanel
    ctx._commentsPanelResizer = commentsResizer
    initSidebarWidths()
    }

    // Wire comment count as panel toggle. The button uses phx-click with
    // JS.dispatch("crit:toggle-comments", to: "#document-renderer") so this
    // listener survives LiveView DOM patches to the header.
    ctx.el.addEventListener('crit:toggle-comments', () => toggleCommentsPanel(ctx))

    // Show loading until server sends init
    ctx.el.innerHTML = '<div class="crit-loading">Loading comments…</div>'

    // Comment-affordance class (`.crit-no-comments`) is server-rendered on
    // the `.crit-page` wrapper (see review_live.html.heex), so the visual
    // suppression is always in sync with @can_comment? — no JS toggle, no
    // reliance on push_event delivery. The hook still receives policy_changed
    // so it can drop any open new-comment composers and re-render the document
    // (closing forms that CSS alone can't unwind for an actively-typing user).
    ctx.handleEvent("policy_changed", ({ can_comment }) => {
      const next = can_comment !== false
      const changed = ctx.canComment !== next
      ctx.canComment = next
      if (changed && ctx.md) {
        ctx.activeForms = ctx.activeForms.filter((f) => f.editingId)
        render(ctx)
      }
    })

    ctx.handleEvent("init", ({ comments, display_name, files, can_comment }) => {
      ctx.displayName = display_name || null
      ctx.comments = comments
      ctx.canComment = can_comment !== false

      if (files && files.length > 1) {
        ctx.multiFile = true
        ctx.files = files.map(f => {
          const orphaned = f.status === 'removed'
          return {
            path: f.path,
            content: f.content,
            position: f.position,
            fileType: isCodeFile(f.path) ? 'code' : 'markdown',
            lineBlocks: orphaned ? [] : (isCodeFile(f.path)
              ? buildCodeLineBlocks(f.content, f.path)
              : buildLineBlocks(md, f.content)),
            comments: comments.filter(c => c.file_path === f.path),
            collapsed: orphaned,
            viewed: false,
            status: f.status || 'modified',
            orphaned,
          }
        })
        restoreViewedState(ctx)
      } else if (files && files.length === 1) {
        const f = files[0]
        ctx.rawContent = f.content
        ctx.singleFilePath = f.path
        ctx.lineBlocks = isCodeFile(f.path)
          ? buildCodeLineBlocks(f.content, f.path)
          : buildLineBlocks(md, f.content)
        // Rebuild TOC with actual content (mount ran before content arrived).
        // ctx.rebuildToc updates the items used by scroll spy and re-runs
        // the auto-open heuristic now that we know there are headings.
        ctx.rebuildToc(f.content)
      }

      render(ctx)
      restoreDrafts(ctx)
      if (ctx._commentsPanel?.classList.contains('comments-panel-open')) {
        renderCommentsPanel(ctx)
      }
    })

    ctx.handleEvent("display_name_updated", (data) => {
      ctx.displayName = data.display_name
      const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
      fetch("/set-name", {
        method: "POST",
        headers: {"Content-Type": "application/json", "x-csrf-token": csrfToken},
        body: JSON.stringify({name: data.display_name})
      }).catch(() => {})
      render(ctx)
    })

    // ===== Delta comment sync handlers =====

    ctx.handleEvent("comment_added", ({ comment }) => {
      ctx.comments.push(comment)
      if (ctx.multiFile) {
        const f = ctx.files.find(fl => fl.path === comment.file_path)
        if (f) f.comments.push(comment)
      }
      insertInlineComment(ctx, comment)
      updateCommentCount(ctx)
      updateTreeBadge(ctx, comment.file_path)
      rerenderPanel(ctx)
    })

    ctx.handleEvent("comment_updated", ({ id, body, updated_at }) => {
      const comment = ctx.comments.find(c => c.id === id)
      if (!comment) return
      comment.body = body
      comment.updated_at = updated_at
      const card = ctx.el.querySelector(`.comment-card[data-comment-id="${id}"]`)
      if (card) {
        const bodyEl = card.querySelector('.comment-body')
        if (bodyEl) bodyEl.innerHTML = commentMd.render(body)
      }
      rerenderPanel(ctx)
    })

    ctx.handleEvent("comment_deleted", ({ id }) => {
      const comment = ctx.comments.find(c => c.id === id)
      if (!comment) return
      ctx.comments = ctx.comments.filter(c => c.id !== id)
      if (ctx.multiFile) {
        const f = ctx.files.find(fl => fl.path === comment.file_path)
        if (f) f.comments = f.comments.filter(c => c.id !== id)
      }
      removeInlineComment(ctx, comment)
      updateCommentCount(ctx)
      updateTreeBadge(ctx, comment.file_path)
      rerenderPanel(ctx)
    })

    ctx.handleEvent("comment_resolved", ({ id, resolved }) => {
      const comment = ctx.comments.find(c => c.id === id)
      if (!comment) return
      comment.resolved = resolved
      // Re-render just this comment inline (resolved/unresolved have different renderers)
      const block = ctx.el.querySelector(`.comment-block:has(> .comment-card[data-comment-id="${id}"])`)
      if (block) {
        const newEl = createCommentElement(comment, ctx)
        block.replaceWith(newEl)
      }
      updateCommentCount(ctx)
      updateTreeBadge(ctx, comment.file_path)
      rerenderPanel(ctx)
    })

    ctx.handleEvent("reply_added", ({ parent_id, reply }) => {
      const comment = ctx.comments.find(c => c.id === parent_id)
      if (!comment) return
      if (!comment.replies) comment.replies = []
      comment.replies.push(reply)
      const card = ctx.el.querySelector(`.comment-card[data-comment-id="${parent_id}"]`)
      if (card) {
        let repliesContainer = card.querySelector('.comment-replies')
        if (repliesContainer) {
          repliesContainer.replaceWith(renderReplyList(comment, ctx))
        } else {
          const replyInput = card.querySelector('.reply-form')
          if (replyInput) {
            card.insertBefore(renderReplyList(comment, ctx), replyInput)
          } else {
            card.appendChild(renderReplyList(comment, ctx))
          }
        }
      }
      rerenderPanel(ctx)
    })

    ctx.handleEvent("reply_updated", ({ parent_id, id, body }) => {
      const comment = ctx.comments.find(c => c.id === parent_id)
      if (!comment) return
      const reply = comment.replies && comment.replies.find(r => r.id === id)
      if (!reply) return
      reply.body = body
      const replyEl = ctx.el.querySelector(`.comment-reply[data-reply-id="${id}"]`)
      if (replyEl) {
        const bodyEl = replyEl.querySelector('.reply-body')
        if (bodyEl) {
          bodyEl.dataset.rawBody = body
          bodyEl.innerHTML = commentMd.render(body)
        }
      }
      rerenderPanel(ctx)
    })

    ctx.handleEvent("reply_deleted", ({ parent_id, id }) => {
      const comment = ctx.comments.find(c => c.id === parent_id)
      if (!comment) return
      comment.replies = (comment.replies || []).filter(r => r.id !== id)
      const replyEl = ctx.el.querySelector(`.comment-reply[data-reply-id="${id}"]`)
      if (replyEl) replyEl.remove()
      rerenderPanel(ctx)
    })

    ctx.handleEvent("display_name_changed", ({ identity, name }) => {
      for (const c of ctx.comments) {
        if (c.author_identity === identity) c.author_display_name = name
        for (const r of (c.replies || [])) {
          if (r.author_identity === identity) r.author_display_name = name
        }
      }
      // Display name changes are rare — full re-render is acceptable
      render(ctx)
      rerenderPanel(ctx)
    })

    // Full sync escape hatch (reconnect, noop_refresh)
    ctx.handleEvent("comments_full_sync", ({ comments }) => {
      ctx.comments = comments
      if (ctx.multiFile) {
        for (const f of ctx.files) {
          f.comments = comments.filter(c => c.file_path === f.path)
        }
      }
      render(ctx)
      rerenderPanel(ctx)
    })

    // Legacy handler — kept for backwards compatibility during rollout
    ctx.handleEvent("comments_updated", ({ comments }) => {
      ctx.comments = comments
      if (ctx.multiFile) {
        for (const f of ctx.files) {
          f.comments = comments.filter(c => c.file_path === f.path)
        }
      }
      render(ctx)
      rerenderPanel(ctx)
    })

    ctx.handleEvent("round_diff_updated", ({ enabled, snapshots }) => {
      ctx.showRoundDiff = enabled
      ctx.prevRoundSnapshots = snapshots || {}
      render(ctx)
    })

    ctx.handleEvent("diff_mode_updated", ({ mode }) => {
      ctx.diffMode = mode
      if (ctx.showRoundDiff) {
        render(ctx)
      }
    })

    // ===== Select-to-Comment helper =====
    // Selection alone never opens the form — copying text stays unhindered.
    // The user presses `c` after selecting to comment on the selection.
    // Returns true if a form was opened from an active selection.
    const tryOpenFormFromSelection = () => {
      const selection = window.getSelection()
      const range = getLineRangeFromSelection(selection)
      if (!range) return false

      let quote = null
      try {
        let selectedText = selection.toString().trim()
        if (selectedText) {
          let fullText = ''
          for (let ln = range.startLine; ln <= range.endLine; ln++) {
            ctx.el.querySelectorAll('.line-block[data-file-path]').forEach(function(el) {
              if (el.dataset.filePath !== range.filePath) return
              const s = parseInt(el.dataset.startLine), endLn = parseInt(el.dataset.endLine)
              if (s <= ln && endLn >= ln) {
                const content = el.querySelector('.line-content')
                if (content) fullText += (fullText ? '\n' : '') + content.textContent.trim()
              }
            })
          }
          const normalizedSelected = selectedText.replace(/\s+/g, ' ')
          const normalizedFull = fullText.trim().replace(/\s+/g, ' ')
          if (normalizedSelected !== normalizedFull && selectedText.length <= 300) {
            quote = selectedText
          }
        }
      } catch (_) { /* quote is a nice-to-have, don't break form opening */ }

      selection.removeAllRanges()
      openForm(ctx, {
        filePath: range.filePath,
        afterBlockIndex: range.afterBlockIndex,
        startLine: range.startLine,
        endLine: range.endLine,
        editingId: null,
        quote: quote,
      })
      return true
    }
    ctx._tryOpenFormFromSelection = tryOpenFormFromSelection

    ctx._keydownHandler = (e) => {
      const tag = e.target.tagName
      if (tag === 'TEXTAREA' || tag === 'INPUT' || e.target.isContentEditable) {
        // Textarea keydown is handled by per-form handlers with stopPropagation
        return
      }
      // Allow Shift (for Shift+C) but block other modifiers
      if (e.metaKey || e.ctrlKey || e.altKey) return

      // Settings panel (shortcuts tab via ?)
      if (e.key === '?') {
        e.preventDefault()
        if (settingsPanelOpen) closeSettingsPanel()
        else openSettingsPanel('shortcuts')
        return
      }
      if (settingsPanelOpen) {
        if (e.key === 'Escape') {
          e.preventDefault()
          closeSettingsPanel()
        }
        return
      }

      // Comments panel toggle
      if (e.key === 'C' && e.shiftKey) {
        e.preventDefault()
        toggleCommentsPanel(ctx)
        return
      }

      // Hide resolved toggle
      if (e.key === 'h') {
        e.preventDefault()
        const current = isHideResolved(ctx)
        setHideResolved(ctx, !current)
        // Sync settings pane toggle if open
        const toggle = document.getElementById('hideResolvedToggle')
        if (toggle) toggle.checked = !current
        return
      }

      // Comment navigation
      if (e.key === '[') { e.preventDefault(); navigateToComment(ctx, -1); return }
      if (e.key === ']') { e.preventDefault(); navigateToComment(ctx, 1); return }

      // Review comment form
      if (e.key === 'G' && e.shiftKey) {
        e.preventDefault()
        openReviewCommentForm(ctx)
        return
      }

      const blocks = ctx.el.querySelectorAll('.line-block')
      const blockCount = blocks.length

      switch (e.key) {
        case 'j': {
          e.preventDefault()
          const next = ctx.focusedBlockIndex < blockCount - 1 ? ctx.focusedBlockIndex + 1 : 0
          focusBlock(ctx, next)
          break
        }
        case 'k': {
          e.preventDefault()
          const prev = ctx.focusedBlockIndex > 0 ? ctx.focusedBlockIndex - 1 : blockCount - 1
          focusBlock(ctx, prev)
          break
        }
        case 'c': {
          e.preventDefault()
          // If text is selected, comment on the selection (with quote).
          // Otherwise fall back to the focused block.
          if (ctx._tryOpenFormFromSelection && ctx._tryOpenFormFromSelection()) break
          if (ctx.focusedBlockIndex < 0) break
          const lineBlocks = getFocusedLineBlocks(ctx)
          const block = lineBlocks[ctx.focusedBlockIndex]
          if (!block) break
          openForm(ctx, {
            afterBlockIndex: ctx.focusedBlockIndex,
            startLine: block.startLine,
            endLine: block.endLine,
            editingId: null,
            filePath: ctx.focusedFilePath || null,
          })
          break
        }
        case 'e': {
          e.preventDefault()
          if (ctx.focusedBlockIndex < 0) break
          const lineBlocks = getFocusedLineBlocks(ctx)
          const block = lineBlocks[ctx.focusedBlockIndex]
          if (!block) break
          const filePath = ctx.focusedFilePath || null
          const comment = ctx.comments.find(c =>
            isOwnComment(c, ctx) &&
            c.end_line >= block.startLine && c.end_line <= block.endLine &&
            (c.file_path || null) === filePath
          )
          if (!comment) break
          const editFormObj = {
            afterBlockIndex: null,
            startLine: comment.start_line,
            endLine: comment.end_line,
            editingId: comment.id,
            filePath: filePath,
          }
          addForm(ctx, editFormObj)
          render(ctx)
          break
        }
        case 'd': {
          e.preventDefault()
          if (ctx.focusedBlockIndex < 0) break
          const lineBlocks = getFocusedLineBlocks(ctx)
          const block = lineBlocks[ctx.focusedBlockIndex]
          if (!block) break
          const filePath = ctx.focusedFilePath || null
          const comment = ctx.comments.find(c =>
            isOwnComment(c, ctx) &&
            c.end_line >= block.startLine && c.end_line <= block.endLine &&
            (c.file_path || null) === filePath
          )
          if (comment) ctx.pushEvent('delete_comment', { id: comment.id })
          break
        }
        case 't': {
          e.preventDefault()
          const tocToggle = document.getElementById('crit-toc-toggle')
          if (tocToggle) tocToggle.click()
          break
        }
        case 'Escape': {
          e.preventDefault()
          if (ctx.activeForms.length > 0) {
            const top = ctx.activeForms[ctx.activeForms.length - 1]
            if (confirmDiscardIfDirty(top)) cancelComment(top, ctx)
          } else if (ctx.focusedBlockIndex >= 0) {
            clearFocus(ctx)
          }
          break
        }
      }
    }
    document.addEventListener('keydown', ctx._keydownHandler)
  },

  destroyed() {
    document.body.classList.remove("dragging")
    if (this._scrollHandler) {
      window.removeEventListener("scroll", this._scrollHandler)
    }
    if (this._keydownHandler) {
      document.removeEventListener("keydown", this._keydownHandler)
    }
    if (this._resizeHandler) {
      window.removeEventListener("resize", this._resizeHandler)
    }
    // Close settings panel if open
    closeSettingsPanel()
    // Defensive: clear any pending tracked timeouts so callbacks don't fire
    // against a torn-down hook (and detached DOM nodes).
    if (this._timers) {
      for (const id of this._timers) clearTimeout(id)
      this._timers.clear()
    }
    // Defensive: panel-internal handlers may have been attached to
    // document/window in future changes — remove them here if present.
    if (this._panelDocClickHandler) {
      document.removeEventListener('click', this._panelDocClickHandler)
      this._panelDocClickHandler = null
    }
    if (this._panelDocKeyHandler) {
      document.removeEventListener('keydown', this._panelDocKeyHandler)
      this._panelDocKeyHandler = null
    }
    if (this._commentsPanel) {
      this._commentsPanel.remove()
      this._commentsPanel = null
    }
    if (this._commentsPanelResizer) {
      this._commentsPanelResizer.remove()
      this._commentsPanelResizer = null
    }
  },
}
