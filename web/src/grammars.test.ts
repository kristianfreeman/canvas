import { expect, test } from 'bun:test'
import { canonicalLanguage, grammarClosure } from './grammars'

test('fence languages resolve through aliases, case-insensitively', () => {
  expect(canonicalLanguage('TS')).toBe('typescript')
  expect(canonicalLanguage(' zsh ')).toBe('shellscript')
  expect(canonicalLanguage('svg')).toBe('html')
  expect(canonicalLanguage('brainfuck')).toBeUndefined()
  expect(canonicalLanguage('')).toBeUndefined()
})

test('an embedding grammar loads after the grammars it embeds', () => {
  expect(grammarClosure('html')).toEqual(['javascript', 'css', 'html'])
  expect(grammarClosure('json')).toEqual(['json'])
})
