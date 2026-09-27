import { test } from 'node:test'
import assert from 'node:assert/strict'
import { install } from './support/dom.mjs'
import { importModule } from './support/modules.mjs'

install()
const runtime = await importModule('js/pierre-runtime.js')
const settings = await importModule('js/review-settings.js')

test('palettePair reads the server-validated pair, with crit\'s defaults', () => {
  const dom = install()
  assert.deepEqual(runtime.palettePair(), { light: 'github-light-default', dark: 'tokyo-night' })
  dom.root.dataset.critPaletteLight = 'min-light'
  dom.root.dataset.critPaletteDark = 'dracula'
  assert.deepEqual(runtime.palettePair(), { light: 'min-light', dark: 'dracula' })
})

test('displayOptions maps the reader\'s settings to Pierre options', () => {
  install()
  assert.deepEqual(
    (({ overflow, disableLineNumbers, theme }) => ({ overflow, disableLineNumbers, theme }))(runtime.displayOptions()),
    { overflow: 'scroll', disableLineNumbers: false, theme: { light: 'github-light-default', dark: 'tokyo-night' } })
  settings.setSetting('codeOverflow', 'wrap')
  settings.setSetting('lineNumbers', 'off')
  const opts = runtime.displayOptions()
  assert.equal(opts.overflow, 'wrap')
  assert.equal(opts.disableLineNumbers, true)
  settings.setSetting('codeOverflow', 'sideways')
  assert.equal(runtime.displayOptions().overflow, 'scroll', 'unknown values fall back')
})

test('Syntax contrast registers boosted copies of the pair with Pierre', () => {
  install()
  const registered = []
  window.PierreDiffs = { registerCustomTheme: name => registered.push(name), resolveTheme: () => Promise.resolve({}) }
  settings.setSetting('boostContrast', 'on')
  assert.deepEqual(runtime.displayOptions().theme, { light: 'github-light-default--crit-boost', dark: 'tokyo-night--crit-boost' })
  assert.deepEqual(registered.sort(), ['github-light-default--crit-boost', 'tokyo-night--crit-boost'])
  delete window.PierreDiffs
})

test('themeType follows the System/Light/Dark choice', () => {
  install()
  assert.equal(runtime.themeType(), 'system')
  install({ theme: 'dark' })
  assert.equal(runtime.themeType(), 'dark')
})

test('applyPalette swaps the palette stylesheet and the theme ids', () => {
  const dom = install()
  runtime.applyPalette({ css: ':root{}', light: 'min-light', dark: 'dracula' })
  assert.equal(dom.style.textContent, ':root{}')
  assert.equal(dom.root.dataset.critPaletteLight, 'min-light')
  assert.equal(dom.root.dataset.critPaletteDark, 'dracula')
})

test('a palette change saves the cookie, asks the server and re-themes code', async () => {
  const dom = install()
  const kinds = []
  const off = runtime.onRendererChange(kind => kinds.push(kind))
  const pushed = []
  await runtime.changeRendererSetting('darkPalette', 'dracula', (event, payload) => {
    pushed.push([event, payload])
    return Promise.resolve({ css: 'x', light: 'github-light-default', dark: 'dracula' })
  })
  off()
  assert.equal(settings.getSetting('darkPalette'), 'dracula')
  assert.deepEqual(pushed, [['theme_palette', { lightPalette: null, darkPalette: 'dracula' }]])
  assert.equal(dom.root.dataset.critPaletteDark, 'dracula')
  assert.deepEqual(kinds, ['theme'])
})

test('preview mode changes only the palette (no code to re-theme)', async () => {
  const dom = install()
  const kinds = []
  const off = runtime.onRendererChange(kind => kinds.push(kind))
  await runtime.changeThemePalette('lightPalette', 'min-light', () => Promise.resolve({ css: 'y', light: 'min-light', dark: 'tokyo-night' }))
  off()
  assert.equal(dom.style.textContent, 'y')
  assert.deepEqual(kinds, [])
})

test('display and contrast changes notify code surfaces with their kind', async () => {
  install()
  const kinds = []
  const off = runtime.onRendererChange(kind => kinds.push(kind))
  await runtime.changeRendererSetting('codeOverflow', 'wrap', () => assert.fail('no server call'))
  await runtime.changeRendererSetting('lineNumbers', 'off', () => assert.fail('no server call'))
  await runtime.changeRendererSetting('boostContrast', 'on', () => assert.fail('no server call'))
  off()
  assert.deepEqual(kinds, ['display', 'display', 'theme'])
  assert.equal(settings.getSetting('codeOverflow'), 'wrap')
})
