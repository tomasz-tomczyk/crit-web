import { test } from 'node:test'
import assert from 'node:assert/strict'
import { install } from './support/dom.mjs'
import { importModule } from './support/modules.mjs'

const settings = await importModule('js/review-settings.js')

test('reads nothing when the cookie is missing or unreadable', () => {
  install()
  assert.deepEqual(settings.readSettings(), {})
  install({ cookie: 'crit-settings=%7Bnot-json' })
  assert.deepEqual(settings.readSettings(), {})
  install({ cookie: 'crit-settings=' + encodeURIComponent('["list"]') })
  assert.deepEqual(settings.readSettings(), {})
})

test('round-trips settings in crit\'s cookie format', () => {
  const dom = install({ cookie: 'other=1' })
  settings.setSetting('darkPalette', 'dracula')
  settings.setSetting('codeOverflow', 'wrap')
  assert.equal(settings.getSetting('darkPalette', 'tokyo-night'), 'dracula')
  assert.equal(settings.getSetting('codeOverflow', 'scroll'), 'wrap')
  assert.equal(settings.getSetting('lineNumbers', 'on'), 'on')
  // Same encoding as crit: encodeURIComponent(JSON), one cookie for all keys.
  const last = dom.writes.at(-1)
  assert.match(last, /^crit-settings=%7B%22darkPalette%22%3A%22dracula%22%2C%22codeOverflow%22%3A%22wrap%22%7D; /)
  assert.match(last, /; path=\/; max-age=31536000; SameSite=Lax$/)
})

test('marks the cookie Secure over https', () => {
  const dom = install({ protocol: 'https:' })
  settings.setSetting('lineNumbers', 'off')
  assert.match(dom.writes.at(-1), /; SameSite=Lax; Secure$/)
})

test('themeChoice follows phx:theme and defaults to system', () => {
  install()
  assert.equal(settings.themeChoice(), 'system')
  install({ theme: 'light' })
  assert.equal(settings.themeChoice(), 'light')
  install({ theme: 'bogus' })
  assert.equal(settings.themeChoice(), 'system')
})

test('syncActivePalette names the half the page shows, only on palette pages', () => {
  let dom = install()
  dom.root.dataset.critPaletteLight = 'min-light'
  dom.root.dataset.critPaletteDark = 'dracula'
  settings.syncActivePalette()
  assert.equal(dom.root.dataset.critPalette, undefined, 'no palette on this page')

  dom.root.setAttribute('data-crit-palette', '')
  settings.syncActivePalette()
  assert.equal(dom.root.dataset.critPalette, 'dracula', 'system dark')
  dom.root.setAttribute('data-theme', 'light')
  settings.syncActivePalette()
  assert.equal(dom.root.dataset.critPalette, 'min-light', 'forced light')

  dom = install({ systemLight: true })
  dom.root.setAttribute('data-crit-palette', '')
  dom.root.dataset.critPaletteLight = 'min-light'
  dom.root.dataset.critPaletteDark = 'dracula'
  settings.syncActivePalette()
  assert.equal(dom.root.dataset.critPalette, 'min-light', 'system light')
  dom.root.setAttribute('data-theme', 'dark')
  settings.syncActivePalette()
  assert.equal(dom.root.dataset.critPalette, 'dracula', 'forced dark')
})

test('applyDisplayAttributes mirrors the code display settings for markdown', () => {
  const dom = install()
  settings.applyDisplayAttributes()
  assert.equal(dom.root.getAttribute('data-line-numbers'), null, 'pages without the attributes are left alone')

  dom.root.setAttribute('data-line-numbers', 'on')
  dom.root.setAttribute('data-code-overflow', 'scroll')
  settings.setSetting('lineNumbers', 'off')
  settings.setSetting('codeOverflow', 'wrap')
  settings.applyDisplayAttributes()
  assert.equal(dom.root.getAttribute('data-line-numbers'), 'off')
  assert.equal(dom.root.getAttribute('data-code-overflow'), 'wrap')

  settings.setSetting('codeOverflow', 'sideways')
  settings.applyDisplayAttributes()
  assert.equal(dom.root.getAttribute('data-code-overflow'), 'scroll', 'unknown values fall back')
})
