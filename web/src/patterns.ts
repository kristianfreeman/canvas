import type { LanguageRegistration } from 'shiki/core'

/** Rule keys that hold a regex. `end` and `while` with back-references are rebuilt per match, so they can't be precompiled. */
const STATIC_KEYS = new Set(['match', 'begin'])
const DYNAMIC_KEYS = new Set(['end', 'while'])
const BACK_REFERENCE = /\\\d/

function isPrecompilable(key: string, value: unknown): value is string {
  if (typeof value !== 'string') return false

  return STATIC_KEYS.has(key) || (DYNAMIC_KEYS.has(key) && !BACK_REFERENCE.test(value))
}

function collect(node: unknown, out: Set<string>) {
  if (Array.isArray(node)) {
    for (const item of node) collect(item, out)

    return
  }

  if (!node || typeof node !== 'object') return

  for (const [key, value] of Object.entries(node)) {
    if (isPrecompilable(key, value)) out.add(value)
    else if (typeof value === 'object') collect(value, out)
  }
}

/** Replaces each escape `\X` through `swap`, the way vscode-textmate scans a source (an escape consumes its next character). */
function mapEscapes(source: string, swap: (char: string) => string) {
  return source.replace(/\\([\s\S])/g, (_escape, char: string) => swap(char))
}

/**
 * The exact strings vscode-textmate hands the regex engine for one grammar pattern: `\z` rewritten, and a pattern with
 * `\A` or `\G` expanded into its four anchor variants, where a disallowed anchor becomes `\uFFFF`. Without anchors the
 * variants coincide, leaving one source.
 */
export function scannerSources(pattern: string): string[] {
  const source = mapEscapes(pattern, (char) => (char === 'z' ? '$(?!\\n)(?<!\\n)' : `\\${char}`))

  const variant = (allowA: boolean, allowG: boolean) =>
    mapEscapes(source, (char) => {
      if (char === 'A') return allowA ? '\\A' : '\\\uFFFF'

      if (char === 'G') return allowG ? '\\G' : '\\\uFFFF'

      return `\\${char}`
    })

  return [...new Set([variant(false, false), variant(false, true), variant(true, false), variant(true, true)])]
}

/** Every regex source the grammars can compile up front, deduplicated, in grammar order. */
export function grammarSources(grammars: readonly LanguageRegistration[]): string[] {
  const patterns = new Set<string>()
  collect(grammars, patterns)
  const sources = new Set<string>()

  for (const pattern of patterns) {
    for (const source of scannerSources(pattern)) sources.add(source)
  }

  return [...sources]
}
