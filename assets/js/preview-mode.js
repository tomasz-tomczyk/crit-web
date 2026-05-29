// PreviewMode hook — host chrome for shareable preview reviews.
//
// Faithful port of crit local's live-mode chrome (crit/frontend/live-mode.js +
// its .toggle / .queue / .dispatch / .composer / .panel-render sub-modules) into
// a single Phoenix hook, the same way document-renderer.js ports crit's code-
// review app.js. The agent (vendored verbatim into priv/static/preview-agent/)
// is injected into the iframe HTML by raw_controller and speaks the postMessage
// protocol defined in crit/frontend/agent-protocol.js — message-type strings
// here are copied EXACTLY from that file (do not invent names).
//
// What is ported vs simplified, relative to crit live-mode:
//   PORTED  — iframe pane, viewport presets (Mobile/Tablet/Desktop/Fit) + set-
//             viewport dispatch, Navigate/Pin mode toggle gated on agent-ready
//             + set-mode dispatch, batched pin sender (queue until agent-ready),
//             selection → composer → create comment, pin-clicked → scroll panel
//             card, persistent side panel of pin cards (number badge, body,
//             author, resolve, reply), keep/clear-highlight + flash-marker on
//             card click, re-push set-pins on every comment change.
//   SIMPLIFIED / OUT OF SCOPE (crit has these; this task does not need them) —
//             reanchoring / drift recovery (pin-resolution-result, enter-
//             reanchor-mode), ancestor-selection menu, route changes / multi-
//             page proxy navigation (preview is a single static page), round
//             tooltips, SSE (LiveView pushes deltas instead), drag-resize of the
//             iframe, settings overlay. These are deliberate omissions.
//
// TRANSPORT — crit uses REST /api/comments + SSE. crit-web uses LiveView:
//   receive: this.handleEvent("init" | "comment_added" | "comment_resolved" |
//            "comment_updated" | "comment_deleted" | "reply_added" |
//            "reply_updated" | "reply_deleted" | "comments_full_sync", ...)
//   send:    this.pushEvent("add_comment", {body, scope:"file", dom_anchor,
//            file_path}), this.pushEvent("resolve_comment", {id, resolved}),
//            this.pushEvent("add_reply", {comment_id, body}).

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

function escapeHTML(str) {
  return String(str == null ? "" : str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;")
}

function formatTime(iso) {
  if (!iso) return ""
  const d = new Date(iso)
  if (isNaN(d.getTime())) return ""
  return d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
}

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

    this.buildShell()

    // Agent bridge. The agent posts from the iframe's content window; we only
    // accept messages whose source is our iframe and whose origin is ours
    // (preview is served same-origin from /r/:token/raw/...).
    this.sender = makeAgentSender((msg) => this.postToAgent(msg))
    this.onMessage = (event) => this.handleAgentMessage(event)
    window.addEventListener("message", this.onMessage)

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
    this.closeComposer()
  },

  // ---- Shell construction (port of live-mode.js buildShell) ----------------

  buildShell() {
    this.el.classList.add("crit-preview-container")
    this.el.innerHTML = [
      '<div class="crit-preview-chrome">',
      '  <div class="crit-preview-toggle-group" id="critPreviewViewport" role="group" aria-label="Viewport size"></div>',
      '  <div class="crit-preview-toggle-group" id="critPreviewMode" role="group" aria-label="Interaction mode"></div>',
      "</div>",
      '<div class="crit-preview-body">',
      '  <div class="crit-preview-iframe-pane">',
      '    <div class="crit-preview-iframe-frame" id="critPreviewFrame">',
      '      <iframe id="critPreviewIframe" title="Preview" referrerpolicy="no-referrer"></iframe>',
      "    </div>",
      "  </div>",
      '  <aside class="crit-preview-panel comments-panel" id="critPreviewPanel" aria-label="Comments">',
      '    <div class="crit-preview-panel-header">',
      '      <span class="crit-preview-panel-title">Comments</span>',
      '      <span class="crit-preview-panel-badge" id="critPreviewBadge">0</span>',
      "    </div>",
      '    <div class="crit-preview-panel-body comments-panel-body" id="critPreviewPanelBody"></div>',
      "  </aside>",
      "</div>",
    ].join("")

    this.viewportToggle = this.el.querySelector("#critPreviewViewport")
    this.modeToggle = this.el.querySelector("#critPreviewMode")
    this.frame = this.el.querySelector("#critPreviewFrame")
    this.iframe = this.el.querySelector("#critPreviewIframe")
    this.iframePane = this.el.querySelector(".crit-preview-iframe-pane")
    this.panelBody = this.el.querySelector("#critPreviewPanelBody")
    this.badge = this.el.querySelector("#critPreviewBadge")

    this.buildViewportToggle()
    this.buildModeToggle()
    this.renderPanel()
  },

  buildViewportToggle() {
    this.viewportToggle.innerHTML = VIEWPORTS.map((v) => {
      const active = v.key === this.viewport.key
      return (
        '<button type="button" class="crit-preview-toggle-btn' +
        (active ? " active" : "") +
        '" data-viewport="' +
        v.key +
        '" aria-pressed="' +
        (active ? "true" : "false") +
        '">' +
        escapeHTML(v.label) +
        "</button>"
      )
    }).join("")

    this.viewportToggle.addEventListener("click", (e) => {
      const btn = e.target.closest(".crit-preview-toggle-btn")
      if (!btn) return
      const vp = VIEWPORTS.find((v) => v.key === btn.dataset.viewport)
      if (vp) this.applyViewport(vp)
    })

    window.addEventListener("resize", () => {
      if (this.viewport.key === "fit") this.applyViewport(VIEWPORTS.find((v) => v.key === "fit"))
    })
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

    this.viewportToggle.querySelectorAll(".crit-preview-toggle-btn").forEach((b) => {
      const on = b.dataset.viewport === vp.key
      b.classList.toggle("active", on)
      b.setAttribute("aria-pressed", on ? "true" : "false")
    })

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
          '<button type="button" class="crit-preview-toggle-btn' +
          (active ? " active" : "") +
          '" data-mode="' +
          m.key +
          '" aria-pressed="' +
          (active ? "true" : "false") +
          '"' +
          (disabled ? ' disabled aria-disabled="true" title="Loading…"' : "") +
          ">" +
          escapeHTML(m.label) +
          "</button>"
        )
      })
      .join("")

    this.modeToggle.addEventListener("click", (e) => {
      const btn = e.target.closest(".crit-preview-toggle-btn")
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
    this.modeToggle.querySelectorAll(".crit-preview-toggle-btn").forEach((b) => {
      const on = b.dataset.mode === next
      b.classList.toggle("active", on)
      b.setAttribute("aria-pressed", on ? "true" : "false")
    })
    if (next === "navigate") this.closeComposer()
  },

  enablePinButton() {
    const pinBtn = this.modeToggle.querySelector('.crit-preview-toggle-btn[data-mode="pin"]')
    if (!pinBtn) return
    pinBtn.removeAttribute("disabled")
    pinBtn.removeAttribute("aria-disabled")
    pinBtn.setAttribute("title", "Click an element in the preview to comment")
  },

  // ---- init + iframe src ---------------------------------------------------

  handleInit(payload) {
    this.comments = payload.comments || []
    this.files = payload.files || []
    this.displayName = payload.display_name || ""
    this.isAdmin = !!payload.is_admin
    if (typeof payload.can_comment === "boolean") this.canComment = payload.can_comment

    // iframe src is ROOT-RELATIVE so the iframe is always same-origin as the
    // parent page. An absolute Endpoint.url() (data-base-url, e.g.
    // http://localhost:4000) makes the iframe cross-origin when the page is
    // browsed via a different host alias (e.g. http://127.0.0.1:4000); the
    // agent<->hook postMessage channel enforces an exact origin match on both
    // ends, so a mismatch silently blocks selection, the composer, and comments.
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

  // ---- Composer (port of live-mode.composer.js + open/submit flow) ---------

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
    this.pendingAnchor = anchor
    const el = document.createElement("div")
    el.className = "crit-preview-composer"
    el.setAttribute("role", "dialog")
    el.setAttribute("aria-label", "New preview comment")
    el.innerHTML = [
      '<div class="crit-preview-composer-meta">',
      '  <span class="crit-preview-composer-chip">' + escapeHTML(this.anchorLabel(anchor)) + "</span>",
      "</div>",
      '<textarea class="crit-preview-composer-body" rows="4" placeholder="Leave a comment… (Ctrl+Enter to submit, Escape to cancel)"></textarea>',
      '<div class="crit-preview-composer-error" hidden></div>',
      '<div class="crit-preview-composer-actions">',
      '  <button type="button" class="btn btn-sm crit-preview-composer-cancel">Cancel</button>',
      '  <button type="button" class="btn btn-sm btn-primary crit-preview-composer-save">Comment</button>',
      "</div>",
    ].join("")

    // Anchor the composer at the top of the panel so it never overlaps the
    // iframe content (simpler than crit's pointer-positioned overlay, which
    // depends on iframe-relative coordinates we don't compute here).
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

  // ---- Side panel (port of live-mode.panel-render.js, LiveView-adapted) ----

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
    this.badge.textContent = String(pins.length)

    if (pins.length === 0) {
      const empty = document.createElement("div")
      empty.className = "comments-panel-empty"
      empty.innerHTML = this.canComment
        ? "No comments yet.<br>Switch to Pin mode and click an element to comment."
        : "No comments yet."
      this.panelBody.appendChild(empty)
      return
    }

    // Group by route (preview is single-page, so all pins share one group keyed
    // by the html file) — mirrors crit's group-by-route panel layout.
    const group = document.createElement("div")
    group.className = "comments-panel-file-group"
    const name = document.createElement("div")
    name.className = "comments-panel-file-name"
    name.textContent = "/" + this.htmlFile
    group.appendChild(name)
    const cards = document.createElement("div")
    cards.className = "comments-panel-file-cards"
    group.appendChild(cards)

    pins.forEach((c, i) => cards.appendChild(this.buildCard(c, i + 1)))
    this.panelBody.appendChild(group)
  },

  buildCard(c, pinNumber) {
    const card = document.createElement("div")
    card.className = "comment-card crit-preview-card"
    card.dataset.commentId = String(c.id)
    card.tabIndex = 0
    if (c.resolved) card.dataset.resolved = "true"

    const head = document.createElement("div")
    head.className = "crit-preview-card-head"
    head.innerHTML =
      '<span class="crit-preview-pin-badge" aria-hidden="true">' +
      pinNumber +
      "</span>" +
      '<span class="crit-preview-card-author">' +
      escapeHTML(c.author || c.author_display_name || "Anonymous") +
      "</span>" +
      (c.resolved ? '<span class="crit-preview-card-resolved">resolved</span>' : "") +
      (c.created_at ? '<span class="crit-preview-card-time">' + escapeHTML(formatTime(c.created_at)) + "</span>" : "")
    card.appendChild(head)

    const body = document.createElement("div")
    body.className = "comment-card-body crit-preview-card-body"
    body.textContent = c.body || ""
    card.appendChild(body)

    // Replies.
    if (c.replies && c.replies.length) {
      const repliesEl = document.createElement("div")
      repliesEl.className = "crit-preview-card-replies"
      c.replies.forEach((r) => {
        const re = document.createElement("div")
        re.className = "crit-preview-reply"
        re.innerHTML =
          '<span class="crit-preview-reply-author">' +
          escapeHTML(r.author || r.author_display_name || "Anonymous") +
          "</span>"
        const rb = document.createElement("div")
        rb.className = "crit-preview-reply-body"
        rb.textContent = r.body || ""
        re.appendChild(rb)
        repliesEl.appendChild(re)
      })
      card.appendChild(repliesEl)
    }

    // Actions: resolve + reply (only when commenting is allowed).
    const actions = document.createElement("div")
    actions.className = "crit-preview-card-actions"

    const resolveBtn = document.createElement("button")
    resolveBtn.type = "button"
    resolveBtn.className = "btn btn-sm crit-preview-resolve-btn"
    resolveBtn.textContent = c.resolved ? "Unresolve" : "Resolve"
    resolveBtn.addEventListener("click", (e) => {
      e.stopPropagation()
      this.pushEvent("resolve_comment", { id: c.id, resolved: !c.resolved })
    })
    actions.appendChild(resolveBtn)

    if (this.canComment) {
      const replyBtn = document.createElement("button")
      replyBtn.type = "button"
      replyBtn.className = "btn btn-sm crit-preview-reply-btn"
      replyBtn.textContent = "Reply"
      replyBtn.addEventListener("click", (e) => {
        e.stopPropagation()
        this.openReply(card, c)
      })
      actions.appendChild(replyBtn)
    }
    card.appendChild(actions)

    // Click the card body → scroll/flash the pin in the iframe (keep/clear-
    // highlight + flash-marker, port of crit's scrollAndFlashPin).
    card.addEventListener("click", (e) => {
      if (e.target.closest("button, a, input, textarea")) return
      this.flashPin(c)
    })

    return card
  },

  openReply(card, comment) {
    // One reply box at a time per card.
    const existing = card.querySelector(".crit-preview-reply-form")
    if (existing) {
      existing.querySelector("textarea").focus()
      return
    }
    const form = document.createElement("div")
    form.className = "crit-preview-reply-form"
    form.innerHTML = [
      '<textarea class="crit-preview-reply-input" rows="2" placeholder="Reply… (Ctrl+Enter to submit, Escape to cancel)"></textarea>',
      '<div class="crit-preview-reply-actions">',
      '  <button type="button" class="btn btn-sm crit-preview-reply-cancel">Cancel</button>',
      '  <button type="button" class="btn btn-sm btn-primary crit-preview-reply-save">Reply</button>',
      "</div>",
    ].join("")
    card.appendChild(form)
    const ta = form.querySelector("textarea")
    const submit = () => {
      const body = (ta.value || "").trim()
      if (!body) {
        ta.focus()
        return
      }
      this.pushEvent("add_reply", { comment_id: comment.id, body })
      form.remove()
    }
    form.querySelector(".crit-preview-reply-save").addEventListener("click", submit)
    form.querySelector(".crit-preview-reply-cancel").addEventListener("click", () => form.remove())
    ta.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) {
        e.preventDefault()
        submit()
      } else if (e.key === "Escape") {
        e.preventDefault()
        form.remove()
      }
    })
    requestAnimationFrame(() => ta.focus())
  },

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
