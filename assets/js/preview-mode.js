// PreviewMode hook — host chrome for shareable preview reviews.
//
// Ports crit local's live-mode chrome (iframe pane, viewport presets,
// Navigate/Pin toggle, agent postMessage bridge) into a single Phoenix hook.
// The comment SIDE PANEL — panel shell, cards, replies, resolve/reply, resolved
// styling — is NOT rebuilt here: it reuses the SAME shared module files mode
// uses (comments-panel.js + the .comments-panel CSS). This hook only supplies
// the iframe/agent machinery and a preview adapter that feeds DOM-anchored pins
// into the shared card renderer.
//
// Header parity with crit local: the viewport + mode toggles are injected into
// the existing right-aligned header (#crit-preview-controls, gated @preview?),
// before #settingsToggle — mirroring crit live-mode.js — instead of a separate
// left chrome bar. The comments panel is toggled by the header comment-count
// button via the crit:toggle-comments dispatch (same as files mode).
//
// The agent (vendored verbatim into priv/static/preview-agent/) is injected into
// the iframe HTML by raw_controller and speaks the postMessage protocol defined
// in crit/frontend/agent-protocol.js — message-type strings here are copied
// EXACTLY from that file (do not invent names).
//
// TRANSPORT — crit uses REST /api/comments + SSE. crit-web uses LiveView:
//   receive: this.handleEvent("init" | "comment_added" | "comment_resolved" |
//            "comment_updated" | "comment_deleted" | "reply_added" |
//            "reply_updated" | "reply_deleted" | "comments_full_sync", ...)
//   send:    this.pushEvent("add_comment", {body, scope:"file", dom_anchor,
//            file_path}), this.pushEvent("resolve_comment", {id, resolved}),
//            this.pushEvent("add_reply", {comment_id, body}).

import { renderCommentCard, attachSidebarResizeHandle, escapeHtml, startInlineBodyEdit } from "./comments-panel"
import { createSettingsPanel } from "./settings-panel"

// Preview-mode keyboard shortcuts (the shared settings overlay's Shortcuts tab).
// Preview's interaction model is the Navigate/Pin header toggle + composer, so
// the list is short and honest (no vim keys like files mode).
const PREVIEW_SHORTCUT_GROUPS = [
  { label: "Commenting", shortcuts: [
    { key: "<kbd>Ctrl</kbd>+<kbd>Enter</kbd>", action: "Submit the open comment or reply" },
    { key: "<kbd>Esc</kbd>", action: "Cancel the open composer or reply" },
  ]},
]

// Chrome → Agent message types (copied verbatim from agent-protocol.js C2A).
const C2A = {
  SET_MODE: "set-mode",
  SET_PINS: "set-pins",
  SET_VIEWPORT: "set-viewport",
  SET_MARKER_TABINDEX: "set-marker-tabindex",
  FLASH_MARKER: "flash-marker",
  KEEP_HIGHLIGHT: "keep-highlight",
  CLEAR_HIGHLIGHT: "clear-highlight",
}

// Agent → Chrome message types (copied verbatim from agent-protocol.js A2C).
const A2C = {
  AGENT_READY: "agent-ready",
  AGENT_ERROR: "agent-error",
  SELECTION: "selection",
  PIN_CLICKED: "pin-clicked",
  FOCUS_STATE: "focus-state",
}

// Viewport presets — mirrors crit live-mode.js VIEWPORTS.
const VIEWPORTS = [
  { key: "mobile", label: "Mobile", w: 390, h: 844 },
  { key: "tablet", label: "Tablet", w: 768, h: 1024 },
  { key: "desktop", label: "Desktop", w: 1280, h: 800 },
  { key: "fit", label: "Fit", w: 0, h: 0 },
]

// Batched pin sender — port of crit live-mode.queue.js makeAgentSender. Holds
// messages until the agent reports ready, then flushes in order. set-pins is
// re-sent on every comment change, so this guarantees the agent never misses
// the pin set if it boots after the first push.
function makeAgentSender(post) {
  let ready = false
  const queue = []
  return {
    send(msg) {
      if (!ready) {
        queue.push(msg)
        return
      }
      post(msg)
    },
    markReady() {
      ready = true
      while (queue.length) post(queue.shift())
    },
    isReady() {
      return ready
    },
  }
}

export const PreviewMode = {
  mounted() {
    this.token = this.el.dataset.token
    this.baseUrl = (this.el.dataset.baseUrl || "").replace(/\/$/, "")
    this.canComment = this.el.dataset.canComment === "true"
    // Viewer identity (server-rendered, same as files mode's #document-renderer)
    // so the panel can gate edit/delete/resolve to the comment's author.
    this.identity = this.el.dataset.identity || ""
    this.userId = this.el.dataset.userId || ""
    this.reviewOwnerId = this.el.dataset.reviewOwnerId || ""

    // State — mirrors window.crit.live state in crit live-mode.
    this.comments = []
    this.files = []
    this.displayName = ""
    this.isAdmin = false
    this.mode = "navigate"
    this.viewport = { key: "desktop", w: 1280, h: 800 }
    this.htmlFile = "index.html"
    this.composerEl = null
    this.pendingAnchor = null
    // Per-comment collapse state + pin-number lookup, consumed by the shared
    // card renderer via the preview adapter.
    this.collapseOverrides = {}
    this.pinNumbers = new Map()
    this.activeFilter = "all" // all | open | resolved (panel filter pills)

    this.buildShell()
    this.buildHeaderControls()

    // Shared settings overlay (gear in the header) — theme + about, plus a
    // preview-specific shortcuts tab. Content-width and hide-resolved are
    // files-mode concerns, so preview omits them.
    this.settings = createSettingsPanel({
      showWidth: false,
      showHideResolved: false,
      shortcutGroups: PREVIEW_SHORTCUT_GROUPS,
    })

    // Agent bridge. The agent posts from the iframe's content window; we only
    // accept messages whose source is our iframe and whose origin is ours
    // (preview is served same-origin from /r/:token/raw/...).
    this.sender = makeAgentSender((msg) => this.postToAgent(msg))
    this.onMessage = (event) => this.handleAgentMessage(event)
    window.addEventListener("message", this.onMessage)

    // Header comment-count button toggles the panel via JS.dispatch (survives
    // LiveView patches), same contract as files mode.
    this.onToggleComments = () => this.togglePanel()
    this.el.addEventListener("crit:toggle-comments", this.onToggleComments)

    // LiveView → client transport. init carries review_type + files + comments;
    // the delta events mirror ReviewLive's push_event names exactly.
    this.handleEvent("init", (payload) => this.handleInit(payload))
    this.handleEvent("comment_added", ({ comment }) => this.upsertComment(comment))
    this.handleEvent("comment_updated", (p) => this.patchComment(p.id, { body: p.body, updated_at: p.updated_at }))
    this.handleEvent("comment_resolved", (p) => this.patchComment(p.id, { resolved: p.resolved }))
    this.handleEvent("comment_deleted", ({ id }) => this.removeComment(id))
    this.handleEvent("reply_added", ({ parent_id, reply }) => this.addReply(parent_id, reply))
    this.handleEvent("reply_updated", (p) => this.patchReply(p.parent_id, p.id, { body: p.body }))
    this.handleEvent("reply_deleted", ({ parent_id, id }) => this.removeReply(parent_id, id))
    this.handleEvent("comments_full_sync", ({ comments }) => {
      this.comments = comments || []
      this.afterCommentsChanged()
    })
    this.handleEvent("policy_changed", ({ can_comment }) => {
      this.canComment = !!can_comment
      this.renderPanel()
    })
  },

  destroyed() {
    if (this.onMessage) window.removeEventListener("message", this.onMessage)
    if (this.onResize) window.removeEventListener("resize", this.onResize)
    if (this.onToggleComments) this.el.removeEventListener("crit:toggle-comments", this.onToggleComments)
    if (this.settings) this.settings.destroy()
    if (this._highlightTimer) { clearTimeout(this._highlightTimer); this._highlightTimer = null }
    const controls = document.getElementById("crit-preview-controls")
    if (controls) controls.innerHTML = ""
    this.closeComposer()
  },

  // ---- Shell construction --------------------------------------------------
  // iframe pane + the SHARED toggle-able comments panel (same .comments-panel
  // markup/CSS files mode uses), laid out as a flex row. The panel is hidden
  // until the header comment-count button opens it (crit:toggle-comments).

  buildShell() {
    this.el.classList.add("crit-preview-container")
    this.el.innerHTML = [
      '<div class="crit-preview-body">',
      '  <div class="crit-preview-iframe-pane">',
      '    <div class="crit-preview-iframe-frame" id="critPreviewFrame">',
      '      <iframe id="critPreviewIframe" title="Preview" referrerpolicy="no-referrer"></iframe>',
      "    </div>",
      "  </div>",
      '  <div class="sidebar-resize-handle" id="commentsPanelResizer" role="separator" tabindex="0" aria-orientation="vertical" aria-label="Resize comments panel"></div>',
      '  <aside class="comments-panel" id="commentsPanel" aria-label="Comments">',
      '    <div class="comments-panel-header">',
      '      <div class="comments-panel-header-row1">',
      '        <div class="comments-panel-header-left">',
      '          <span class="comments-panel-title">Comments</span>',
      '          <span class="comments-panel-count-badge" id="commentsPanelCountBadge">0</span>',
      "        </div>",
      '        <div class="comments-panel-header-actions">',
      '          <button class="comments-panel-close" title="Close comments panel" aria-label="Close comments panel">&#x2715;</button>',
      "        </div>",
      "      </div>",
      '      <div class="comments-panel-header-row2">',
      '        <div class="comments-filter-toggle crit-diff-mode-toggle" id="commentsFilterPill" role="radiogroup" aria-label="Filter comments">',
      '          <button class="crit-toggle-btn crit-toggle-btn--active" data-filter="all" role="radio" aria-checked="true" tabindex="0">All <span class="filter-count">0</span></button>',
      '          <button class="crit-toggle-btn" data-filter="open" role="radio" aria-checked="false" tabindex="-1">Open <span class="filter-count">0</span></button>',
      '          <button class="crit-toggle-btn" data-filter="resolved" role="radio" aria-checked="false" tabindex="-1">Resolved <span class="filter-count">0</span></button>',
      "        </div>",
      '        <button class="comments-panel-expand-all" id="commentsPanelExpandAll">Expand all</button>',
      "      </div>",
      "    </div>",
      '    <div class="comments-panel-body" id="critPreviewPanelBody"></div>',
      "  </aside>",
      "</div>",
    ].join("")

    this.frame = this.el.querySelector("#critPreviewFrame")
    this.iframe = this.el.querySelector("#critPreviewIframe")
    this.iframePane = this.el.querySelector(".crit-preview-iframe-pane")
    this.panel = this.el.querySelector("#commentsPanel")
    this.panelBody = this.el.querySelector("#critPreviewPanelBody")
    this.countBadge = this.el.querySelector("#commentsPanelCountBadge")
    this.resizer = this.el.querySelector("#commentsPanelResizer")

    this.panel.querySelector(".comments-panel-close").addEventListener("click", () => this.closePanel())

    // Filter pills (All / Open / Resolved) — radiogroup with roving tabindex,
    // mirroring files mode's panel header. Counts update on every render.
    this.filterPill = this.panel.querySelector("#commentsFilterPill")
    this.filterPill.addEventListener("click", (e) => {
      const btn = e.target.closest(".crit-toggle-btn")
      if (btn) this.applyFilter(btn, false)
    })
    this.filterPill.addEventListener("keydown", (e) => {
      const btns = Array.from(this.filterPill.querySelectorAll(".crit-toggle-btn"))
      const i = btns.findIndex((b) => b === document.activeElement)
      if (i === -1) return
      let next = null
      if (e.key === "ArrowRight" || e.key === "ArrowDown") next = (i + 1) % btns.length
      else if (e.key === "ArrowLeft" || e.key === "ArrowUp") next = (i - 1 + btns.length) % btns.length
      else if (e.key === "Home") next = 0
      else if (e.key === "End") next = btns.length - 1
      else return
      e.preventDefault()
      this.applyFilter(btns[next], true)
    })

    // Expand all / Collapse all.
    this.expandAllBtn = this.panel.querySelector("#commentsPanelExpandAll")
    this.expandAllBtn.addEventListener("click", () => this.toggleExpandAll())

    // Drag-to-resize the panel — same shared handle files mode uses.
    const savedWidth = parseInt(localStorage.getItem("crit-comments-panel-width") || "", 10)
    if (Number.isFinite(savedWidth) && savedWidth >= 300) this.panel.style.width = savedWidth + "px"
    attachSidebarResizeHandle(this.resizer, this.panel, {
      storageKey: "crit-comments-panel-width", min: 300, edge: "left", step: 16,
    })

    this.renderPanel()
    // Comments are the point of a shared preview, so the panel starts open
    // (the header comment-count button still toggles it closed/open).
    this.openPanel()
  },

  // Inject viewport + mode toggles into the right-aligned header, mirroring
  // crit local's live-mode.js (which inserts them before #settingsToggle). The
  // server renders an empty #crit-preview-controls (phx-update=ignore) so these
  // hook-built toggles survive LiveView patches.
  buildHeaderControls() {
    const controls = document.getElementById("crit-preview-controls")
    if (!controls) return
    controls.innerHTML = [
      '<div class="crit-diff-mode-toggle" id="critPreviewViewport" role="group" aria-label="Viewport size"></div>',
      '<div class="crit-diff-mode-toggle" id="critPreviewMode" role="group" aria-label="Interaction mode"></div>',
    ].join("")
    this.viewportToggle = controls.querySelector("#critPreviewViewport")
    this.modeToggle = controls.querySelector("#critPreviewMode")
    this.buildViewportToggle()
    this.buildModeToggle()
  },

  buildViewportToggle() {
    this.viewportToggle.innerHTML = VIEWPORTS.map((v) => {
      const active = v.key === this.viewport.key
      return (
        '<button type="button" class="crit-toggle-btn' +
        (active ? " crit-toggle-btn--active" : "") +
        '" data-viewport="' + v.key +
        '" aria-pressed="' + (active ? "true" : "false") +
        '" title="' + escapeHtml(v.label) + '">' +
        escapeHtml(v.label) +
        "</button>"
      )
    }).join("")

    this.viewportToggle.addEventListener("click", (e) => {
      const btn = e.target.closest(".crit-toggle-btn")
      if (!btn) return
      const vp = VIEWPORTS.find((v) => v.key === btn.dataset.viewport)
      if (vp) this.applyViewport(vp)
    })

    // Stored so destroyed() can remove it — the hook is re-mountable (navigating
    // between two preview reviews), and an anonymous listener would leak a stale
    // `this` on every remount. Mirrors document-renderer.js's resize cleanup.
    this.onResize = () => {
      if (this.viewport.key === "fit") this.applyViewport(VIEWPORTS.find((v) => v.key === "fit"))
    }
    window.addEventListener("resize", this.onResize)
  },

  applyViewport(vp) {
    let w, h
    if (vp.key === "fit") {
      const rect = this.iframePane.getBoundingClientRect()
      w = Math.max(320, Math.floor(rect.width - 32))
      h = Math.max(240, Math.floor(rect.height - 32))
    } else {
      w = vp.w
      h = vp.h
    }
    this.viewport = { key: vp.key, w, h }
    this.frame.style.width = w + "px"
    this.frame.style.height = h + "px"

    if (this.viewportToggle) {
      this.viewportToggle.querySelectorAll(".crit-toggle-btn").forEach((b) => {
        const on = b.dataset.viewport === vp.key
        b.classList.toggle("crit-toggle-btn--active", on)
        b.setAttribute("aria-pressed", on ? "true" : "false")
      })
    }

    if (w > 0 && h > 0) this.sender.send({ type: C2A.SET_VIEWPORT, width: w, height: h })
  },

  buildModeToggle() {
    this.modeToggle.innerHTML = [
      { key: "navigate", label: "Navigate" },
      { key: "pin", label: "Pin" },
    ]
      .map((m) => {
        const active = m.key === this.mode
        // Pin stays disabled until agent-ready, mirroring crit live-mode's
        // installMode: a Pin click must never race the iframe→agent boot.
        const disabled = m.key === "pin"
        return (
          '<button type="button" class="crit-toggle-btn' +
          (active ? " crit-toggle-btn--active" : "") +
          '" data-mode="' + m.key +
          '" aria-pressed="' + (active ? "true" : "false") + '"' +
          (disabled ? ' disabled aria-disabled="true" title="Loading…"' : "") +
          ">" + escapeHtml(m.label) + "</button>"
        )
      })
      .join("")

    this.modeToggle.addEventListener("click", (e) => {
      const btn = e.target.closest(".crit-toggle-btn")
      if (!btn || btn.hasAttribute("disabled")) return
      const key = btn.dataset.mode
      if (key !== "navigate" && key !== "pin") return
      this.setMode(key)
    })
  },

  setMode(value) {
    const next = value === "pin" ? "pin" : "navigate"
    if (this.mode === next) return
    this.mode = next
    // Port of crit setMode: tell the agent the mode + flip marker tabindex so
    // Tab doesn't jump into the iframe while pinning.
    this.sender.send({ type: C2A.SET_MODE, value: next })
    this.sender.send({ type: C2A.SET_MARKER_TABINDEX, value: next === "pin" ? -1 : 0 })
    if (this.modeToggle) {
      this.modeToggle.querySelectorAll(".crit-toggle-btn").forEach((b) => {
        const on = b.dataset.mode === next
        b.classList.toggle("crit-toggle-btn--active", on)
        b.setAttribute("aria-pressed", on ? "true" : "false")
      })
    }
    if (next === "pin") this.openPanel()
    if (next === "navigate") this.closeComposer()
  },

  enablePinButton() {
    if (!this.modeToggle) return
    const pinBtn = this.modeToggle.querySelector('.crit-toggle-btn[data-mode="pin"]')
    if (!pinBtn) return
    pinBtn.removeAttribute("disabled")
    pinBtn.removeAttribute("aria-disabled")
    pinBtn.setAttribute("title", "Click an element in the preview to comment")
  },

  // ---- Panel open/close ----------------------------------------------------

  openPanel() {
    if (!this.panel) return
    this.panel.classList.add("comments-panel-open")
    this.syncToggleAria(true)
  },

  closePanel() {
    if (!this.panel) return
    this.panel.classList.remove("comments-panel-open")
    this.syncToggleAria(false)
  },

  togglePanel() {
    if (!this.panel) return
    if (this.panel.classList.contains("comments-panel-open")) this.closePanel()
    else this.openPanel()
  },

  syncToggleAria(isOpen) {
    const btn = document.getElementById("comment-count")
    if (btn) btn.setAttribute("aria-expanded", String(isOpen))
  },

  // ---- Filter pills + expand-all -------------------------------------------

  applyFilter(btn, focus) {
    if (!btn) return
    this.activeFilter = btn.dataset.filter || "all"
    this.filterPill.querySelectorAll(".crit-toggle-btn").forEach((b) => {
      const active = b === btn
      b.classList.toggle("crit-toggle-btn--active", active)
      b.setAttribute("aria-checked", active ? "true" : "false")
      b.setAttribute("tabindex", active ? "0" : "-1")
    })
    if (focus) btn.focus()
    this.renderPanel()
  },

  // Default collapse state matches the shared card: resolved collapsed, open
  // expanded — unless the user has toggled an override.
  isCardCollapsed(c) {
    const ov = this.collapseOverrides[c.id]
    return ov !== undefined ? ov : !!c.resolved
  },

  toggleExpandAll() {
    const pins = this.comments.filter((c) => c.dom_anchor)
    const anyCollapsed = pins.some((c) => this.isCardCollapsed(c))
    // If anything is collapsed, expand everything; otherwise collapse all.
    pins.forEach((c) => { this.collapseOverrides[c.id] = !anyCollapsed })
    this.renderPanel()
  },

  updateExpandAllLabel() {
    if (!this.expandAllBtn) return
    const pins = this.comments.filter((c) => c.dom_anchor)
    const anyCollapsed = pins.some((c) => this.isCardCollapsed(c))
    this.expandAllBtn.textContent = anyCollapsed ? "Expand all" : "Collapse all"
  },

  // ---- init + iframe src ---------------------------------------------------

  handleInit(payload) {
    this.comments = payload.comments || []
    this.files = payload.files || []
    this.displayName = payload.display_name || ""
    this.isAdmin = !!payload.is_admin
    if (typeof payload.can_comment === "boolean") this.canComment = payload.can_comment

    // iframe src is ROOT-RELATIVE so the iframe is always same-origin as the
    // parent page. An absolute Endpoint.url() (data-base-url) makes the iframe
    // cross-origin when browsed via a different host alias (e.g. 127.0.0.1 vs
    // localhost); the agent<->hook postMessage channel enforces an exact origin
    // match on both ends, so a mismatch silently blocks selection + comments.
    const firstHtml = this.files.find((f) => /\.html?$/i.test(f.path || ""))
    this.htmlFile = (firstHtml && firstHtml.path) || "index.html"
    this.iframe.src = "/r/" + encodeURIComponent(this.token) + "/raw/" + this.htmlFile

    this.applyViewport(this.viewport)
    this.afterCommentsChanged()
  },

  // ---- Agent postMessage bridge -------------------------------------------

  postToAgent(msg) {
    const iw = this.iframe && this.iframe.contentWindow
    if (!iw) return
    try {
      iw.postMessage(msg, window.location.origin)
    } catch (_) {
      /* noop */
    }
  },

  handleAgentMessage(event) {
    // Accept only messages from our iframe's content window. Preview is served
    // same-origin, so origin must match ours.
    if (!this.iframe || event.source !== this.iframe.contentWindow) return
    if (event.origin !== window.location.origin) return
    const msg = event.data
    if (!msg || typeof msg.type !== "string") return

    // Dispatch table — port of crit live-mode.dispatch.js makeMessageDispatcher.
    switch (msg.type) {
      case A2C.AGENT_READY:
        this.handleAgentReady()
        break
      case A2C.AGENT_ERROR:
        console.warn("[preview-mode] agent error:", msg.kind, msg.message)
        break
      case A2C.SELECTION:
        this.handleSelection(msg.dom_anchor)
        break
      case A2C.PIN_CLICKED:
        this.scrollPanelToCard(msg.pin_id)
        break
      case A2C.FOCUS_STATE:
        // No-op: crit uses this to suppress shortcuts while typing in the
        // iframe; preview-mode has no global shortcuts to suppress.
        break
      default:
        break
    }
  },

  handleAgentReady() {
    this.sender.markReady()
    this.enablePinButton()
    // Push current mode, viewport, and pins now that the agent can receive them.
    this.sender.send({ type: C2A.SET_MODE, value: this.mode })
    if (this.viewport.w > 0 && this.viewport.h > 0) {
      this.sender.send({ type: C2A.SET_VIEWPORT, width: this.viewport.w, height: this.viewport.h })
    }
    this.pushPins()
  },

  // set-pins payload: one entry per commentable pin (a comment with a
  // dom_anchor). Re-sent on every comment change. Mirrors crit's pin push.
  pushPins() {
    const pins = this.comments
      .filter((c) => c.dom_anchor)
      .map((c) => ({
        id: String(c.id),
        dom_anchor: c.dom_anchor,
        resolved: !!c.resolved,
      }))
    this.sender.send({ type: C2A.SET_PINS, pins })
  },

  // ---- Composer (selection → new comment) ----------------------------------

  handleSelection(anchor) {
    if (!anchor || !anchor.css_selector) return
    if (!this.canComment) return
    this.openComposer(anchor)
  },

  openComposer(anchor) {
    // closeComposer() nulls pendingAnchor, so set it AFTER closing any prior
    // composer — otherwise submitComposer sees a null anchor and silently
    // drops the comment (no pushEvent, nothing reaches the server).
    this.closeComposer()
    this.openPanel()
    this.pendingAnchor = anchor
    const el = document.createElement("div")
    el.className = "crit-preview-composer"
    el.setAttribute("role", "dialog")
    el.setAttribute("aria-label", "New preview comment")
    el.innerHTML = [
      '<div class="crit-preview-composer-meta">',
      '  <span class="crit-preview-composer-chip">' + escapeHtml(this.anchorLabel(anchor)) + "</span>",
      "</div>",
      '<textarea class="crit-preview-composer-body" rows="4" placeholder="Leave a comment… (Ctrl+Enter to submit, Escape to cancel)"></textarea>',
      '<div class="crit-preview-composer-error" hidden></div>',
      '<div class="crit-preview-composer-actions">',
      '  <button type="button" class="btn btn-sm crit-preview-composer-cancel">Cancel</button>',
      '  <button type="button" class="btn btn-sm btn-primary crit-preview-composer-save">Comment</button>',
      "</div>",
    ].join("")

    // Anchor the composer at the top of the panel so it never overlaps the
    // iframe content.
    this.panelBody.insertBefore(el, this.panelBody.firstChild)
    this.composerEl = el

    const textarea = el.querySelector(".crit-preview-composer-body")
    const errEl = el.querySelector(".crit-preview-composer-error")
    const save = () => this.submitComposer(textarea, errEl)
    el.querySelector(".crit-preview-composer-save").addEventListener("click", save)
    el.querySelector(".crit-preview-composer-cancel").addEventListener("click", () => this.closeComposer())
    textarea.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) {
        e.preventDefault()
        save()
      } else if (e.key === "Escape") {
        e.preventDefault()
        this.closeComposer()
      }
    })
    requestAnimationFrame(() => textarea.focus())
  },

  submitComposer(textarea, errEl) {
    const body = (textarea.value || "").trim()
    if (!body) {
      textarea.focus()
      return
    }
    // Capture the anchor before closeComposer() (below) nulls it.
    const anchor = this.pendingAnchor
    if (!anchor) return
    // start_line/end_line: ReviewLive's add_comment handler reads these (files
    // mode is line-anchored). DOM-anchored preview comments have no line, so
    // send 0/0 — the changeset only enforces > 0 when scope === "line".
    this.pushEvent("add_comment", {
      body,
      scope: "file",
      file_path: this.htmlFile,
      start_line: 0,
      end_line: 0,
      dom_anchor: anchor,
    })
    // The new comment arrives back via the comment_added push event, which
    // re-renders the panel and re-pushes pins. Just close the composer.
    this.closeComposer()
  },

  closeComposer() {
    if (this.composerEl && this.composerEl.parentNode) {
      this.composerEl.parentNode.removeChild(this.composerEl)
    }
    this.composerEl = null
    this.pendingAnchor = null
  },

  anchorLabel(anchor) {
    if (anchor && Array.isArray(anchor.tag_chain) && anchor.tag_chain.length) {
      return anchor.tag_chain[anchor.tag_chain.length - 1]
    }
    return "pin"
  },

  // ---- Comment list mutations (LiveView delta handlers) --------------------

  upsertComment(comment) {
    const idx = this.comments.findIndex((c) => String(c.id) === String(comment.id))
    if (idx >= 0) this.comments[idx] = comment
    else this.comments.push(comment)
    this.afterCommentsChanged()
  },

  patchComment(id, fields) {
    const c = this.comments.find((c) => String(c.id) === String(id))
    if (!c) return
    Object.assign(c, fields)
    this.afterCommentsChanged()
  },

  removeComment(id) {
    this.comments = this.comments.filter((c) => String(c.id) !== String(id))
    this.afterCommentsChanged()
  },

  addReply(parentId, reply) {
    const c = this.comments.find((c) => String(c.id) === String(parentId))
    if (!c) return
    c.replies = c.replies || []
    if (!c.replies.some((r) => String(r.id) === String(reply.id))) c.replies.push(reply)
    this.renderPanel()
  },

  patchReply(parentId, id, fields) {
    const c = this.comments.find((c) => String(c.id) === String(parentId))
    if (!c || !c.replies) return
    const r = c.replies.find((r) => String(r.id) === String(id))
    if (r) Object.assign(r, fields)
    this.renderPanel()
  },

  removeReply(parentId, id) {
    const c = this.comments.find((c) => String(c.id) === String(parentId))
    if (!c || !c.replies) return
    c.replies = c.replies.filter((r) => String(r.id) !== String(id))
    this.renderPanel()
  },

  // Re-render the panel AND re-push pins to the agent. crit live-mode does both
  // on every comment change so the markers stay in sync with the panel.
  afterCommentsChanged() {
    this.renderPanel()
    if (this.sender && this.sender.isReady()) this.pushPins()
  },

  // ---- Side panel (shared card renderer + preview adapter) -----------------

  // Maps preview state onto the shared comments-panel contract. Preview cards
  // are fully interactive (the panel is the only place comments live — there is
  // no inline document to scroll to), so resolve + reply render on every card.
  // Own-comment check, mirroring files mode's isOwnComment: by user id when the
  // viewer is authenticated, else by anonymous identity.
  isOwnComment(c) {
    if (this.userId) return c.user_id != null && String(c.user_id) === String(this.userId)
    return !!c.author_identity && c.author_identity === this.identity
  },

  isReviewOwner() {
    return !!this.userId && !!this.reviewOwnerId && String(this.userId) === String(this.reviewOwnerId)
  },

  cardAdapter() {
    return {
      // Resolve/edit/delete are gated to the comment's author (resolve also to
      // the review owner; delete also to admins) — matching files mode + crit
      // local, and enforced server-side. Offering resolve to everyone left the
      // button stuck-disabled for non-authors: the shared card disables it
      // optimistically, but the server rejects an unauthorised resolve without
      // echoing a state change, so it never re-enables.
      isOwn: (c) => this.isOwnComment(c),
      canResolve: (c) => this.isOwnComment(c) || this.isReviewOwner(),
      canDelete: (c) => this.isOwnComment(c) || this.isAdmin,
      displayName: this.displayName,
      collapseOverrides: this.collapseOverrides,
      showActions: () => true,
      showReplyComposer: () => this.canComment,
      markdownEnv: () => ({}),
      headerBadges: (c) => {
        const n = this.pinNumbers.get(String(c.id))
        if (!n) return []
        const badge = document.createElement("span")
        badge.className = "crit-preview-pin-badge"
        badge.setAttribute("aria-hidden", "true")
        badge.textContent = String(n)
        return [badge]
      },
      onResolve: (c, resolved) => this.pushEvent("resolve_comment", { id: c.id, resolved }),
      onDelete: (c) => this.pushEvent("delete_comment", { id: c.id }),
      onEditComment: (id, body) => this.pushEvent("edit_comment", { id, body }),
      onAddReply: (commentId, body) => this.pushEvent("add_reply", { comment_id: commentId, body }),
      onDeleteReply: (id) => this.pushEvent("delete_reply", { id }),
      onEditReply: (commentId, reply) => {
        const sel = window.CSS && CSS.escape ? CSS.escape(String(reply.id)) : reply.id
        const replyEl = this.panelBody.querySelector('[data-reply-id="' + sel + '"]')
        const bodyEl = replyEl && replyEl.querySelector(".reply-body")
        if (bodyEl) startInlineBodyEdit(bodyEl, reply.body, (v) => this.pushEvent("edit_reply", { id: reply.id, body: v }))
      },
      scheduleTimeout: (fn, ms) => setTimeout(fn, ms),
      onCardClick: (c) => this.flashPin(c),
    }
  },

  renderPanel() {
    if (!this.panelBody) return
    // Preserve an open composer across re-renders.
    const composer = this.composerEl
    if (composer && composer.parentNode === this.panelBody) {
      this.panelBody.removeChild(composer)
    }

    this.panelBody.innerHTML = ""
    if (composer) this.panelBody.appendChild(composer)

    const pins = this.comments.filter((c) => c.dom_anchor)
    const total = pins.length
    const openCount = pins.filter((c) => !c.resolved).length
    const resolvedCount = pins.filter((c) => c.resolved).length

    // Pin numbers are stable across filters (panel order = full pin order),
    // matching the marker numbers the agent assigns inside the iframe.
    this.pinNumbers = new Map()
    pins.forEach((c, i) => this.pinNumbers.set(String(c.id), i + 1))

    // Counts: total badge, header number, and per-pill counts.
    if (this.countBadge) this.countBadge.textContent = String(total)
    const headerCount = document.getElementById("commentCountNumber")
    if (headerCount) headerCount.textContent = total ? String(total) : ""
    if (this.filterPill) {
      this.filterPill.querySelectorAll(".crit-toggle-btn").forEach((b) => {
        const countEl = b.querySelector(".filter-count")
        if (!countEl) return
        const f = b.dataset.filter
        countEl.textContent = f === "open" ? openCount : f === "resolved" ? resolvedCount : total
      })
    }
    this.updateExpandAllLabel()

    if (total === 0) {
      const empty = document.createElement("div")
      empty.className = "comments-panel-empty"
      empty.innerHTML = this.canComment
        ? "No comments yet.<br>Switch to Pin mode and click an element to comment."
        : "No comments yet."
      this.panelBody.appendChild(empty)
      return
    }

    const visible = pins.filter((c) => {
      if (this.activeFilter === "open") return !c.resolved
      if (this.activeFilter === "resolved") return c.resolved
      return true
    })

    if (visible.length === 0) {
      const empty = document.createElement("div")
      empty.className = "comments-panel-empty"
      empty.textContent = this.activeFilter === "open" ? "No open comments" : "No resolved comments"
      this.panelBody.appendChild(empty)
      return
    }

    // Single-page preview: one file group keyed by the html file, mirroring
    // files mode's panel grouping but with a single group.
    const adapter = this.cardAdapter()
    const group = document.createElement("div")
    group.className = "comments-panel-file-group"
    const name = document.createElement("div")
    name.className = "comments-panel-file-name"
    name.textContent = "/" + this.htmlFile
    group.appendChild(name)
    const cards = document.createElement("div")
    cards.className = "comments-panel-file-cards"
    visible.forEach((c) => cards.appendChild(renderCommentCard(c, adapter)))
    group.appendChild(cards)
    this.panelBody.appendChild(group)
  },

  // ---- Pin highlight + flash (agent bridge) --------------------------------

  flashPin(comment) {
    if (!comment) return
    const anchor = comment.dom_anchor
    if (anchor && anchor.css_selector) {
      this.sender.send({ type: C2A.KEEP_HIGHLIGHT, selector: anchor.css_selector })
      if (this._highlightTimer) clearTimeout(this._highlightTimer)
      this._highlightTimer = setTimeout(() => {
        this.sender.send({ type: C2A.CLEAR_HIGHLIGHT })
        this._highlightTimer = null
      }, 1000)
    }
    this.sender.send({ type: C2A.FLASH_MARKER, pin_id: String(comment.id) })
  },

  scrollPanelToCard(pinId) {
    this.openPanel()
    const card = this.panelBody.querySelector(
      '.comment-card[data-comment-id="' + (window.CSS && CSS.escape ? CSS.escape(String(pinId)) : pinId) + '"]'
    )
    if (!card) return
    card.scrollIntoView({ behavior: "smooth", block: "center" })
    card.classList.remove("crit-preview-card-flash")
    void card.offsetWidth
    card.classList.add("crit-preview-card-flash")
    card.addEventListener(
      "animationend",
      () => card.classList.remove("crit-preview-card-flash"),
      { once: true }
    )
  },
}
