// Shared settings overlay — used by BOTH files mode (document-renderer.js) and
// preview mode (preview-mode.js). Extracted so the gear/overlay stop being
// document-renderer-only (the overlay was inert in preview because that hook
// never mounts).
//
// Like comments-panel.js, this module is PURE: it queries the server-rendered
// overlay shell (#settingsOverlay + tabs + empty panes, which live in
// review_live.html.heex and are shared by both modes) and is driven entirely by
// a per-mode `adapter`. All settings state is client-side (theme/width =
// localStorage, hide-resolved = localStorage) — there is no server state, which
// is why this is a JS module and not a LiveComponent.
//
// Theme is universal: clicking a theme pill dispatches the same `phx:set-theme`
// CustomEvent that app.js's setTheme() listens for. Per-mode differences are
// pure data on the adapter: preview drops Content-Width, supplies its own
// shortcut list, and (for now) omits Hide-resolved.

const THEME_ICONS = {
  system: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="currentColor"><path fill-rule="evenodd" d="M2 4.25A2.25 2.25 0 0 1 4.25 2h7.5A2.25 2.25 0 0 1 14 4.25v5.5A2.25 2.25 0 0 1 11.75 12h-1.312c.1.128.21.248.328.36a.75.75 0 0 1 .234.545v.345a.75.75 0 0 1-.75.75h-4.5a.75.75 0 0 1-.75-.75v-.345a.75.75 0 0 1 .234-.545c.118-.111.228-.232.328-.36H4.25A2.25 2.25 0 0 1 2 9.75v-5.5Zm2.25-.75a.75.75 0 0 0-.75.75v4.5c0 .414.336.75.75.75h7.5a.75.75 0 0 0 .75-.75v-4.5a.75.75 0 0 0-.75-.75h-7.5Z" clip-rule="evenodd"/></svg>',
  light: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="currentColor"><path d="M8 1a.75.75 0 0 1 .75.75v1.5a.75.75 0 0 1-1.5 0v-1.5A.75.75 0 0 1 8 1ZM10.5 8a2.5 2.5 0 1 1-5 0 2.5 2.5 0 0 1 5 0ZM12.95 4.11a.75.75 0 1 0-1.06-1.06l-1.062 1.06a.75.75 0 0 0 1.061 1.062l1.06-1.061ZM15 8a.75.75 0 0 1-.75.75h-1.5a.75.75 0 0 1 0-1.5h1.5A.75.75 0 0 1 15 8ZM11.89 12.95a.75.75 0 0 0 1.06-1.06l-1.06-1.062a.75.75 0 0 0-1.062 1.061l1.061 1.06ZM8 12a.75.75 0 0 1 .75.75v1.5a.75.75 0 0 1-1.5 0v-1.5A.75.75 0 0 1 8 12ZM5.172 11.89a.75.75 0 0 0-1.061-1.062L3.05 11.89a.75.75 0 1 0 1.06 1.06l1.06-1.06ZM4 8a.75.75 0 0 1-.75.75h-1.5a.75.75 0 0 1 0-1.5h1.5A.75.75 0 0 1 4 8ZM4.11 5.172A.75.75 0 0 0 5.173 4.11L4.11 3.05a.75.75 0 1 0-1.06 1.06l1.06 1.06Z"/></svg>',
  dark: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="currentColor"><path d="M14.438 10.148c.19-.425-.321-.787-.748-.601A5.5 5.5 0 0 1 6.453 2.31c.186-.427-.176-.938-.6-.748a6.501 6.501 0 1 0 8.585 8.586Z"/></svg>',
}

function cap(s) {
  return s.charAt(0).toUpperCase() + s.slice(1)
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

// createSettingsPanel(adapter) wires the shared overlay shell and returns a
// handle. adapter:
//   showWidth: bool, readWidth(): string, applyWidth(choice)          (files)
//   showHideResolved: bool, readHideResolved(): bool, setHideResolved(v) (files)
//   shortcutGroups: [{ label, shortcuts: [{ key, action, mode? }] }]  (per-mode)
// Theme + About are universal and need no adapter input.
export function createSettingsPanel(adapter) {
  const overlay = document.getElementById('settingsOverlay')
  const toggle = document.getElementById('settingsToggle')
  if (!overlay) {
    return { open() {}, close() {}, toggle() {}, isOpen: () => false, destroy() {} }
  }

  let panelOpen = false
  let panelTab = 'settings'
  const listeners = []
  const on = (el, ev, fn) => {
    if (!el) return
    el.addEventListener(ev, fn)
    listeners.push([el, ev, fn])
  }

  function renderSettingsPane() {
    const pane = document.getElementById('settingsPane')
    if (!pane) return

    const currentTheme = localStorage.getItem('phx:theme') || 'system'

    let html = '<div class="settings-section-label">Display</div>'
    html += '<div class="settings-display-group">'

    // Theme row (universal)
    html += '<div class="settings-display-row">'
    html += '<span class="settings-display-label">Theme</span>'
    html += '<div class="settings-pill settings-pill--theme" id="settingsThemePill" role="group" aria-label="Theme">'
    html += '<div class="settings-pill-indicator" id="settingsThemeIndicator"></div>'
    ;['system', 'light', 'dark'].forEach(function(theme) {
      const active = theme === currentTheme ? ' active' : ''
      html += '<button class="settings-pill-btn' + active + '" data-settings-theme="' + theme + '" title="' + cap(theme) + ' theme">' + THEME_ICONS[theme] + '</button>'
    })
    html += '</div></div>'

    // Content width row (files mode only)
    if (adapter.showWidth) {
      const currentWidth = (adapter.readWidth && adapter.readWidth()) || 'default'
      html += '<div class="settings-display-row">'
      html += '<span class="settings-display-label">Content Width</span>'
      html += '<div class="settings-pill settings-pill--width" id="settingsWidthPill" role="group" aria-label="Content width">'
      html += '<div class="settings-pill-indicator" id="settingsWidthIndicator"></div>'
      ;['compact', 'default', 'wide'].forEach(function(w) {
        const active = w === currentWidth ? ' active' : ''
        html += '<button class="settings-pill-btn' + active + '" data-settings-width="' + w + '">' + cap(w) + '</button>'
      })
      html += '</div></div>'
    }

    // Hide resolved row (only when the mode supports it)
    if (adapter.showHideResolved) {
      const hideResolved = adapter.readHideResolved && adapter.readHideResolved()
      html += '<div class="settings-display-row">'
      html += '<span class="settings-display-label">Hide resolved comments</span>'
      html += '<label class="comments-panel-switch">'
      html += '<input type="checkbox" id="hideResolvedToggle" aria-label="Hide resolved comments"' + (hideResolved ? ' checked' : '') + '>'
      html += '<span class="comments-panel-switch-track"><span class="comments-panel-switch-thumb"></span></span>'
      html += '</label>'
      html += '</div>'
    }

    html += '</div>' // close settings-display-group

    pane.innerHTML = html

    // Theme pill — dispatch the same event the rest of the app uses.
    pane.querySelectorAll('[data-settings-theme]').forEach(function(btn) {
      btn.addEventListener('click', function() {
        const theme = btn.dataset.settingsTheme
        const event = new CustomEvent('phx:set-theme', { bubbles: true })
        btn.dataset.phxTheme = theme
        btn.dispatchEvent(event)
        pane.querySelectorAll('[data-settings-theme]').forEach(function(b) { b.classList.toggle('active', b.dataset.settingsTheme === theme) })
        updatePillIndicator('settingsThemeIndicator', ['system', 'light', 'dark'], theme)
      })
    })
    updatePillIndicator('settingsThemeIndicator', ['system', 'light', 'dark'], currentTheme)

    // Width pill (files only)
    if (adapter.showWidth) {
      pane.querySelectorAll('[data-settings-width]').forEach(function(btn) {
        btn.addEventListener('click', function() {
          const w = btn.dataset.settingsWidth
          adapter.applyWidth(w)
          pane.querySelectorAll('[data-settings-width]').forEach(function(b) { b.classList.toggle('active', b.dataset.settingsWidth === w) })
          updatePillIndicator('settingsWidthIndicator', ['compact', 'default', 'wide'], w)
        })
      })
      const currentWidth = (adapter.readWidth && adapter.readWidth()) || 'default'
      updatePillIndicator('settingsWidthIndicator', ['compact', 'default', 'wide'], currentWidth)
    }

    // Hide-resolved toggle
    if (adapter.showHideResolved) {
      const hideResolvedToggle = pane.querySelector('#hideResolvedToggle')
      if (hideResolvedToggle) {
        hideResolvedToggle.addEventListener('change', function() {
          adapter.setHideResolved(hideResolvedToggle.checked)
        })
      }
    }
  }

  function renderShortcutsPane() {
    const pane = document.getElementById('shortcutsPane')
    if (!pane) return
    const groups = adapter.shortcutGroups || []
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
    html += '<div class="about-header">'
    html += '<h2>Crit Web</h2>'
    html += '<div class="about-version">Your feedback loop with the agent.</div>'
    html += '</div>'
    html += '<div class="settings-section-label">Links</div>'
    html += '<div class="about-links">'
    html += '<a class="about-link" href="https://crit.md" target="_blank" rel="noopener"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M8 1v4M5.5 3h5M3 7h10v6.5a.5.5 0 0 1-.5.5h-9a.5.5 0 0 1-.5-.5V7Z"/></svg>Homepage</a>'
    html += '<a class="about-link" href="https://github.com/tomasz-tomczyk/crit-web" target="_blank" rel="noopener"><svg viewBox="0 0 16 16" fill="currentColor"><path d="M8 0c4.42 0 8 3.58 8 8a8.013 8.013 0 0 1-5.45 7.59c-.4.08-.55-.17-.55-.38 0-.27.01-1.13.01-2.2 0-.75-.25-1.23-.54-1.48 1.78-.2 3.65-.88 3.65-3.95 0-.88-.31-1.59-.82-2.15.08-.2.36-1.02-.08-2.12 0 0-.67-.22-2.2.82-.64-.18-1.32-.27-2-.27-.68 0-1.36.09-2 .27-1.53-1.03-2.2-.82-2.2-.82-.44 1.1-.16 1.92-.08 2.12-.51.56-.82 1.28-.82 2.15 0 3.06 1.86 3.75 3.64 3.95-.23.2-.44.55-.51 1.07-.46.21-1.61.55-2.33-.66-.15-.24-.6-.83-1.23-.82-.67.01-.27.38.01.53.34.19.73.9.82 1.13.16.45.68 1.31 2.69.94 0 .67.01 1.3.01 1.49 0 .21-.15.45-.55.38A7.995 7.995 0 0 1 0 8c0-4.42 3.58-8 8-8Z"/></svg>GitHub</a>'
    html += '<a class="about-link" href="https://crit.md/changelog" target="_blank" rel="noopener"><svg viewBox="0 0 16 16" fill="currentColor"><path d="M1 7.775V2.75C1 1.784 1.784 1 2.75 1h5.025c.464 0 .91.184 1.238.513l6.25 6.25a1.75 1.75 0 0 1 0 2.474l-5.026 5.026a1.75 1.75 0 0 1-2.474 0l-6.25-6.25A1.752 1.752 0 0 1 1 7.775Zm1.5 0c0 .066.026.13.073.177l6.25 6.25a.25.25 0 0 0 .354 0l5.025-5.025a.25.25 0 0 0 0-.354l-6.25-6.25a.25.25 0 0 0-.177-.073H2.75a.25.25 0 0 0-.25.25ZM6 5a1 1 0 1 1 0 2 1 1 0 0 1 0-2Z"/></svg>Changelog</a>'
    html += '</div>'
    pane.innerHTML = html
  }

  function switchTab(tab) {
    panelTab = tab
    let activeBtn = null
    overlay.querySelectorAll('.settings-tab[data-tab]').forEach(function(t) {
      const isActive = t.dataset.tab === tab
      t.classList.toggle('active', isActive)
      if (isActive) activeBtn = t
    })
    overlay.querySelectorAll('.settings-pane').forEach(function(p) {
      p.classList.toggle('active', p.dataset.pane === tab)
    })
    const underline = overlay.querySelector('.settings-tab-underline')
    if (underline && activeBtn) {
      const tabsRect = activeBtn.parentElement.getBoundingClientRect()
      const btnRect = activeBtn.getBoundingClientRect()
      underline.style.left = (btnRect.left - tabsRect.left) + 'px'
      underline.style.width = btnRect.width + 'px'
    }
    if (tab === 'settings') renderSettingsPane()
    else if (tab === 'about') renderAboutPane()
  }

  function open(tab) {
    panelTab = tab || 'settings'
    panelOpen = true
    overlay.classList.add('active')
    if (!overlay.querySelector('.settings-tab-underline')) {
      const underline = document.createElement('div')
      underline.className = 'settings-tab-underline'
      overlay.querySelector('.settings-tabs').appendChild(underline)
    }
    switchTab(panelTab)
    renderShortcutsPane()
  }

  function close() {
    panelOpen = false
    overlay.classList.remove('active')
  }

  // Wiring (gear toggle, close button, click-outside, tab clicks).
  on(toggle, 'click', function() { panelOpen ? close() : open('settings') })
  on(document.getElementById('settingsClose'), 'click', close)
  on(overlay, 'click', function(e) { if (e.target === overlay) close() })
  overlay.querySelectorAll('.settings-tab[data-tab]').forEach(function(tab) {
    on(tab, 'click', function() { switchTab(tab.dataset.tab) })
  })

  return {
    open,
    close,
    toggle: function(tab) { panelOpen ? close() : open(tab) },
    isOpen: function() { return panelOpen },
    switchTab,
    destroy: function() {
      listeners.forEach(function(l) { l[0].removeEventListener(l[1], l[2]) })
      if (panelOpen) close()
    },
  }
}
