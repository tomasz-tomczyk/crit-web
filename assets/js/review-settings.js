// Code renderer and theme settings for the review page, in the `crit-settings`
// JSON cookie with crit's key names (lightPalette, darkPalette, boostContrast,
// codeOverflow, lineNumbers). A cookie, not localStorage, because the server
// reads the theme palette choice to style the page before first paint
// (CritWeb.ThemePalette). The System/Light/Dark theme stays in `phx:theme`.

const COOKIE = 'crit-settings'
const MAX_AGE = 60 * 60 * 24 * 365

export function readSettings() {
  const match = document.cookie.match(/(?:^|;\s*)crit-settings=([^;]*)/)
  if (!match) return {}
  try {
    const parsed = JSON.parse(decodeURIComponent(match[1]))
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : {}
  } catch (_) {
    return {}
  }
}

export function getSetting(key, fallback) {
  const settings = readSettings()
  return Object.prototype.hasOwnProperty.call(settings, key) ? settings[key] : fallback
}

export function setSetting(key, value) {
  const settings = readSettings()
  settings[key] = value
  const secure = window.location.protocol === 'https:' ? '; Secure' : ''
  document.cookie = COOKIE + '=' + encodeURIComponent(JSON.stringify(settings)) +
    '; path=/; max-age=' + MAX_AGE + '; SameSite=Lax' + secure
}

// The System/Light/Dark choice (sitewide, see app.js setTheme).
export function themeChoice() {
  try {
    const t = localStorage.getItem('phx:theme')
    return t === 'light' || t === 'dark' ? t : 'system'
  } catch (_) {
    return 'system'
  }
}

// On review pages <html data-crit-palette> marks that a theme palette is
// applied (CritWeb.ThemePalette). Its value is the active theme id, as in
// crit: the light or dark half, whichever the page shows now. The CSS does
// not depend on the value; it names the theme for scripts, tests and people
// inspecting the page. Call after the theme, the OS scheme or the pair changes.
export function syncActivePalette(root = document.documentElement) {
  if (!root.hasAttribute('data-crit-palette')) return
  const forced = root.getAttribute('data-theme')
  const light = forced === 'light' || (forced !== 'dark' &&
    !!(window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches))
  const id = light ? root.dataset.critPaletteLight : root.dataset.critPaletteDark
  if (id) root.dataset.critPalette = id
}

// Rendered markdown follows the code display settings through CSS keyed on
// <html data-line-numbers / data-code-overflow> (rendered by the server,
// CritWeb.ReviewDisplay). Call after either setting changes; pages without
// the attributes are left alone.
export function applyDisplayAttributes(root = document.documentElement) {
  if (!root.hasAttribute('data-line-numbers')) return
  root.setAttribute('data-line-numbers', getSetting('lineNumbers', 'on') === 'off' ? 'off' : 'on')
  root.setAttribute('data-code-overflow', getSetting('codeOverflow', 'scroll') === 'wrap' ? 'wrap' : 'scroll')
}
