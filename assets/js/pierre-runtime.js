// The code renderer for review pages: crit's @pierre/diffs build (Shiki in a
// worker pool), vendored verbatim under /pierre/ and assets/vendor/crit/
// (scripts/sync-pierre.sh). This module owns the crit-web side of it:
// loading the bundle, the worker pool, the reader's display settings and
// theme palette, and fenced-code highlighting outside rendered documents.
// crit's equivalent lives in crit/web/app.js (ensurePierreWorkerPool,
// pierreDisplayOptions, watchCodeBlocks); keep the two in step.

import adapter from '../vendor/crit/crit-pierre-adapter.js'
import runtime from '../vendor/crit/crit-pierre-runtime.js'
import themeBoost from '../vendor/crit/crit-theme-boost.js'
import codeHighlight from '../vendor/crit/crit-code-highlight.js'
import { applyDisplayAttributes, getSetting, readSettings, setSetting, syncActivePalette, themeChoice } from './review-settings.js'

// Absolute: review pages live under /r/:token, so crit's relative
// 'pierre/…' would resolve to /r/pierre/….
const ENTRY_URL = '/pierre/pierre-diffs.js'
const WORKER_URL = '/pierre/pierre-worker.js'
const PALETTES_URL = '/pierre/palettes.js'

function loadScript(src, type) {
  return new Promise(resolve => {
    const script = document.createElement('script')
    if (type) script.type = type
    script.src = src
    script.onload = () => resolve(true)
    script.onerror = () => resolve(false)
    document.head.appendChild(script)
  })
}

let pierrePromise = null
// window.PierreDiffs, or null when the bundle cannot load. Loaded once per
// page; module scripts are deferred, so callers await this before rendering.
export function loadPierre() {
  if (!pierrePromise) {
    pierrePromise = window.PierreDiffs
      ? Promise.resolve(window.PierreDiffs)
      : loadScript(ENTRY_URL, 'module').then(() => window.PierreDiffs || null)
  }
  return pierrePromise
}

let palettesPromise = null
// Every bundled theme palette (window.crit.palettes: id, type, displayName,
// colors), for the Settings theme lists. [] when it cannot load.
export function loadPalettes() {
  if (!palettesPromise) {
    palettesPromise = (window.crit && window.crit.palettes)
      ? Promise.resolve(window.crit.palettes)
      : loadScript(PALETTES_URL).then(() => (window.crit && window.crit.palettes) || [])
  }
  return palettesPromise
}

// The reader's light/dark theme ids, as validated and applied by the server
// (CritWeb.ThemePalette, <html data-crit-palette-light/-dark>).
export function palettePair() {
  const root = document.documentElement.dataset
  return {
    light: root.critPaletteLight || adapter.THEME.light,
    dark: root.critPaletteDark || adapter.THEME.dark,
  }
}

// Pierre options every code surface shares: overflow, line numbers and the
// theme pair (a contrast-boosted copy when Syntax contrast is on).
export function displayOptions() {
  return Object.assign(adapter.displayOptions(getSetting), {
    theme: themeBoost.themes(window.PierreDiffs, palettePair(), getSetting('boostContrast', 'off') === 'on'),
  })
}

export function themeType() {
  return adapter.themeTypeFor(themeChoice())
}

const listeners = new Set()
// Code surfaces re-render when display settings, the theme or the worker
// pool change. fn(kind): 'theme' (palette, contrast: token colours changed,
// highlighted fences must be rebuilt) or 'display' (overflow, line numbers,
// worker fallback). Returns an unsubscribe function.
export function onRendererChange(fn) {
  listeners.add(fn)
  return () => listeners.delete(fn)
}
function notify(kind) {
  listeners.forEach(fn => {
    try { fn(kind) } catch (error) { console.error('Code renderer update failed', error) }
  })
}

let workerController = null
// Pierre's worker pool (undefined after the workers failed; Pierre then
// highlights on the main thread).
export function workerPool() {
  const P = window.PierreDiffs
  if (!P) return undefined
  if (!workerController) {
    workerController = runtime.createWorkerController({
      create() {
        const display = displayOptions()
        return P.getOrCreateWorkerPoolSingleton({
          poolOptions: {
            workerFactory: () => new Worker(WORKER_URL, { type: 'module' }),
            poolSize: Math.max(1, Math.min(4, (navigator.hardwareConcurrency || 4) - 1)),
          },
          highlighterOptions: {
            theme: display.theme,
            lineDiffType: display.lineDiffType,
            preferredHighlighter: 'shiki-js',
          },
        })
      },
      onFailure(error) {
        console.warn('Highlight workers unavailable; rendering without workers.', error)
        configureCodeHighlight()
        requestAnimationFrame(() => notify('display'))
      },
    })
  }
  return workerController.get()
}

// Fenced code outside Pierre surfaces tokenizes in the same pool.
export function configureCodeHighlight() {
  codeHighlight.configure({
    pool: () => loadPierre().then(P => (P ? workerPool() : null)),
  })
}

// Comment bodies and other sanitised markdown render fences plain; highlight
// them once mounted (crit: watchCodeBlocks). Returns a disconnect function.
export function watchCodeBlocks(root) {
  codeHighlight.upgrade(root)
  const observer = new MutationObserver(records => {
    for (const record of records) {
      for (const node of record.addedNodes) {
        if (node.nodeType === 1) codeHighlight.upgrade(node.matches('pre') ? node.parentNode : node)
      }
    }
  })
  observer.observe(root, { childList: true, subtree: true })
  return () => observer.disconnect()
}

// After a palette or Syntax contrast change: hand the pool the new theme,
// drop highlighted fences (their token colours belong to the old theme) and
// let code surfaces re-render.
export async function applyThemeChange() {
  const pool = window.PierreDiffs ? workerPool() : undefined
  if (pool) await pool.setRenderOptions({ theme: displayOptions().theme })
  configureCodeHighlight()
  notify('theme')
}

// After an overflow or line-number change: code surfaces re-render and
// rendered markdown follows through its <html> attributes.
export function applyDisplayChange() {
  applyDisplayAttributes()
  notify('display')
}

// The server's palette reply (ReviewLive "theme_palette"): swap the page's
// palette stylesheet and the validated theme ids read by palettePair().
export function applyPalette({ css, light, dark }) {
  const style = document.getElementById('crit-palette')
  if (style && typeof css === 'string') style.textContent = css
  const root = document.documentElement
  if (light) root.dataset.critPaletteLight = light
  if (dark) root.dataset.critPaletteDark = dark
  syncActivePalette(root)
}

// Save a light/dark theme choice and restyle the page with the server's
// validated palette. Enough on its own for pages without code (preview mode).
// pushEvent(event, payload) → Promise of the LiveView reply.
export async function changeThemePalette(key, value, pushEvent) {
  setSetting(key, value)
  const settings = readSettings()
  applyPalette(await pushEvent('theme_palette', {
    lightPalette: settings.lightPalette || null,
    darkPalette: settings.darkPalette || null,
  }))
}

// Settings changed one renderer setting (crit: onRendererSettingChange).
export async function changeRendererSetting(key, value, pushEvent) {
  if (key === 'lightPalette' || key === 'darkPalette') {
    await changeThemePalette(key, value, pushEvent)
    await applyThemeChange()
    return
  }
  setSetting(key, value)
  if (key === 'boostContrast') {
    await applyThemeChange()
  } else {
    applyDisplayChange()
  }
}

export { adapter, codeHighlight }
