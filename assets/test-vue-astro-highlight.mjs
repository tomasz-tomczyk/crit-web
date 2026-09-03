// Smoke test: Vue SFC and Astro grammars register with highlight.js (issue #868).
// Run: node assets/test-vue-astro-highlight.mjs   (from crit-web/ root)
//   or: node test-vue-astro-highlight.mjs         (from crit-web/assets/)

import hljs from 'highlight.js'
import hljsAstro from 'highlightjs-astro-js'
import { readFileSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { dirname, resolve, join } from 'node:path'
import { tmpdir } from 'node:os'

const __dirname = dirname(fileURLToPath(import.meta.url))
const vueShimPath = resolve(__dirname, 'js/highlightjs-vue.js')
const vueSrc = readFileSync(vueShimPath, 'utf8')

const tmp = mkdtempSync(join(tmpdir(), 'crit-vue-astro-'))
const tmpFile = join(tmp, 'vue.mjs')
writeFileSync(tmpFile, vueSrc)

let vue
try {
  ;({ vue } = await import(pathToFileURL(tmpFile).href))
} finally {
  rmSync(tmp, { recursive: true, force: true })
}

if (typeof vue !== 'function') {
  console.error('FAIL: could not load vue grammar from highlightjs-vue.js')
  process.exit(1)
}

hljs.registerLanguage('vue', vue)
hljs.registerLanguage('astro', hljsAstro)

let pass = 0
let fail = 0

function check(label, ok) {
  const status = ok ? 'PASS' : 'FAIL'
  if (ok) pass++; else fail++
  console.log(`${status}: ${label}`)
}

check('vue language registered', !!hljs.getLanguage('vue'))
check('astro language registered', !!hljs.getLanguage('astro'))

const vueOut = hljs.highlight(
  '<template>\n  <div>{{ msg }}</div>\n</template>\n<script>\nconst msg = "hi"\n</script>\n',
  { language: 'vue', ignoreIllegals: true }
).value
check('vue highlight emits hljs spans', vueOut.includes('hljs-'))

const astroOut = hljs.highlight(
  '---\nconst title = "Hi";\n---\n<h1>{title}</h1>\n',
  { language: 'astro', ignoreIllegals: true }
).value
check('astro highlight emits hljs spans', astroOut.includes('hljs-'))

console.log(`\n${pass} passed, ${fail} failed`)
process.exit(fail === 0 ? 0 : 1)
