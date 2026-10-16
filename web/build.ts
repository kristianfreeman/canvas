/**
 * Bundles src/main.tsx and src/styles.css into one self-contained dist/index.html (inline IIFE script and CSS)
 * that WKWebView loads from file://, where module scripts are blocked. Shiki grammars are emitted separately as
 * classic scripts in dist/langs/<name>.js, which the page loads on demand. native/index.ts becomes dist/native.js,
 * the runtime the server evaluates in each JavaScriptCore context (docs/native.md).
 */
import { mkdir, rm } from 'node:fs/promises'
import { join } from 'node:path'
import type { LanguageRegistration } from 'shiki/core'
import { ALIASES, GRAMMAR_DEPS, GRAMMARS, type GrammarName } from './src/grammars'

const root = import.meta.dir
const outDir = join(root, 'dist')
const langsDir = join(outDir, 'langs')

const CSP = "default-src 'self' file: data: 'unsafe-inline' 'unsafe-eval'; connect-src 'none'"

const kb = (n: number) => `${(n / 1024).toFixed(0)} KB`

async function build(entrypoints: string[]) {
  const result = await Bun.build({
    entrypoints: entrypoints.map((entry) => join(root, entry)),
    format: 'iife',
    target: 'browser',
    minify: true,
    define: { 'process.env.NODE_ENV': '"production"' },
  })

  if (!result.success) {
    for (const log of result.logs) console.error(log)
    process.exit(1)
  }

  return result
}

async function nativeBundle() {
  const result = await build(['native/index.ts'])
  const js = (await Promise.all(result.outputs.map((output) => output.text()))).join('')

  if (!js.includes('canvasNative')) {
    console.error('build: native.js does not define canvasNative')
    process.exit(1)
  }

  return js
}

async function bundle() {
  const result = await build(['src/main.tsx', 'src/styles.css'])
  let js = ''
  let css = ''
  const texts = await Promise.all(result.outputs.map((output) => output.text()))

  for (const [index, output] of result.outputs.entries()) {
    if (output.path.endsWith('.css')) css += texts[index]
    else if (output.kind === 'entry-point' || output.path.endsWith('.js')) js += texts[index]
  }

  if (!js) {
    console.error('build: no JavaScript output')
    process.exit(1)
  }

  // Keep the inline blocks from terminating early inside the HTML parser.
  return {
    js: js.replace(/<\/script/gi, '<\\/script').replace(/<!--/g, '<\\u0021--'),
    css: css.replace(/<\/style/gi, '<\\/style'),
  }
}

function sameSet(a: readonly string[], b: readonly string[]) {
  return a.length === b.length && a.every((item) => b.includes(item))
}

/** The page resolves fences before any grammar is loaded, so its alias and dependency tables must match the grammars. */
function checkTables(name: GrammarName, own: LanguageRegistration) {
  const problems: string[] = []
  const missing = (own.aliases ?? []).filter((alias) => ALIASES[alias] !== name)

  if (missing.length) problems.push(`aliases ${missing.join(', ')} are missing from ALIASES`)

  if (!sameSet(own.embeddedLangs ?? [], GRAMMAR_DEPS[name] ?? [])) {
    problems.push(`embeds [${(own.embeddedLangs ?? []).join(', ')}] but GRAMMAR_DEPS says [${(GRAMMAR_DEPS[name] ?? []).join(', ')}]`)
  }

  return problems.map((problem) => `${name}: ${problem}`)
}

async function grammarScript(name: GrammarName) {
  const all = (await import(`shiki/langs/${name}.mjs`)).default as LanguageRegistration[]
  const own = all.filter((grammar) => grammar.name === name)

  if (own.length !== 1) throw new Error(`${name}: expected one grammar named ${name}, found ${own.length}`)
  const literal = JSON.stringify(JSON.stringify(own))
  const script = `(self.canvasGrammars=self.canvasGrammars||{})[${JSON.stringify(name)}]=JSON.parse(${literal});\n`

  return { script, problems: checkTables(name, own[0]) }
}

async function writeGrammars() {
  await rm(langsDir, { recursive: true, force: true })
  await mkdir(langsDir, { recursive: true })
  const scripts = await Promise.all(GRAMMARS.map(grammarScript))
  const problems = scripts.flatMap((entry) => entry.problems)

  if (problems.length) {
    for (const problem of problems) console.error(`build: ${problem}`)
    process.exit(1)
  }

  await Promise.all(GRAMMARS.map((name, index) => Bun.write(join(langsDir, `${name}.js`), scripts[index].script)))

  return scripts.reduce((total, entry) => total + entry.script.length, 0)
}

const { js, css } = await bundle()

const html = [
  '<!doctype html>',
  '<html lang="en">',
  '<head>',
  '<meta charset="utf-8">',
  `<meta http-equiv="Content-Security-Policy" content="${CSP}">`,
  '<meta name="viewport" content="width=device-width, initial-scale=1">',
  '<meta name="color-scheme" content="dark light">',
  '<title>Canvas</title>',
  `<style>${css}</style>`,
  '</head>',
  '<body>',
  '<div id="root"></div>',
  `<script>${js}</script>`,
  '</body>',
  '</html>',
  '',
].join('\n')

await mkdir(outDir, { recursive: true })
await Bun.write(join(outDir, 'index.html'), html)
const langBytes = await writeGrammars()
const native = await nativeBundle()
await Bun.write(join(outDir, 'native.js'), native)

console.log(`dist/index.html  ${kb(html.length)}  (js ${kb(js.length)}, css ${kb(css.length)})`)
console.log(`dist/langs/      ${kb(langBytes)}  (${GRAMMARS.length} grammars, loaded on demand)`)
console.log(`dist/native.js   ${kb(native.length)}  (JavaScriptCore runtime)`)
