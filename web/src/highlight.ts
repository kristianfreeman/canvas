import { createHighlighterCoreSync, type HighlighterCore, type LanguageRegistration } from 'shiki/core'
import { createJavaScriptRegexEngine, defaultJavaScriptRegexConstructor } from 'shiki/engine/javascript'
import githubDark from 'shiki/themes/github-dark-default.mjs'
import githubLight from 'shiki/themes/github-light-default.mjs'
import { canonicalLanguage, grammarClosure, type GrammarName } from './grammars'
import { Lru } from './lru'
import { grammarSources } from './patterns'

let highlighter: HighlighterCore | undefined
const loaded = new Set<string>()
const arrived = new Map<GrammarName, LanguageRegistration[]>()
const requested = new Set<GrammarName>()
const cache = new Lru<string, string>(256)
const readyListeners = new Set<(name: GrammarName) => void>()
let fetchGrammar: (name: GrammarName) => void = () => {}

/** Compiled regexes by source, shared with the engine so precompiled ones are never converted again. */
const regexes = new Map<string, RegExp | Error>()
const compileRegex = (source: string) => defaultJavaScriptRegexConstructor(source, { target: 'auto' })
/** Grammars whose regexes are all compiled; only these are cheap enough to highlight inside a budget. */
const warmed = new Set<GrammarName>()
/** The last measured highlighting cost per grammar, in ms per character. */
const costPerChar = new Map<GrammarName, number>()

type Budget = { limit: number; spent: number; now: () => number }
let budget: Budget | undefined
const wallClock = () => performance.now()

export function getHighlighter() {
  highlighter ??= createHighlighterCoreSync({
    themes: [githubDark, githubLight],
    langs: [],
    engine: createJavaScriptRegexEngine({ forgiving: true, cache: regexes, regexConstructor: compileRegex }),
  })

  return highlighter
}

/** How grammar scripts are fetched. The page loads `langs/<name>.js`; without a loader, unloaded languages stay plain. */
export function setGrammarFetcher(fetcher: (name: GrammarName) => void) {
  fetchGrammar = fetcher
}

export function onGrammarReady(listener: (name: GrammarName) => void) {
  readyListeners.add(listener)

  return () => readyListeners.delete(listener)
}

function activate(name: GrammarName) {
  const closure = grammarClosure(name)

  if (loaded.has(name) || !closure.every((part) => arrived.has(part))) return
  getHighlighter().loadLanguageSync(closure.flatMap((part) => arrived.get(part)!))
  for (const part of closure) loaded.add(part)

  for (const listener of readyListeners) listener(name)
}

/** Called with a grammar script's payload. Activates it and anything that was waiting on it as a dependency. */
export function registerGrammar(name: GrammarName, grammars: LanguageRegistration[]) {
  arrived.set(name, grammars)

  for (const waiting of requested) activate(waiting)
}

export function requestGrammar(name: GrammarName) {
  if (loaded.has(name)) return
  requested.add(name)

  for (const part of grammarClosure(name)) {
    if (!arrived.has(part)) fetchGrammar(part)
  }

  activate(name)
}

export function isGrammarLoaded(name: string) {
  return loaded.has(name)
}

/**
 * JavaScriptCore compiles a regex on its first exec, separately for Latin-1 and UTF-16 strings, and that costs more
 * than converting the pattern. One probe of each width compiles both.
 */
const PROBES = ['a', 'a\u2713']

function convertRegex(source: string) {
  try {
    const regex = compileRegex(source)
    regexes.set(source, regex)

    return regex
  } catch (error) {
    regexes.set(source, error as Error)

    return undefined
  }
}

function* compileSteps(source: string) {
  const regex = convertRegex(source)
  yield

  for (const probe of regex ? PROBES : []) {
    regex!.lastIndex = 0
    regex!.exec(probe)
    yield
  }
}

/**
 * Compiles a loaded grammar's regexes a step at a time, so the first highlight in that language doesn't stall for
 * hundreds of milliseconds. Regexes the engine already holds are skipped.
 */
export function* warmGrammar(name: GrammarName): Generator<void, void, unknown> {
  if (warmed.has(name) || !loaded.has(name)) return

  for (const source of grammarSources(grammarClosure(name).flatMap((part) => arrived.get(part) ?? []))) {
    if (!regexes.has(source)) yield* compileSteps(source)
  }

  warmed.add(name)
}

/**
 * Runs `fn` with highlighting limited to about `limit` ms in total. Blocks that don't fit, or whose grammar isn't
 * warmed yet, render plain with `data-deferred`; cached blocks are always highlighted.
 */
export function withHighlightBudget<T>(limit: number, fn: () => T, now: () => number = wallClock): T {
  const outer = budget
  budget = { limit, spent: 0, now }

  try {
    return fn()
  } finally {
    budget = outer
  }
}

function affordable(source: string, lang: GrammarName) {
  if (!budget) return true
  const perChar = costPerChar.get(lang)

  if (perChar === undefined || !warmed.has(lang)) return false

  return budget.spent + perChar * source.length <= budget.limit
}

export function escapeHtml(text: string) {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
}

const cacheKey = (source: string, lang: GrammarName) => `${lang}\u0000${source}`

function shikiHtml(source: string, lang: GrammarName) {
  const clock = budget?.now ?? wallClock
  const start = clock()
  const html = getHighlighter().codeToHtml(source, {
    lang,
    themes: { dark: 'github-dark-default', light: 'github-light-default' },
    defaultColor: false,
  })
  const elapsed = clock() - start
  costPerChar.set(lang, elapsed / Math.max(1, source.length))

  if (budget) budget.spent += elapsed
  cache.set(cacheKey(source, lang), html)

  return html
}

function plainPre(source: string, attribute = '') {
  return `<pre class="shiki plain"${attribute}><code>${escapeHtml(source)}</code></pre>`
}

function loadedLanguage(lang: GrammarName) {
  if (!loaded.has(lang)) requestGrammar(lang)

  return loaded.has(lang)
}

function highlightLoaded(source: string, lang: GrammarName) {
  const hit = cache.get(cacheKey(source, lang))

  if (hit !== undefined) return hit

  if (!affordable(source, lang)) return plainPre(source, ` data-deferred="${lang}"`)

  try {
    return shikiHtml(source, lang)
  } catch (error) {
    console.warn('[canvas] highlight failed', error)

    return plainPre(source)
  }
}

/**
 * Returns a `<pre class="shiki">` block whose spans carry `--shiki-dark` and `--shiki-light`; CSS picks one per theme.
 * A known language whose grammar hasn't loaded yet renders plain with `data-pending`, and the grammar is requested.
 */
export function highlight(code: string, lang?: string): string {
  const source = code.replace(/\n$/, '')
  const resolved = canonicalLanguage(lang)

  if (!resolved) return plainPre(source)

  if (!loadedLanguage(resolved)) return plainPre(source, ` data-pending="${resolved}"`)

  return highlightLoaded(source, resolved)
}

export function codeBlockHtml(code: string, lang?: string) {
  const label = lang ? `<span class="cv-codeblock-lang">${escapeHtml(lang)}</span>` : ''

  return `<div class="cv-codeblock">${label}${highlight(code, lang)}</div>`
}
