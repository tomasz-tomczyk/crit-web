// Smoke test for the patched highlight.js markdown grammar in crit-web.
// Run: node assets/test-markdown-patch.mjs   (from crit-web/ root)
//   or: node test-markdown-patch.mjs         (from crit-web/assets/)
//
// Unlike crit/ (which loads a concatenated bundle in a vm sandbox), crit-web
// uses esbuild + npm imports. We import highlight.js + the patch directly —
// that's exactly the modules that ship in the production bundle.

import hljs from 'highlight.js'
import { readFileSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { dirname, resolve, join } from 'node:path'
import { tmpdir } from 'node:os'

const __dirname = dirname(fileURLToPath(import.meta.url))
const patchPath = resolve(__dirname, 'js/highlight-markdown-patch.js')
const patchSrc = readFileSync(patchPath, 'utf8')

// crit-web's package.json sets "type": "commonjs", so the .js patch file is
// CJS to Node. esbuild handles ESM .js fine at bundle time; here we just copy
// the source into a temp .mjs file and import it. Same module evaluated, no
// build step.
const tmp = mkdtempSync(join(tmpdir(), 'crit-md-patch-'))
const tmpFile = join(tmp, 'patch.mjs')
writeFileSync(tmpFile, patchSrc)

let registerMarkdownPatch
try {
  ;({ registerMarkdownPatch } = await import(pathToFileURL(tmpFile).href))
} finally {
  rmSync(tmp, { recursive: true, force: true })
}

if (typeof registerMarkdownPatch !== 'function') {
  console.error('FAIL: could not load registerMarkdownPatch from patch source')
  process.exit(1)
}

registerMarkdownPatch(hljs)

if (!hljs.getLanguage('markdown')) {
  console.error('FAIL: markdown language not registered')
  process.exit(1)
}

let pass = 0
let fail = 0

function check(label, input, predicate) {
  const out = hljs.highlight(input, { language: 'markdown' }).value
  const ok = predicate(out)
  const status = ok ? 'PASS' : 'FAIL'
  if (ok) pass++; else fail++
  console.log(`${status}: ${label}`)
  if (!ok) {
    console.log('  input:    ' + JSON.stringify(input))
    console.log('  output:   ' + out)
  }
}

// Helpers
const containsAnyEmphasisWith = (s, sub) =>
  /<span class="hljs-emphasis">[^<]*<\/span>/.test(s) &&
  /<span class="hljs-emphasis">([^<]*)<\/span>/g.exec(s) &&
  Array.from(s.matchAll(/<span class="hljs-emphasis">([^<]*)<\/span>/g)).some(m => m[1].includes(sub))

// --- hljs#4279: intraword underscore must NOT trigger italic ---
check(
  ':no_entry: should not italicize "entry"',
  ":no_entry:\nI'm not italic.",
  (out) => !containsAnyEmphasisWith(out, 'entry')
)

check(
  'flutter_eval.json should not italicize "eval"',
  'flutter_eval.json',
  (out) => !containsAnyEmphasisWith(out, 'eval')
)

check(
  '_id should not italicize',
  'the _id field',
  (out) => !/<span class="hljs-emphasis">/.test(out)
)

check(
  'snake__case should not bold "case"',
  'snake__case identifier',
  (out) => !/<span class="hljs-strong">/.test(out)
)

// --- hljs#3719: bare *** line should be horizontal rule, not bold ---
check(
  '*** on its own line is hljs-section (rule), not hljs-strong',
  'before\n***\nafter',
  (out) => out.includes('<span class="hljs-section">***</span>') &&
           !/<span class="hljs-strong">/.test(out)
)

check(
  '--- on its own line is hljs-section (rule)',
  'before\n---\nafter',
  // It can match either as a rule or as a setext heading underline depending
  // on context; both are acceptable. What we DON'T want is hljs-strong.
  (out) => !/<span class="hljs-strong">/.test(out)
)

check(
  '___ on its own line is hljs-section (rule), not hljs-strong',
  'before\n___\nafter',
  (out) => out.includes('<span class="hljs-section">___</span>') &&
           !/<span class="hljs-strong">/.test(out)
)

// --- Regression checks: still highlight legitimate emphasis/strong ---
check(
  '**bold text** is still hljs-strong',
  '**bold text**',
  (out) => /<span class="hljs-strong">\*\*bold text\*\*<\/span>/.test(out)
)

check(
  '*italic text* is still hljs-emphasis',
  '*italic text*',
  (out) => /<span class="hljs-emphasis">\*italic text\*<\/span>/.test(out)
)

check(
  '_italic_ (whitespace-bounded) is still hljs-emphasis',
  'this is _italic_ here',
  (out) => /<span class="hljs-emphasis">_italic_<\/span>/.test(out)
)

check(
  '__bold__ (whitespace-bounded) is still hljs-strong',
  'this is __bold__ here',
  (out) => /<span class="hljs-strong">__bold__<\/span>/.test(out)
)

// --- Italic/bold bleed across code spans (notification-plan.md screenshot) ---

// `*_id` should be a code span; surrounding text must NOT be in emphasis.
check(
  'backtick code span containing `*_id` is wrapped in hljs-code',
  '`*_id` fields — validate as *UUID* before any database query',
  (out) => /<span class="hljs-code">`\*_id`<\/span>/.test(out)
)

check(
  '"fields — validate as " (after `*_id`) is NOT inside hljs-emphasis',
  '`*_id` fields — validate as *UUID* before any database query',
  (out) => !containsAnyEmphasisWith(out, 'fields')
)

check(
  '*UUID* IS still wrapped in hljs-emphasis',
  '`*_id` fields — validate as *UUID* before any database query',
  (out) => /<span class="hljs-emphasis">\*UUID\*<\/span>/.test(out)
)

check(
  '" before any database query" (after *UUID*) is NOT inside hljs-emphasis',
  '`*_id` fields — validate as *UUID* before any database query',
  (out) => !containsAnyEmphasisWith(out, 'database query')
)

// "src/**/*.go" — neither bold nor italic should match.
check(
  '"src/**/*.go" produces no hljs-strong',
  '"src/**/*.go"',
  (out) => !/<span class="hljs-strong">/.test(out)
)

check(
  '"src/**/*.go" produces no hljs-emphasis',
  '"src/**/*.go"',
  (out) => !/<span class="hljs-emphasis">/.test(out)
)

check(
  '"internal/*.go" produces no hljs-emphasis',
  '"internal/*.go"',
  (out) => !/<span class="hljs-emphasis">/.test(out)
)

// Multiple code spans on one line.
check(
  'two backtick spans both render as hljs-code',
  'enforce `Content-Type: application/json`; reject `text/plain`',
  (out) => {
    const matches = Array.from(out.matchAll(/<span class="hljs-code">`[^`]+`<\/span>/g))
    return matches.length === 2
  }
)

// `Timestamps — always use *UTC*, never local time` — *UTC* is fine, the
// rest of the line should not be italicized.
check(
  '*UTC* is hljs-emphasis but " never local time" is NOT',
  'Timestamps — always use *UTC*, never local time',
  (out) =>
    /<span class="hljs-emphasis">\*UTC\*<\/span>/.test(out) &&
    !containsAnyEmphasisWith(out, 'never local time')
)

// Regression: an unterminated `*` at the end of a string literal must not
// open italic that bleeds into the rest of the file.
check(
  'unterminated trailing `*` does not open hljs-emphasis',
  'first line has *no closer\nsecond line is plain',
  (out) => !/<span class="hljs-emphasis">/.test(out)
)

check(
  '***bold-italic*** still gets hljs-strong',
  '***bold-italic***',
  (out) => /<span class="hljs-strong">/.test(out)
)

// --- Setext heading must require a paragraph line, not list/HR (CommonMark §4.3) ---
const yamlFrontmatter = '---\npaths:\n  - "src/**/*.go"\n  - "internal/*.go"\n---'

check(
  'YAML frontmatter: opening --- is hljs-section',
  yamlFrontmatter,
  (out) => /^<span class="hljs-section">---<\/span>/.test(out)
)

check(
  'YAML frontmatter: closing --- is hljs-section (HR), not part of setext heading',
  yamlFrontmatter,
  (out) => /<span class="hljs-section">---<\/span>$/.test(out)
)

check(
  'YAML frontmatter: "src/**/*.go" content is NOT inside any hljs-section span',
  yamlFrontmatter,
  (out) => {
    const sections = Array.from(out.matchAll(/<span class="hljs-section">([\s\S]*?)<\/span>/g))
    return sections.every(m => !m[1].includes('src/') && !m[1].includes('internal/'))
  }
)

check(
  'YAML frontmatter: both `  -` bullets render as hljs-bullet',
  yamlFrontmatter,
  (out) => {
    const bullets = Array.from(out.matchAll(/<span class="hljs-bullet">\s*-<\/span>/g))
    return bullets.length === 2
  }
)

// Regression: ATX headings still work.
check(
  'ATX heading `# Title` is hljs-section',
  '# Title',
  (out) => /<span class="hljs-section">#\s*Title<\/span>/.test(out)
)

// Regression: legitimate setext heading with paragraph line still matches.
check(
  'legitimate setext heading `Heading\\n---` still matches as hljs-section',
  'Heading\n---',
  (out) => /<span class="hljs-section">/.test(out) && out.includes('Heading')
)

// Regression: list followed by paragraph break + HR still works.
check(
  'list + blank line + --- still produces a horizontal rule',
  '- item\n\n---',
  (out) =>
    /<span class="hljs-bullet">-<\/span>/.test(out) &&
    /<span class="hljs-section">---<\/span>/.test(out)
)

// --- Sentinel check: confirm the patch source contains the version marker ---
check(
  'patch sentinel CRIT_MD_PATCH_v1 present in patch source',
  '',
  () => patchSrc.includes('CRIT_MD_PATCH_v1')
)

console.log(`\n${pass} passed, ${fail} failed`)
process.exit(fail > 0 ? 1 : 0)
