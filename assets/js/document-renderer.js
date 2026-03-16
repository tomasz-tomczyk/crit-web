import markdownit from "markdown-it"
import hljs from "highlight.js/lib/core"
import javascript from "highlight.js/lib/languages/javascript"
import typescript from "highlight.js/lib/languages/typescript"
import go from "highlight.js/lib/languages/go"
import python from "highlight.js/lib/languages/python"
import ruby from "highlight.js/lib/languages/ruby"
import rust from "highlight.js/lib/languages/rust"
import sql from "highlight.js/lib/languages/sql"
import bash from "highlight.js/lib/languages/bash"
import json from "highlight.js/lib/languages/json"
import yaml from "highlight.js/lib/languages/yaml"
import xml from "highlight.js/lib/languages/xml"
import css from "highlight.js/lib/languages/css"
import elixir from "highlight.js/lib/languages/elixir"

hljs.registerLanguage("javascript", javascript)
hljs.registerLanguage("typescript", typescript)
hljs.registerLanguage("go", go)
hljs.registerLanguage("python", python)
hljs.registerLanguage("ruby", ruby)
hljs.registerLanguage("rust", rust)
hljs.registerLanguage("sql", sql)
hljs.registerLanguage("bash", bash)
hljs.registerLanguage("json", json)
hljs.registerLanguage("yaml", yaml)
hljs.registerLanguage("xml", xml)
hljs.registerLanguage("css", css)
hljs.registerLanguage("elixir", elixir)

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

// ===== Suggestion Diff Renderer =====
function renderSuggestionDiff(suggestionContent, originalLines) {
  let sugLines = suggestionContent.replace(/\n$/, '').split('\n')
  let html = '<div class="suggestion-diff">'
  html += '<div class="suggestion-header">Suggested change</div>'

  const origLen = (originalLines && originalLines.length > 0) ? originalLines.length : 0
  const isEmptySuggestion = sugLines.length === 1 && sugLines[0] === '' && origLen > 0
  const sugLen = isEmptySuggestion ? 0 : sugLines.length
  const pairedLen = Math.min(origLen, sugLen)
  const hasWordDiff = typeof wordDiff === 'function' && typeof applyWordDiffToHtml === 'function'

  // Compute word-level diffs for paired lines
  const delContents = []
  const addContents = []
  for (let i = 0; i < pairedLen; i++) {
    const wd = hasWordDiff ? wordDiff(originalLines[i], sugLines[i]) : null
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
  setTimeout(() => {
    toast.classList.remove('mini-toast-visible')
    setTimeout(() => toast.remove(), 300)
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

function langFromPath(filePath) {
  const ext = (filePath || '').split('.').pop().toLowerCase()
  const map = {
    js: 'javascript', jsx: 'javascript', ts: 'typescript', tsx: 'typescript',
    go: 'go', py: 'python', rb: 'ruby', rs: 'rust',
    sql: 'sql', sh: 'bash', bash: 'bash', zsh: 'bash',
    json: 'json', yaml: 'yaml', yml: 'yaml',
    html: 'xml', htm: 'xml', xml: 'xml', svg: 'xml',
    css: 'css', scss: 'css', less: 'css',
    ex: 'elixir', exs: 'elixir',
    md: 'markdown', java: 'java', kt: 'kotlin',
    c: 'c', h: 'c', cpp: 'cpp', hpp: 'cpp',
    cs: 'csharp', swift: 'swift', php: 'php',
    r: 'r', lua: 'lua', zig: 'zig', nim: 'nim',
    toml: 'ini', ini: 'ini', dockerfile: 'dockerfile',
    makefile: 'makefile', tf: 'hcl',
  }
  return map[ext] || null
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
    const unresolvedCount = f.comments.length
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
    collapseBtn.title = 'Collapse all folders'
    collapseBtn.innerHTML = '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path d="M4.22 3.22a.75.75 0 0 1 1.06 0L8 5.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 4.28a.75.75 0 0 1 0-1.06zm0 5a.75.75 0 0 1 1.06 0L8 10.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 9.28a.75.75 0 0 1 0-1.06z"/></svg>'
    collapseBtn.addEventListener('click', function() {
      const allFolders = panel.querySelectorAll('.tree-folder')
      const anyExpanded = Array.from(allFolders).some(f => !f.classList.contains('collapsed'))
      allFolders.forEach(function(f) {
        const fp = f.dataset.folderPath
        ctx.treeFolderState[fp] = anyExpanded
        f.classList.toggle('collapsed', anyExpanded)
      })
      collapseBtn.title = anyExpanded ? 'Expand all folders' : 'Collapse all folders'
      collapseBtn.classList.toggle('all-collapsed', anyExpanded)
    })
    headerEl.appendChild(collapseBtn)
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

function render(ctx) {
  if (ctx.multiFile) {
    renderMultiFile(ctx)
  } else {
    renderDocument(ctx)
  }
}

// ---- Multi-file rendering ---------------------------------------------------

function renderMultiFile(ctx) {
  saveOpenFormContent(ctx)
  const container = ctx.el
  container.classList.add('multi-file')

  // Measure actual header height and set CSS variable for sticky positioning
  const header = document.querySelector('.crit-header')
  if (header) {
    document.documentElement.style.setProperty('--crit-header-height', header.offsetHeight + 'px')
  }

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

function renderFileSection(ctx, file) {
  const section = document.createElement('details')
  section.className = 'file-section'
  section.id = 'file-section-' + CSS.escape(file.path)
  if (!file.collapsed) section.open = true

  const header = document.createElement('summary')
  header.className = 'file-header'

  // Scroll correction on collapse
  header.addEventListener('click', function(e) {
    if (e.target.closest('.file-header-viewed')) {
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
    header.blur()
  })
  section.addEventListener('toggle', function() {
    file.collapsed = !section.open
  })

  const unresolvedCount = file.comments.length
  const dirParts = file.path.split('/')
  const fileName = dirParts.pop()
  const dirPath = dirParts.length > 0 ? dirParts.join('/') + '/' : ''

  header.innerHTML =
    '<div class="file-header-chevron"><svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path d="M12.78 5.22a.749.749 0 0 1 0 1.06l-4.25 4.25a.749.749 0 0 1-1.06 0L3.22 6.28a.749.749 0 1 1 1.06-1.06L8 8.939l3.72-3.719a.749.749 0 0 1 1.06 0Z"/></svg></div>' +
    '<svg class="file-header-icon" viewBox="0 0 16 16" fill="var(--crit-fg-dimmed)"><path fill-rule="evenodd" d="M3.75 1.5a.25.25 0 0 0-.25.25v12.5c0 .138.112.25.25.25h8.5a.25.25 0 0 0 .25-.25V6H9.75A1.75 1.75 0 0 1 8 4.25V1.5H3.75zm5.75.56v2.19c0 .138.112.25.25.25h2.19L9.5 2.06zM2 1.75C2 .784 2.784 0 3.75 0h5.086c.464 0 .909.184 1.237.513l3.414 3.414c.329.328.513.773.513 1.237v8.086A1.75 1.75 0 0 1 12.25 15h-8.5A1.75 1.75 0 0 1 2 13.25V1.75z"/></svg>' +
    '<span class="file-header-name"><span class="dir">' + escapeHtml(dirPath) + '</span>' + escapeHtml(fileName) + '</span>' +
    (unresolvedCount > 0 ? '<span class="file-header-comment-count">' +
      '<svg viewBox="0 0 16 16" fill="currentColor"><path d="M1 2.75C1 1.784 1.784 1 2.75 1h10.5c.966 0 1.75.784 1.75 1.75v7.5A1.75 1.75 0 0 1 13.25 12H9.06l-2.573 2.573A1.458 1.458 0 0 1 4 13.543V12H2.75A1.75 1.75 0 0 1 1 10.25Zm1.75-.25a.25.25 0 0 0-.25.25v7.5c0 .138.112.25.25.25h2a.75.75 0 0 1 .75.75v2.19l2.72-2.72a.749.749 0 0 1 .53-.22h4.5a.25.25 0 0 0 .25-.25v-7.5a.25.25 0 0 0-.25-.25Z"/></svg>' +
      unresolvedCount + '</span>' : '')

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

  // File body — render using renderBlock per block
  const body = document.createElement('div')
  body.className = 'file-body' + (file.fileType === 'code' ? ' code-document' : '')

  const commentsMap = buildCommentsMap(file.comments)
  const commentedLineSet = buildCommentedLineSet(file.comments)
  const lineBlocks = file.lineBlocks

  for (let i = 0; i < lineBlocks.length; i++) {
    const block = lineBlocks[i]
    const blockEl = renderBlock(ctx, block, i, commentsMap, commentedLineSet, file.path)
    body.appendChild(blockEl)
  }

  if (file.fileType !== 'code') {
    replaceBrokenImages(body)
  }

  section.appendChild(body)
  return section
}

// ---- Render document --------------------------------------------------------

function buildCommentsMap(comments) {
  const map = {}
  for (const c of comments) {
    if (!map[c.end_line]) map[c.end_line] = []
    map[c.end_line].push(c)
  }
  return map
}

function buildCommentedLineSet(comments) {
  const set = new Set()
  for (const c of comments) {
    for (let ln = c.start_line; ln <= c.end_line; ln++) set.add(ln)
  }
  return set
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

  // Gutter
  const gutter = document.createElement("div")
  gutter.className = "line-gutter"
  gutter.dataset.startLine = block.startLine
  gutter.dataset.endLine = block.endLine

  const lineNum = document.createElement("span")
  lineNum.className = "line-num"
  lineNum.textContent = block.startLine === block.endLine ? block.startLine : String(block.startLine)

  const lineAdd = document.createElement("span")
  lineAdd.className = "line-add"
  lineAdd.textContent = "+"

  gutter.appendChild(lineNum)
  gutter.appendChild(lineAdd)
  gutter.addEventListener("mousedown", (e) => handleGutterMouseDown(e, ctx))

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

  const commentsMap = buildCommentsMap(ctx.comments)
  const commentedLineSet = buildCommentedLineSet(ctx.comments)

  for (let bi = 0; bi < ctx.lineBlocks.length; bi++) {
    const block = ctx.lineBlocks[bi]
    container.appendChild(renderBlock(ctx, block, bi, commentsMap, commentedLineSet, ctx.singleFilePath || null))
  }

  renderMermaidBlocks(container)
  replaceBrokenImages(container)
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
  const total = ctx.comments.length
  const numEl = document.getElementById('commentCountNumber')
  if (total === 0) {
    el.style.display = 'none'
    el.title = 'Toggle comments panel'
  } else {
    el.style.display = ''
    el.classList.remove('comment-count-resolved')
    el.title = total + ' comment' + (total === 1 ? '' : 's') + ' — toggle panel'
    if (numEl) numEl.textContent = total
  }
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
  const editForm = findFormForEdit(ctx, comment.id)
  if (editForm) {
    return createInlineEditor(comment, editForm, ctx)
  }

  const isOwn = comment.author_identity === ctx.identity

  const wrapper = document.createElement("div")
  wrapper.className = "comment-block"

  const card = document.createElement("div")
  card.className = "comment-card"
  card.dataset.commentId = comment.id
  card.style.setProperty("--comment-hue", identityHue(comment.author_identity))

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

  const author = document.createElement("span")
  author.className = "comment-author" + (isOwn ? " comment-author-you" : "")
  author.innerHTML =
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="comment-author-icon"><path fill-rule="evenodd" d="M18.685 19.097A9.723 9.723 0 0 0 21.75 12c0-5.385-4.365-9.75-9.75-9.75S2.25 6.615 2.25 12a9.723 9.723 0 0 0 3.065 7.097A9.716 9.716 0 0 0 12 21.75a9.716 9.716 0 0 0 6.685-2.653Zm-12.54-1.285A7.486 7.486 0 0 1 12 15a7.486 7.486 0 0 1 5.855 2.812A8.224 8.224 0 0 1 12 20.25a8.224 8.224 0 0 1-5.855-2.438ZM15.75 9a3.75 3.75 0 1 1-7.5 0 3.75 3.75 0 0 1 7.5 0Z" clip-rule="evenodd"/></svg>` +
    (isOwn ? (ctx.displayName || "You") : (comment.author_display_name || comment.author_identity || "?").slice(0, 20))

  const sep = () => {
    const s = document.createElement("span")
    s.className = "comment-header-sep"
    s.textContent = "·"
    return s
  }

  const headerLeft = document.createElement("div")
  headerLeft.style.cssText = "display:flex;align-items:center;gap:6px"
  headerLeft.appendChild(author)
  if (comment.review_round >= 1) {
    headerLeft.appendChild(sep())
    const roundBadge = document.createElement("span")
    const rc = comment.review_round === ctx.reviewRound ? " round-current" : comment.review_round === ctx.reviewRound - 1 ? " round-latest" : ""
    roundBadge.className = "comment-round-badge" + rc
    roundBadge.textContent = "R" + comment.review_round
    headerLeft.appendChild(roundBadge)
  }
  headerLeft.appendChild(sep())
  headerLeft.appendChild(lineRef)
  headerLeft.appendChild(sep())
  headerLeft.appendChild(time)

  header.appendChild(headerLeft)

  if (isOwn) {
    const actions = document.createElement("div")
    actions.className = "comment-actions"

    const editBtn = document.createElement("button")
    editBtn.textContent = "Edit"
    editBtn.addEventListener("click", () => {
      const editFormObj = { afterBlockIndex: null, startLine: comment.start_line, endLine: comment.end_line, editingId: comment.id, filePath: comment.file_path || null }
      addForm(ctx, editFormObj)
      render(ctx)
    })

    const deleteBtn = document.createElement("button")
    deleteBtn.className = "delete-btn"
    deleteBtn.textContent = "Delete"
    deleteBtn.addEventListener("click", () => {
      ctx.pushEvent("delete_comment", { id: comment.id })
    })

    actions.appendChild(editBtn)
    actions.appendChild(deleteBtn)
    header.appendChild(actions)
  }

  const body = document.createElement("div")
  body.className = "comment-body"
  const env = {}
  if (ctx && ctx.rawContent && comment.start_line && comment.end_line && !comment.side) {
    env.originalLines = ctx.rawContent.split('\n').slice(comment.start_line - 1, comment.end_line)
  }
  body.innerHTML = commentMd.render(comment.body, env)

  card.appendChild(header)
  card.appendChild(body)
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
      cancelComment(formObj, ctx)
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
  submitBtn.textContent = "Submit"
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
      cancelComment(formObj, ctx)
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
  wrapper.appendChild(form)

  requestAnimationFrame(() => textarea.focus())
  return wrapper
}

function submitNewComment(body, formObj, ctx) {
  if (!body.trim()) return
  clearDraft(ctx.reviewToken, formObj)
  ctx.pushEvent("add_comment", {
    start_line: formObj.startLine,
    end_line: formObj.endLine,
    body: body.trim(),
    file_path: formObj.filePath || null,
  })
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

function cancelComment(formObj, ctx) {
  removeForm(ctx, formObj.formKey)
  if (ctx.activeForms.length === 0) {
    ctx.selectionStart = null
    ctx.selectionEnd = null
    ctx.focusedBlockIndex = -1
  }
  render(ctx)
}

function insertSuggestion(textarea, formObj, ctx) {
  let rawContent = ctx.rawContent
  if (formObj.filePath && ctx.multiFile) {
    const file = ctx.files.find(f => f.path === formObj.filePath)
    if (file) rawContent = file.content
  }
  const lines = rawContent.split("\n").slice(formObj.startLine - 1, formObj.endLine)
  const suggestion = "```suggestion\n" + lines.join("\n") + "\n```"
  const start = textarea.selectionStart
  const end = textarea.selectionEnd
  textarea.value = textarea.value.substring(0, start) + suggestion + textarea.value.substring(end)
  const cursorPos = start + "```suggestion\n".length
  textarea.selectionStart = cursorPos
  textarea.selectionEnd = cursorPos + lines.join("\n").length
  textarea.focus()
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

  if (items.length === 0) {
    toggleBtn.style.display = "none"
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

// ---- Comments panel helpers -------------------------------------------------

function renderCommentsPanel(ctx) {
  const panel = ctx._commentsPanel
  if (!panel) return
  const body = panel.querySelector('.comments-panel-body')
  body.innerHTML = ''

  if (ctx.comments.length === 0) {
    body.innerHTML = '<div class="comments-panel-empty">No comments yet</div>'
    return
  }

  const sorted = [...ctx.comments].sort((a, b) => a.start_line - b.start_line)

  function renderCommentCard(comment, filePath) {
    const card = document.createElement('div')
    card.className = 'comments-panel-card'

    const isOwn = comment.author_identity === ctx.identity
    const authorLabel = isOwn ? 'You' : (comment.author_identity || '?').slice(0, 6)
    const lineRef = comment.start_line === comment.end_line
      ? `Line ${comment.start_line}`
      : `Lines ${comment.start_line}\u2013${comment.end_line}`

    const header = document.createElement('div')
    header.className = 'comments-panel-card-header'
    header.textContent = `${authorLabel} \u00b7 ${lineRef}`
    if (comment.review_round >= 1) {
      const roundBadge = document.createElement('span')
      const rc = comment.review_round === ctx.reviewRound ? ' round-current' : comment.review_round === ctx.reviewRound - 1 ? ' round-latest' : ''
      roundBadge.className = 'comment-round-badge' + rc
      roundBadge.textContent = 'R' + comment.review_round
      header.appendChild(document.createTextNode(' '))
      header.appendChild(roundBadge)
    }

    const bodyEl = document.createElement('div')
    bodyEl.className = 'comments-panel-card-body'
    const env = {}
    if (comment.start_line && comment.end_line && !comment.side) {
      let fileContent = ctx.rawContent
      if (ctx.multiFile && filePath) {
        const file = ctx.files.find(f => f.path === filePath)
        if (file) fileContent = file.content
      }
      if (fileContent) {
        env.originalLines = fileContent.split('\n').slice(comment.start_line - 1, comment.end_line)
      }
    }
    bodyEl.innerHTML = commentMd.render(comment.body, env)

    card.appendChild(header)
    card.appendChild(bodyEl)
    card.addEventListener('click', () => {
      if (filePath) {
        const section = document.getElementById('file-section-' + CSS.escape(filePath))
        if (section && !section.open) section.open = true
      }
      scrollToInlineComment(comment, ctx)
    })
    return card
  }

  if (ctx.multiFile) {
    // Group by file_path
    const grouped = {}
    for (const c of sorted) {
      const fp = c.file_path || ''
      if (!grouped[fp]) grouped[fp] = []
      grouped[fp].push(c)
    }

    for (const file of ctx.files) {
      const fileComments = grouped[file.path]
      if (!fileComments || fileComments.length === 0) continue

      const fileHeader = document.createElement('div')
      fileHeader.className = 'comments-panel-file-header'
      fileHeader.textContent = file.path
      body.appendChild(fileHeader)

      for (const c of fileComments) {
        body.appendChild(renderCommentCard(c, file.path))
      }
    }
  } else {
    for (const comment of sorted) {
      body.appendChild(renderCommentCard(comment, null))
    }
  }
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

function updateTocPosition(ctx) {
  const toc = document.getElementById('crit-toc')
  const panel = ctx._commentsPanel
  if (!toc || !panel) return
  const panelOpen = panel.classList.contains('comments-panel-open')
  toc.style.right = panelOpen ? (panel.offsetWidth + 16) + 'px' : ''
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
  updateTocPosition(ctx)
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
    ctx.reviewRound = parseInt(ctx.el.dataset.reviewRound || "0", 10)
    ctx.multiFile = ctx.el.dataset.multiFile === 'true'
    ctx.files = []
    ctx.singleFilePath = null
    ctx.focusedFilePath = null
    ctx.treeFolderState = {}

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

    ctx.lineBlocks = buildLineBlocks(md, rawContent)

    // Build table of contents
    const tocEl = document.getElementById("crit-toc")
    const tocToggleBtn = document.getElementById("crit-toc-toggle")
    const tocItems = extractTocItems(md, rawContent)
    if (tocEl && tocToggleBtn) {
      buildToc(tocEl, tocToggleBtn, tocItems)
      const saved = localStorage.getItem("crit-toc")
      if (saved === "open" || (saved === null && window.innerWidth > 1200)) {
        tocEl.classList.remove("crit-toc-hidden")
      }
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
        updateTocActive(tocItems)
      })
    }
    window.addEventListener("scroll", ctx._scrollHandler, { passive: true })

    // Keyboard shortcuts overlay
    const shortcutsOverlay = document.createElement('div')
    shortcutsOverlay.className = 'shortcuts-overlay'
    shortcutsOverlay.innerHTML = `
      <div class="shortcuts-dialog">
        <h3>Keyboard Shortcuts</h3>
        <table class="shortcuts-table">
          <tr><td><kbd>j</kbd></td><td>Next block</td></tr>
          <tr><td><kbd>k</kbd></td><td>Previous block</td></tr>
          <tr><td><kbd>c</kbd></td><td>Comment on focused block</td></tr>
          <tr><td><kbd>e</kbd></td><td>Edit comment on focused block</td></tr>
          <tr><td><kbd>d</kbd></td><td>Delete comment on focused block</td></tr>
          <tr><td><kbd>t</kbd></td><td>Toggle table of contents</td></tr>
          <tr><td><kbd>Shift</kbd>+<kbd>C</kbd></td><td>Toggle comments panel</td></tr>
          <tr><td><kbd>Ctrl</kbd>+<kbd>Enter</kbd></td><td>Submit comment</td></tr>
          <tr><td><kbd>Esc</kbd></td><td>Cancel / clear focus</td></tr>
          <tr><td><kbd>?</kbd></td><td>Toggle this help</td></tr>
        </table>
      </div>
    `
    shortcutsOverlay.addEventListener('click', (e) => {
      if (e.target === shortcutsOverlay) shortcutsOverlay.classList.remove('visible')
    })
    document.body.appendChild(shortcutsOverlay)
    ctx._shortcutsOverlay = shortcutsOverlay

    const shortcutsBtn = document.getElementById('shortcuts-btn')
    if (shortcutsBtn) {
      shortcutsBtn.addEventListener('click', () => {
        ctx._shortcutsOverlay.classList.toggle('visible')
      })
    }

    // Comments panel
    const commentsPanel = document.createElement('div')
    commentsPanel.className = 'comments-panel'
    commentsPanel.innerHTML = `
      <div class="comments-panel-header">
        <span>Comments</span>
        <button title="Close">\u00d7</button>
      </div>
      <div class="comments-panel-body"></div>
    `
    commentsPanel.querySelector('.comments-panel-header button').addEventListener('click', () => {
      commentsPanel.classList.remove('comments-panel-open')
      updateTocPosition(ctx)
    })
    const mainLayout = document.getElementById('crit-main-layout')
    mainLayout.appendChild(commentsPanel)
    ctx._commentsPanel = commentsPanel

    // Wire comment count as panel toggle
    const commentCountEl = document.getElementById('comment-count')
    if (commentCountEl) {
      commentCountEl.addEventListener('click', () => toggleCommentsPanel(ctx))
    }

    // Show loading until server sends init
    ctx.el.innerHTML = '<div class="crit-loading">Loading comments…</div>'

    ctx.handleEvent("init", ({ comments, display_name, files }) => {
      ctx.displayName = display_name || null
      ctx.comments = comments

      if (files && files.length > 1) {
        ctx.multiFile = true
        ctx.files = files.map(f => ({
          path: f.path,
          content: f.content,
          position: f.position,
          fileType: isCodeFile(f.path) ? 'code' : 'markdown',
          lineBlocks: isCodeFile(f.path)
            ? buildCodeLineBlocks(f.content, f.path)
            : buildLineBlocks(md, f.content),
          comments: comments.filter(c => c.file_path === f.path),
          collapsed: false,
          viewed: false,
        }))
        restoreViewedState(ctx)
      } else if (files && files.length === 1) {
        const f = files[0]
        ctx.rawContent = f.content
        ctx.singleFilePath = f.path
        ctx.lineBlocks = isCodeFile(f.path)
          ? buildCodeLineBlocks(f.content, f.path)
          : buildLineBlocks(md, f.content)
        // Rebuild TOC with actual content (mount ran before content arrived)
        const tocEl = document.getElementById("crit-toc")
        const tocToggleBtn = document.getElementById("crit-toc-toggle")
        if (tocEl && tocToggleBtn) {
          buildToc(tocEl, tocToggleBtn, extractTocItems(md, f.content))
        }
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

    ctx.handleEvent("comments_updated", ({ comments }) => {
      ctx.comments = comments
      if (ctx.multiFile) {
        // Re-distribute comments to files
        for (const f of ctx.files) {
          f.comments = comments.filter(c => c.file_path === f.path)
        }
      }
      // Preserve any open form
      render(ctx)
      if (ctx._commentsPanel?.classList.contains('comments-panel-open')) {
        renderCommentsPanel(ctx)
      }
    })

    ctx._keydownHandler = (e) => {
      const tag = e.target.tagName
      if (tag === 'TEXTAREA' || tag === 'INPUT' || e.target.isContentEditable) {
        // Textarea keydown is handled by per-form handlers with stopPropagation
        return
      }
      // Allow Shift (for Shift+C) but block other modifiers
      if (e.metaKey || e.ctrlKey || e.altKey) return

      // Shortcuts overlay
      if (e.key === '?') {
        e.preventDefault()
        ctx._shortcutsOverlay.classList.toggle('visible')
        return
      }
      if (ctx._shortcutsOverlay.classList.contains('visible')) {
        if (e.key === 'Escape') {
          e.preventDefault()
          ctx._shortcutsOverlay.classList.remove('visible')
        }
        return
      }

      // Comments panel toggle
      if (e.key === 'C' && e.shiftKey) {
        e.preventDefault()
        toggleCommentsPanel(ctx)
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
            c.author_identity === ctx.identity &&
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
            c.author_identity === ctx.identity &&
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
            cancelComment(ctx.activeForms[ctx.activeForms.length - 1], ctx)
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
    if (this._shortcutsOverlay) {
      this._shortcutsOverlay.remove()
    }
    if (this._commentsPanel) {
      this._commentsPanel.remove()
    }
  },
}
