// Shared comments-panel rendering — used by BOTH files mode (document-renderer.js)
// and preview mode (preview-mode.js). Extracted so the two renderers stop
// duplicating the comment card, replies, reply composer, resolved styling, and
// the draggable sidebar resize handle.
//
// This module is PURE: it imports nothing from document-renderer or preview-mode
// and never reads global ctx. Each caller passes an `adapter` carrying only the
// mode-specific bits (permission predicates, LiveView callbacks, markdown env,
// per-mode header badges, card-click behaviour). Everything that is genuinely
// identical between the two modes — comment markdown (with @file refs +
// comment-ref chips), author badges, timestamps, the reply list, the reply
// composer, collapse behaviour, resolve/delete buttons — lives here once.
//
// LiveView event contract is unchanged: the adapter callbacks forward to the
// same pushEvent names the two renderers already used (resolve_comment,
// delete_comment, add_reply, delete_reply, edit_reply).

import markdownit from "markdown-it"
import hljs from "highlight.js"

// ---- Shared helpers ---------------------------------------------------------

const IDENTITY_HUES = [200, 140, 30, 260, 350, 90, 175, 315, 55, 220, 0, 160]

export function identityHue(identity) {
  if (!identity) return 200
  let hash = 0
  for (let i = 0; i < identity.length; i++) {
    hash = Math.imul(31, hash) + identity.charCodeAt(i) | 0
  }
  return IDENTITY_HUES[Math.abs(hash) % IDENTITY_HUES.length]
}

export function escapeHtml(str) {
  return String(str == null ? "" : str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
}

export function formatTime(isoStr) {
  if (!isoStr) return ""
  const d = new Date(isoStr)
  if (isNaN(d.getTime())) return ""
  return d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
}

export function authorColorIndex(author) {
  if (!author) return 0
  let hash = 0
  for (let i = 0; i < author.length; i++) {
    hash = ((hash << 5) - hash) + author.charCodeAt(i)
    hash |= 0
  }
  return Math.abs(hash) % 6
}

// ---- Comment markdown -------------------------------------------------------
// Single shared markdown-it instance so comment bodies render identically in
// both modes (this also fixes preview's old raw-textContent bug). document-
// renderer.js layers its files-mode-only ```suggestion fence rule onto this
// same instance at runtime; that rule is inert for preview comments.

export const commentMd = markdownit({
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

// ===== File Reference Inline Rule ===== (@path/to/file renders as a chip)
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

// Override code_inline so backtick-wrapped comment IDs render as the same chip.
const defaultCodeInline = commentMd.renderer.rules.code_inline || function(tokens, idx, options, env, self) {
  return self.renderToken(tokens, idx, options)
}
commentMd.renderer.rules.code_inline = function(tokens, idx, options, env, self) {
  const content = tokens[idx].content
  if (/^(c|r|rp)_[a-f0-9]{6,}$/.test(content)) {
    return '<span class="comment-ref comment-ref-code" tabindex="0" role="link" data-ref-id="' + escapeHtml(content) + '">' + escapeHtml(content) + '</span>'
  }
  return defaultCodeInline(tokens, idx, options, env, self)
}

// Turn `c_...` / `r_...` / `rp_...` ids in rendered text nodes into ref chips.
export function linkifyCommentRefsInDom(el) {
  const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT, null, false)
  const textNodes = []
  let node
  while ((node = walker.nextNode())) {
    if (node.parentNode.closest('code, pre, .comment-ref')) continue
    textNodes.push(node)
  }
  const re = /((?:c|r|rp)_[a-f0-9]{6,})/g
  textNodes.forEach(tn => {
    if (!re.test(tn.nodeValue)) { re.lastIndex = 0; return }
    re.lastIndex = 0
    const frag = document.createDocumentFragment()
    let last = 0, m
    while ((m = re.exec(tn.nodeValue)) !== null) {
      if (m.index > last) frag.appendChild(document.createTextNode(tn.nodeValue.slice(last, m.index)))
      const span = document.createElement('span')
      span.className = 'comment-ref'
      span.tabIndex = 0
      span.setAttribute('role', 'link')
      span.dataset.refId = m[1]
      span.textContent = m[1]
      frag.appendChild(span)
      last = m.index + m[0].length
    }
    if (last < tn.nodeValue.length) frag.appendChild(document.createTextNode(tn.nodeValue.slice(last)))
    tn.parentNode.replaceChild(frag, tn)
  })
}

// Render markdown into `el` and linkify comment-ref ids. `env` carries
// originalLines for the ```suggestion fence rule (files mode); {} for preview.
export function renderMarkdown(el, body, env) {
  el.innerHTML = commentMd.render(body || "", env || {})
  linkifyCommentRefsInDom(el)
}

// ---- SVG snippets (shared between modes) ------------------------------------

const SVG_COLLAPSE = '<svg viewBox="0 0 16 16" fill="currentColor" width="16" height="16"><path d="M12.78 5.22a.75.75 0 0 1 0 1.06l-4.25 4.25a.75.75 0 0 1-1.06 0L3.22 6.28a.75.75 0 0 1 1.06-1.06L8 8.94l3.72-3.72a.75.75 0 0 1 1.06 0Z"/></svg>'
const SVG_AUTHOR = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="comment-author-icon"><path fill-rule="evenodd" d="M18.685 19.097A9.723 9.723 0 0 0 21.75 12c0-5.385-4.365-9.75-9.75-9.75S2.25 6.615 2.25 12a9.723 9.723 0 0 0 3.065 7.097A9.716 9.716 0 0 0 12 21.75a9.716 9.716 0 0 0 6.685-2.653Zm-12.54-1.285A7.486 7.486 0 0 1 12 15a7.486 7.486 0 0 1 5.855 2.812A8.224 8.224 0 0 1 12 20.25a8.224 8.224 0 0 1-5.855-2.438ZM15.75 9a3.75 3.75 0 1 1-7.5 0 3.75 3.75 0 0 1 7.5 0Z" clip-rule="evenodd"/></svg>'
const SVG_DELETE = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/></svg>'
const SVG_EDIT = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z"/><path d="m15 5 4 4"/></svg>'
const SVG_RESOLVE = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>'
const SVG_UNRESOLVE = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12a9 9 0 0 1 9-9 9 9 0 0 1 6.36 2.64M21 12a9 9 0 0 1-9 9 9 9 0 0 1-6.36-2.64"/><polyline points="21 3 21 8 16 8"/><polyline points="3 21 3 16 8 16"/></svg>'

// ---- Author element (shared) ------------------------------------------------

function buildAuthorEl(c, adapter, { reply = false } = {}) {
  const isOwn = adapter.isOwn(c)
  if (c.author_display_name) {
    const badge = document.createElement('span')
    badge.className = 'comment-author-badge author-color-' + authorColorIndex(c.author_display_name)
    badge.textContent = '@' + c.author_display_name
    return badge
  }
  const author = document.createElement('span')
  author.className = 'comment-author' + (isOwn ? ' comment-author-you' : '')
  const fallback = reply ? (c.author_identity || '?').slice(0, 20) : 'anonymous'
  author.innerHTML = SVG_AUTHOR + (isOwn ? (adapter.displayName || 'You') : fallback)
  return author
}

// Swap a rendered body element for an inline edit textarea + Save/Cancel.
// Used for editing a comment body or a reply body. On Save the caller pushes the
// edit to the server, which echoes back an update that re-renders the card;
// Cancel restores the original rendered node.
export function startInlineBodyEdit(bodyEl, rawText, onSave) {
  // Guard a repeat click after the body was already swapped for a textarea:
  // the node is now detached, so replaceWith/insertAdjacentElement/focus would
  // be silent no-ops on a parentless element.
  if (!bodyEl || !bodyEl.isConnected) return
  const restoreNode = bodyEl
  const textarea = document.createElement('textarea')
  textarea.className = 'comment-textarea'
  textarea.value = rawText || ''
  textarea.rows = 3

  const actions = document.createElement('div')
  actions.className = 'reply-edit-actions'
  const saveBtn = document.createElement('button')
  saveBtn.className = 'btn btn-sm btn-primary'
  saveBtn.textContent = 'Save'
  const cancelBtn = document.createElement('button')
  cancelBtn.className = 'btn btn-sm'
  cancelBtn.textContent = 'Cancel'
  actions.appendChild(saveBtn)
  actions.appendChild(cancelBtn)

  restoreNode.replaceWith(textarea)
  textarea.insertAdjacentElement('afterend', actions)
  textarea.focus()

  function cancel() {
    actions.remove()
    textarea.replaceWith(restoreNode)
  }
  cancelBtn.addEventListener('click', function(e) { e.stopPropagation(); cancel() })
  saveBtn.addEventListener('click', function(e) {
    e.stopPropagation()
    const v = textarea.value.trim()
    if (!v) return
    onSave(v)
  })
  textarea.addEventListener('keydown', function(e) {
    if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) { e.preventDefault(); e.stopPropagation(); saveBtn.click() }
    if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); cancel() }
  })
}

// ---- Replies (read-only list) -----------------------------------------------

export function renderReplyList(comment, adapter) {
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
    const isOwnReply = adapter.isOwn(reply)
    replyMeta.appendChild(buildAuthorEl(reply, adapter, { reply: true }))
    const replyTime = document.createElement('span')
    replyTime.className = 'reply-time'
    replyTime.textContent = formatTime(reply.created_at)
    replyMeta.appendChild(replyTime)
    replyHeader.appendChild(replyMeta)

    const canDelete = adapter.canDelete(reply)
    if (isOwnReply || canDelete) {
      const replyActions = document.createElement('div')
      replyActions.className = 'reply-actions'

      if (isOwnReply && adapter.onEditReply) {
        const replyEditBtn = document.createElement('button')
        replyEditBtn.title = 'Edit'
        replyEditBtn.innerHTML = SVG_EDIT
        replyEditBtn.addEventListener('click', function(e) { e.stopPropagation(); adapter.onEditReply(comment.id, reply) })
        replyActions.appendChild(replyEditBtn)
      }

      if (canDelete) {
        const replyDeleteBtn = document.createElement('button')
        replyDeleteBtn.className = 'delete-btn'
        replyDeleteBtn.title = 'Delete'
        replyDeleteBtn.innerHTML = SVG_DELETE
        replyDeleteBtn.addEventListener('click', function(e) {
          e.stopPropagation()
          adapter.onDeleteReply(reply.id)
        })
        replyActions.appendChild(replyDeleteBtn)
      }

      replyHeader.appendChild(replyActions)
    }

    replyEl.appendChild(replyHeader)

    const replyBody = document.createElement('div')
    replyBody.className = 'reply-body'
    replyBody.dataset.rawBody = reply.body
    renderMarkdown(replyBody, reply.body)
    replyEl.appendChild(replyBody)

    repliesContainer.appendChild(replyEl)
  })
  return repliesContainer
}

// ---- Reply composer (expand-on-focus input -> textarea) ---------------------

export function createReplyInput(commentId, adapter) {
  const form = document.createElement('div')
  form.className = 'reply-form'

  const input = document.createElement('input')
  input.type = 'text'
  input.className = 'reply-input'
  input.placeholder = 'Write a reply…'
  form.appendChild(input)

  const textarea = document.createElement('textarea')
  textarea.className = 'reply-textarea'
  textarea.placeholder = 'Write a reply…'
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
    if (adapter.beforeReplyExpand) adapter.beforeReplyExpand()
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

  // Collapse on blur if empty (with delay to allow button clicks).
  const schedule = adapter.scheduleTimeout || ((fn, ms) => setTimeout(fn, ms))
  textarea.addEventListener('blur', function() {
    schedule(function() {
      if (form.classList.contains('expanded') && !textarea.value.trim() && !form.contains(document.activeElement)) {
        collapse()
      }
    }, 150)
  })

  submitBtn.addEventListener('click', function() {
    const body = textarea.value.trim()
    if (!body) return
    submitBtn.disabled = true
    adapter.onAddReply(commentId, body)
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

// ---- Comment card (side-panel) ----------------------------------------------
// Generalised from document-renderer's renderPanelCard. The adapter controls:
//   isOwn(c) / canResolve(c) / canDelete(c)        permission predicates
//   displayName                                    current viewer's name
//   collapseOverrides                              per-comment collapse store
//   markdownEnv(comment)                           {originalLines?} for fences
//   headerBadges(comment) -> [el]                  round/line-ref (files) | pin (preview)
//   showActions(comment) -> bool                   resolve/delete row on the card itself
//   showReplyComposer(comment) -> bool             inline reply box under the card
//   onResolve(c) / onDelete(c)                     LiveView mutations
//   onAddReply / onDeleteReply / onEditReply       reply mutations (forwarded to composer/list)
//   onCardClick(comment, event)                    files: scroll-to-source | preview: flash pin
//   wrapperClass / cardClass                       optional extra classes

export function renderCommentCard(comment, adapter) {
  const isResolved = !!comment.resolved

  const wrapper = document.createElement('div')
  wrapper.className = 'comment-block panel-comment-block' + (adapter.wrapperClass ? ' ' + adapter.wrapperClass : '')

  const card = document.createElement('div')
  card.className = 'comment-card' + (isResolved ? ' resolved-card' : '') + (adapter.cardClass ? ' ' + adapter.cardClass : '')
  card.dataset.commentId = comment.id

  // Collapse state — resolved cards default collapsed; open cards default open.
  const overrides = adapter.collapseOverrides || {}
  const isCollapsed = isResolved
    ? (overrides[comment.id] !== undefined ? overrides[comment.id] : true)
    : (overrides[comment.id] === true)
  if (isCollapsed) card.classList.add('collapsed')

  const header = document.createElement('div')
  header.className = 'comment-header'

  const headerLeft = document.createElement('div')
  headerLeft.className = 'comment-header-left'

  const collapseBtn = document.createElement('button')
  collapseBtn.className = 'comment-collapse-btn'
  collapseBtn.title = isCollapsed ? 'Expand comment' : 'Collapse comment'
  collapseBtn.innerHTML = SVG_COLLAPSE
  collapseBtn.addEventListener('click', function(e) {
    e.stopPropagation()
    card.classList.toggle('collapsed')
    overrides[comment.id] = card.classList.contains('collapsed')
    collapseBtn.title = card.classList.contains('collapsed') ? 'Expand comment' : 'Collapse comment'
  })
  headerLeft.appendChild(collapseBtn)

  headerLeft.appendChild(buildAuthorEl(comment, adapter))

  // Mode-specific badges (files: round + line-ref; preview: pin number).
  if (adapter.headerBadges) {
    for (const badge of adapter.headerBadges(comment)) {
      if (badge) headerLeft.appendChild(badge)
    }
  }

  // Time (last child of headerLeft — matches crit local).
  const time = document.createElement('span')
  time.className = 'comment-time'
  time.textContent = formatTime(comment.created_at)
  headerLeft.appendChild(time)

  header.appendChild(headerLeft)

  // bodyEl is assigned below; declared here so an edit button (built in the
  // actions row above the body) can close over it.
  let bodyEl

  if (adapter.showActions(comment)) {
    const actions = document.createElement('div')
    actions.className = 'comment-actions'

    if (adapter.canResolve(comment)) {
      const resolveBtn = document.createElement('button')
      resolveBtn.className = isResolved ? 'resolve-btn resolve-btn--active' : 'resolve-btn'
      resolveBtn.title = isResolved ? 'Unresolve' : 'Resolve'
      resolveBtn.innerHTML = isResolved
        ? SVG_UNRESOLVE + '<span>Unresolve</span>'
        : SVG_RESOLVE + '<span>Resolve</span>'
      resolveBtn.addEventListener('click', function(e) {
        e.stopPropagation()
        if (resolveBtn.disabled) return
        resolveBtn.disabled = true
        adapter.onResolve(comment, !isResolved)
      })
      actions.appendChild(resolveBtn)
    }

    if (adapter.onEditComment && adapter.isOwn(comment)) {
      const editBtn = document.createElement('button')
      editBtn.title = 'Edit'
      editBtn.innerHTML = SVG_EDIT
      editBtn.addEventListener('click', function(e) {
        e.stopPropagation()
        startInlineBodyEdit(bodyEl, comment.body, function(v) { adapter.onEditComment(comment.id, v) })
      })
      actions.appendChild(editBtn)
    }

    if (adapter.canDelete(comment)) {
      const deleteBtn = document.createElement('button')
      deleteBtn.className = 'delete-btn'
      deleteBtn.title = 'Delete'
      deleteBtn.innerHTML = SVG_DELETE
      deleteBtn.addEventListener('click', function(e) {
        e.stopPropagation()
        adapter.onDelete(comment)
      })
      actions.appendChild(deleteBtn)
    }

    if (actions.childElementCount > 0) header.appendChild(actions)
  }

  card.appendChild(header)

  bodyEl = document.createElement('div')
  bodyEl.className = 'comment-body'
  renderMarkdown(bodyEl, comment.body, adapter.markdownEnv ? adapter.markdownEnv(comment) : {})
  card.appendChild(bodyEl)

  if (comment.replies && comment.replies.length > 0) {
    card.appendChild(renderReplyList(comment, adapter))
  }

  if (adapter.showReplyComposer && adapter.showReplyComposer(comment)) {
    card.appendChild(createReplyInput(comment.id, adapter))
  }

  wrapper.appendChild(card)

  if (adapter.onCardClick) {
    wrapper.style.cursor = 'pointer'
    wrapper.addEventListener('click', function(e) {
      if (e.target.closest('button, a, input, textarea')) return
      adapter.onCardClick(comment, e)
    })
  }

  return wrapper
}

// ---- Draggable sidebar resize handle (shared) -------------------------------
// Pointer events + setPointerCapture: the handle keeps receiving move/up events
// even if the pointer leaves the window. Avoids the "stuck dragging" leak that
// document-level mousemove listeners suffer from. `cfg` = { storageKey, min,
// edge: 'left'|'right', step }.

export function attachSidebarResizeHandle(handle, target, cfg) {
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
