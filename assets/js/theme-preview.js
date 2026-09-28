// /themes (CritWeb.ThemesLive): flip through the bundled themes on fixed
// review samples and pick a light and a dark theme. Mirrors crit's
// crit-theme-preview.js; the samples use crit-web's review markup, and the
// palette stylesheet comes from the server (`theme_palette`, as on the review
// page) instead of crit's client-side palette module.

import { adapter, applyPalette, codeHighlight, configureCodeHighlight, displayOptions, loadPierre, palettePair, workerPool } from "./pierre-runtime"
import pierreDOM from "../vendor/crit/crit-pierre-dom.js"
import { applyDisplayAttributes, getSetting, setSetting, themeChoice } from "./review-settings"

const ICON_CHEVRON = '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true"><path d="M12.78 5.22a.749.749 0 0 1 0 1.06l-4.25 4.25a.749.749 0 0 1-1.06 0L3.22 6.28a.749.749 0 1 1 1.06-1.06L8 8.939l3.72-3.719a.749.749 0 0 1 1.06 0Z"></path></svg>'
const ICON_FILE = '<svg class="file-header-icon" viewBox="0 0 16 16" fill="var(--crit-editor-fg-muted)" aria-hidden="true"><path fill-rule="evenodd" d="M3.75 1.5a.25.25 0 0 0-.25.25v11.5c0 .138.112.25.25.25h8.5a.25.25 0 0 0 .25-.25V6H9.75A1.75 1.75 0 0 1 8 4.25V1.5H3.75zm5.75.56v2.19c0 .138.112.25.25.25h2.19L9.5 2.06zM2 1.75C2 .784 2.784 0 3.75 0h5.086c.464 0 .909.184 1.237.513l3.414 3.414c.329.328.513.773.513 1.237v8.086A1.75 1.75 0 0 1 12.25 15h-8.5A1.75 1.75 0 0 1 2 13.25V1.75z"></path></svg>'

const CODE = [
  'package main',
  '',
  'import (',
  '\t"errors"',
  '\t"net/http"',
  ')',
  '',
  '// authMiddleware checks the API key header, then the session cookie.',
  'func authMiddleware(next http.Handler) http.Handler {',
  '\treturn http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {',
  '\t\tif key := r.Header.Get("X-API-Key"); key != "" && !validKey(key) {',
  '\t\t\thttp.Error(w, errors.New("invalid key").Error(), http.StatusUnauthorized)',
  '\t\t\treturn',
  '\t\t}',
  '\t\tconst retries = 3 // TODO: make configurable',
  '\t\tnext.ServeHTTP(w, r)',
  '\t})',
  '}',
  '',
].join('\n')

let sampleKey = 0

const FENCE = { code: 'if !validKey(key) {\n\treturn http.StatusUnauthorized\n}\n', lang: 'go' }

function fileHeader(dir, name) {
  return '<summary class="file-header"><div class="file-header-chevron">' + ICON_CHEVRON + '</div>' + ICON_FILE +
    '<span class="file-header-name"><span class="dir">' + dir + '</span><span class="filename">' + name + '</span></span>' +
    '<a class="crit-round-diff-btn">Raw</a>' +
    '<label class="file-header-viewed"><input type="checkbox"><span>Viewed</span></label></summary>'
}

function commentCard(author, color, lineRef, body, reply) {
  return '<div class="comment-block"><div class="comment-card"><div class="comment-header"><div class="comment-header-left">' +
    '<button class="comment-collapse-btn" aria-label="Collapse comment">' + ICON_CHEVRON + '</button>' +
    '<span class="comment-author-badge author-color-' + color + '">@' + author + '</span>' +
    (lineRef ? '<span class="comment-line-ref">' + lineRef + '</span>' : '') +
    '<span class="comment-time">1:47 PM</span></div><div class="comment-actions"></div></div>' +
    '<div class="comment-body">' + body + '</div>' +
    (reply ? '<div class="comment-replies"><div class="comment-reply"><div class="reply-header"><div class="reply-meta">' +
      '<span class="comment-author-badge author-color-2">@Claude</span><span class="reply-time">1:52 PM</span></div></div>' +
      '<div class="reply-body">' + reply + '</div></div></div>' : '') +
    '<div class="reply-form"><input type="text" class="reply-input" placeholder="Write a reply…"></div></div></div>'
}

// Rendered Markdown uses crit-web's line blocks: one block per source line.
function block(n, html, cls, contentCls) {
  return '<div class="line-block' + (cls ? ' ' + cls : '') + '"><div class="line-gutter"><span class="line-num">' + n + '</span></div>' +
    '<div class="line-content' + (contentCls ? ' ' + contentCls : '') + '">' + html + '</div></div>'
}

function tableRow(n, tag, cells, head) {
  return '<tr class="line-block table-row' + (head ? ' table-first' : '') + '"><td class="native-table-gutter"><div class="line-gutter"><span class="line-num">' + n + '</span></div></td>' +
    cells.map(c => '<' + tag + ' class="line-content table-row' + (head ? ' table-first' : '') + '">' + c + '</' + tag + '>').join('') + '</tr>'
}

function fenceBlocks(start) {
  const escape = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  const lines = codeHighlight.lines(FENCE.code, FENCE.lang) || FENCE.code.replace(/\n$/, '').split('\n').map(escape)
  return lines.map((html, i) => block(start + i, '<code class="crit-code">' + (html || '&nbsp;') + '</code>', '',
    'code-line' + (i === 0 ? ' code-first' : '') + (i === lines.length - 1 ? ' code-last' : ''))).join('')
}

function documentSample() {
  return block(1, '<h1>API key authentication</h1>') +
    block(2, '', '', 'empty-line') +
    block(3, '<p>Requests may send an <code>X-API-Key</code> header. Keys are checked before the session cookie, see <a href="#">the auth guide</a>. Invalid keys get a <strong>401</strong>.</p>', 'has-comment') +
    block(4, '', '', 'empty-line') +
    block(5, '<h2>Rollout</h2>', 'focused') +
    block(6, '<ol start="1"><li>Ship the middleware behind a flag</li></ol>') +
    block(7, '<ol start="2"><li>Rotate existing keys</li></ol>', 'line-block-added') +
    block(8, '<blockquote><p>Keys never appear in logs.</p></blockquote>') +
    fenceBlocks(9) +
    block(12, '', '', 'empty-line') +
    '<div class="native-table-wrapper"><table class="native-table"><thead>' +
    tableRow(13, 'th', ['Setting', 'Type', 'Default'], true) + '</thead><tbody>' +
    tableRow(15, 'td', ['<code>auth.keys</code>', 'string[]', '<code>[]</code>']) +
    tableRow(16, 'td', ['<code>auth.header</code>', 'string', '<code>"X-API-Key"</code>']) +
    '</tbody></table></div>'
}

export const ThemePreview = {
  async mounted() {
    const hook = this
    hook.saved = palettePair()
    hook.state = { mode: initialMode(), id: null }
    hook.list = document.getElementById('themeList')

    hook.list.addEventListener('click', e => {
      const item = e.target.closest('[data-id]')
      if (item) hook.select(hook.state.mode, item.dataset.id)
    })
    hook.list.addEventListener('keydown', e => {
      const step = { ArrowDown: 1, ArrowUp: -1, Home: -1e9, End: 1e9 }[e.key]
      if (step === undefined) return
      e.preventDefault()
      hook.move(step)
    })
    document.getElementById('previewModeToggle').addEventListener('click', e => {
      const btn = e.target.closest('[data-preview-mode]')
      if (btn && btn.dataset.previewMode !== hook.state.mode) hook.select(btn.dataset.previewMode, hook.saved[btn.dataset.previewMode])
    })
    document.getElementById('useTheme').addEventListener('click', () => {
      setSetting(hook.state.mode + 'Palette', hook.state.id)
      hook.saved[hook.state.mode] = hook.state.id
      hook.refreshChrome()
      document.getElementById('themeStatus').textContent = 'Saved. Open or reload a review to use it.'
    })
    // Display settings: the review page's cookie keys; the samples follow them.
    document.querySelectorAll('[data-preview-setting]').forEach(select => {
      const value = getSetting(select.dataset.previewSetting, select.dataset.fallback)
      select.value = Array.from(select.options).some(o => o.value === value) ? value : select.dataset.fallback
      select.addEventListener('change', () => {
        setSetting(select.dataset.previewSetting, select.value)
        applyDisplayAttributes()
        hook.renderSamples()
      })
    })

    hook.P = await loadPierre()
    configureCodeHighlight()
    await codeHighlight.prime([FENCE])
    const hash = location.hash.slice(1).split('/')
    const mode = hash[0] === 'light' || hash[0] === 'dark' ? hash[0] : hook.state.mode
    const id = hook.items(mode).some(el => el.dataset.id === hash[1]) ? hash[1] : hook.saved[mode]
    await hook.select(mode, id)
    hook.list.focus()
  },

  items(mode) {
    return Array.from(this.list.querySelectorAll('[data-id]')).filter(el => el.dataset.type === mode)
  },

  move(delta) {
    const items = this.items(this.state.mode)
    const i = items.findIndex(el => el.dataset.id === this.state.id)
    const next = items[Math.max(0, Math.min(items.length - 1, i + delta))]
    if (next) this.select(this.state.mode, next.dataset.id)
  },

  async select(mode, id) {
    const seq = this.seq = (this.seq || 0) + 1
    this.state = { mode, id }
    // Preview the chosen half: force the mode on this page only (not saved).
    document.documentElement.setAttribute('data-theme', mode)
    const pair = Object.assign({}, this.saved, { [mode]: id })
    const reply = await new Promise(resolve =>
      this.pushEvent('theme_palette', { lightPalette: pair.light, darkPalette: pair.dark }, resolve))
    if (seq !== this.seq) return
    applyPalette(reply)
    this.refreshChrome()
    await this.renderSamples()
    history.replaceState(null, '', '#' + mode + '/' + id)
  },

  refreshChrome() {
    const { mode, id } = this.state
    document.querySelectorAll('[data-preview-mode]').forEach(b => {
      b.classList.toggle('crit-toggle-btn--active', b.dataset.previewMode === mode)
      b.setAttribute('aria-pressed', String(b.dataset.previewMode === mode))
    })
    this.list.querySelectorAll('[data-id]').forEach(el => {
      el.hidden = el.dataset.type !== mode
      el.setAttribute('aria-selected', String(el.dataset.id === id))
      el.querySelector('.theme-preview-current').hidden = el.dataset.id !== this.saved[mode]
    })
    this.list.setAttribute('aria-activedescendant', 'theme-' + id)
    const item = document.getElementById('theme-' + id)
    if (item) item.scrollIntoView({ block: 'nearest' })
    document.getElementById('themeName').textContent = item ? item.querySelector('.theme-preview-item-name').textContent : id
    const saved = this.saved[mode] === id
    document.getElementById('themeStatus').textContent = saved ? 'Your current ' + mode + ' theme' : ''
    const use = document.getElementById('useTheme')
    use.textContent = saved ? 'In use' : 'Use as ' + mode + ' theme'
    use.disabled = saved
  },

  // Code tokens carry the theme's colours: the worker pool gets the previewed
  // theme and fences are re-tokenized with it.
  async renderSamples() {
    const pool = workerPool()
    if (pool) await pool.setRenderOptions({ theme: displayOptions().theme })
    configureCodeHighlight()
    await codeHighlight.prime([FENCE])
    const root = document.getElementById('themeSamples')
    root.innerHTML =
      '<details class="file-section theme-preview-file" open>' + fileHeader('internal/', 'server.go') +
        '<div class="file-body crit-code-body" id="previewCode"></div></details>' +
      '<details class="file-section theme-preview-file" open>' + fileHeader('docs/', 'auth.md') +
        '<div class="file-comments">' + commentCard('Ada', 4, null, '<p>Should the rollout mention <strong>key rotation</strong> for old clients?</p>', '<p>Added step 2.</p>') + '</div>' +
        '<div class="file-body"><div class="document-wrapper">' + documentSample() + '</div></div></details>' +
      '<section class="theme-preview-controls">' +
        ['Ada', 'Claude', 'Grace', 'Linus', 'Margaret', 'Ken'].map((name, i) =>
          '<span class="comment-author-badge author-color-' + i + '">@' + name + '</span>').join('') +
      '</section><section class="theme-preview-controls">' +
        '<div class="crit-diff-mode-toggle"><button class="crit-toggle-btn crit-toggle-btn--active">Split</button><button class="crit-toggle-btn">Unified</button></div>' +
        '<button class="btn btn-sm">Default</button><button class="btn btn-sm btn-primary">Primary</button>' +
        '<span class="file-header-badge removed">Removed</span>' +
      '</section>'
    this.renderCode()
  },

  // One Pierre File with a line comment, rebuilt per theme or setting.
  renderCode() {
    const container = document.getElementById('previewCode')
    if (this.file) { this.file.cleanUp(); this.file = null }
    if (!container || !this.P) return
    container.innerHTML = ''
    this.file = new this.P.File(Object.assign(adapter.baseOptions(this.state.mode, 'unified'), displayOptions(), {
      themeType: this.state.mode,
      disableFileHeader: true,
      unsafeCSS: pierreDOM.unsafeCSS,
      renderAnnotation() {
        const el = document.createElement('div')
        el.className = 'pierre-annotation'
        el.innerHTML = commentCard('Ada', 4, 'Lines 11–12', '<p>Use <code>http.StatusUnauthorized</code> here too, and drop the unused <code>retries</code>.</p>')
        return el
      },
    }), workerPool())
    this.file.render({
      file: adapter.buildFileContents(this.P, { path: 'internal/server.go', content: CODE }, 'theme-preview:' + (++sampleKey)),
      lineAnnotations: [{ lineNumber: 12, metadata: { kind: 'thread', id: 'sample' } }],
      containerWrapper: container,
    })
  },

  destroyed() {
    if (this.file) this.file.cleanUp()
  },
}

function initialMode() {
  const choice = themeChoice()
  if (choice === 'light' || choice === 'dark') return choice
  return window.matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark'
}
