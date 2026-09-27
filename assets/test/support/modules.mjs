// Import crit-web's review-page modules under `node --test`.
//
// assets/js is ES modules bundled by esbuild, but assets/package.json says
// "type": "commonjs", so Node cannot import them in place. This mirrors
// assets/js (as ESM) and assets/vendor/crit (crit's UMD modules, as CJS) into
// a temp directory once per test process and imports from there.

import { cpSync, mkdtempSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const assets = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..')
let root = null

function mirror() {
  if (root) return root
  root = mkdtempSync(join(tmpdir(), 'crit-web-js-'))
  cpSync(join(assets, 'js'), join(root, 'js'), { recursive: true })
  cpSync(join(assets, 'vendor', 'crit'), join(root, 'vendor', 'crit'), { recursive: true })
  writeFileSync(join(root, 'package.json'), '{"type":"module"}')
  writeFileSync(join(root, 'vendor', 'crit', 'package.json'), '{"type":"commonjs"}')
  return root
}

// importModule('js/code-file-view.js')
export function importModule(path) {
  return import(pathToFileURL(join(mirror(), path)).href)
}
