import { describe, expect, test } from 'bun:test'
import { highlightLines } from './highlight'
import { reduceScope, SCOPES } from './scopes'

const scopesOf = (code: string, lang: string) => new Set(highlightLines(code, lang).flat().map((token) => token.c))

describe('reduceScope', () => {
  test('contract scopes pass through and dotted ones reduce to their head', () => {
    expect(reduceScope('keyword', null)).toBe('keyword')
    expect(reduceScope('title.function.invoke', null)).toBe('title')
    expect(reduceScope('meta.prompt', 'string')).toBe('meta')
  })

  test('scopes outside the list map to the color GitHub gives them', () => {
    expect(reduceScope('title.class', null)).toBe('type')
    expect(reduceScope('variable.language', null)).toBe('keyword')
    expect(reduceScope('attribute', null)).toBe('attr')
    expect(reduceScope('name', null)).toBe('tag')
    expect(reduceScope('operator', null)).toBe('keyword')
  })

  test('code regions reset to plain and colorless scopes inherit', () => {
    expect(reduceScope('subst', 'string')).toBeNull()
    expect(reduceScope('language:xml', 'keyword')).toBeNull()
    expect(reduceScope('emphasis', 'section')).toBe('section')
  })
})

describe('highlightLines', () => {
  test('splits lines and merges adjacent tokens of one scope', () => {
    expect(highlightLines('const a = 1\n// done\n', 'typescript')).toEqual([
      [{ s: 'const', c: 'keyword' }, { s: ' a = ' }, { s: '1', c: 'number' }],
      [{ s: '// done', c: 'comment' }],
    ])
  })

  test('a multi-line token keeps its scope on every line', () => {
    expect(highlightLines('/* a\nb */', 'javascript')).toEqual([[{ s: '/* a', c: 'comment' }], [{ s: 'b */', c: 'comment' }]])
  })

  test('template substitutions are plain inside a string', () => {
    const [line] = highlightLines('`a${b}c`', 'javascript')

    expect(line).toEqual([{ s: '`a', c: 'string' }, { s: '${b}' }, { s: 'c`', c: 'string' }])
  })

  test('aliases resolve and every scope is in the contract list', () => {
    const allowed = new Set<string | undefined>([...SCOPES, undefined])
    const samples: [string, string][] = [
      ['tsx', 'const el = <Card title="x" />'],
      ['sh', 'echo "$HOME" # hi'],
      ['toml', '[a]\nb = 1'],
      ['html', '<a href="x">y</a>'],
      ['yml', 'a: [1, true]'],
      ['py', 'def f(x): return None'],
      ['rs', 'fn main() { let x: u8 = 1; }'],
      ['diff', '+add\n-del'],
      ['swift', 'let a: Int = 1'],
      ['go', 'func main() {}'],
      ['sql', 'SELECT 1'],
      ['css', '.a { color: red }'],
      ['md', '# Hi\n\n- item `x`'],
      ['json', '{"a": 1}'],
    ]

    for (const [lang, code] of samples) {
      const found = scopesOf(code, lang)

      expect([lang, [...found].every((scope) => allowed.has(scope))]).toEqual([lang, true])
      expect([lang, found.size > 1]).toEqual([lang, true])
    }

    expect(scopesOf('+add\n-del', 'diff')).toEqual(new Set(['addition', 'deletion']))
  })

  test('unknown or missing languages give one plain token per line', () => {
    expect(highlightLines('a <b>\n\nc', 'brainfork')).toEqual([[{ s: 'a <b>' }], [{ s: '' }], [{ s: 'c' }]])
    expect(highlightLines('x')).toEqual([[{ s: 'x' }]])
  })
})
