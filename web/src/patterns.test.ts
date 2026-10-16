import { expect, test } from 'bun:test'
import { createHighlighterCoreSync, type LanguageRegistration } from 'shiki/core'
import { createJavaScriptRegexEngine, defaultJavaScriptRegexConstructor } from 'shiki/engine/javascript'
import shellscript from 'shiki/langs/shellscript.mjs'
import swift from 'shiki/langs/swift.mjs'
import githubDark from 'shiki/themes/github-dark-default.mjs'
import { grammarSources, scannerSources } from './patterns'

test('scanner sources rewrite \\z and expand \\A and \\G into the four anchor variants', () => {
  expect(scannerSources('a\\z')).toEqual(['a$(?!\\n)(?<!\\n)'])
  expect(scannerSources('\\Gx|\\Ay')).toEqual([
    '\\\uFFFFx|\\\uFFFFy',
    '\\Gx|\\\uFFFFy',
    '\\\uFFFFx|\\Ay',
    '\\Gx|\\Ay',
  ])
  expect(scannerSources('\\\\G\\d')).toEqual(['\\\\G\\d'])
})

test('grammar sources skip end patterns with back-references but keep static ones', () => {
  const grammar = {
    name: 'x',
    scopeName: 'source.x',
    patterns: [{ begin: '(["\'])', end: '\\1', patterns: [{ match: 'a(b)\\1' }] }],
    repository: { r: { begin: 'q', end: 'z', while: '^\\s' } },
  } as unknown as LanguageRegistration

  expect(grammarSources([grammar]).toSorted()).toEqual(['(["\'])', '^\\s', 'a(b)\\1', 'q', 'z'])
})

const construct = (source: string) => defaultJavaScriptRegexConstructor(source, { target: 'auto' })

const SWIFT = 'let panel = CanvasPanel(contentRect: frame)\npanel.level = .floating\n/// docs\nstruct A: B { var c = "\\(d)" }\n'
const SHELL = '# comment\ncanvas show approve.tsx --wait --data \'{"plan":"deploy"}\' | jq -r .decision\nfor f in *; do echo "$f"; done\n'

test.each([
  ['swift', swift, SWIFT],
  ['shellscript', shellscript, SHELL],
] as const)('after precompiling %s, highlighting compiles no further regexes', (lang, grammars, code) => {
  const cache = new Map<string, RegExp | Error>()
  const highlighter = createHighlighterCoreSync({
    themes: [githubDark],
    langs: [grammars],
    engine: createJavaScriptRegexEngine({ forgiving: true, cache, regexConstructor: construct }),
  })

  for (const source of grammarSources(grammars)) {
    try {
      cache.set(source, construct(source))
    } catch (error) {
      cache.set(source, error as Error)
    }
  }

  const before = cache.size
  const html = highlighter.codeToHtml(code, { lang, theme: 'github-dark-default' })

  expect(html).toContain('<span style="color:')
  expect(cache.size).toBe(before)
})
