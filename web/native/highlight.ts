import hljs from 'highlight.js/lib/core'
import bash from 'highlight.js/lib/languages/bash'
import css from 'highlight.js/lib/languages/css'
import diff from 'highlight.js/lib/languages/diff'
import go from 'highlight.js/lib/languages/go'
import ini from 'highlight.js/lib/languages/ini'
import javascript from 'highlight.js/lib/languages/javascript'
import json from 'highlight.js/lib/languages/json'
import markdown from 'highlight.js/lib/languages/markdown'
import python from 'highlight.js/lib/languages/python'
import rust from 'highlight.js/lib/languages/rust'
import sql from 'highlight.js/lib/languages/sql'
import swift from 'highlight.js/lib/languages/swift'
import typescript from 'highlight.js/lib/languages/typescript'
import xml from 'highlight.js/lib/languages/xml'
import yaml from 'highlight.js/lib/languages/yaml'
import { Lru } from '../src/lru'
import { reduceScope, type Scope } from './scopes'

const LANGUAGES = { bash, css, diff, go, ini, javascript, json, markdown, python, rust, sql, swift, typescript, xml, yaml }

for (const [name, language] of Object.entries(LANGUAGES)) hljs.registerLanguage(name, language)
hljs.registerAliases(['shell', 'console', 'shellsession'], { languageName: 'bash' })

export type Token = { s: string; c?: Scope }

type TreeNode = { scope?: string; children: (TreeNode | string)[] }

const cache = new Lru<string, Token[][]>(256)

function addToken(line: Token[], s: string, c: Scope | null) {
  const last = line.at(-1)

  if (last && (last.c ?? null) === c) last.s += s
  else line.push(c ? { s, c } : { s })
}

function addText(lines: Token[][], text: string, c: Scope | null) {
  const parts = text.split('\n')

  for (const [index, part] of parts.entries()) {
    if (index > 0) lines.push([])

    if (part) addToken(lines[lines.length - 1], part, c)
  }
}

function walk(node: TreeNode, inherited: Scope | null, lines: Token[][]) {
  const scope = node.scope === undefined ? inherited : reduceScope(node.scope, inherited)

  for (const child of node.children) {
    if (typeof child === 'string') addText(lines, child, scope)
    else walk(child, scope, lines)
  }
}

function plainLines(code: string): Token[][] {
  return code.split('\n').map((line) => [{ s: line }])
}

function highlighted(code: string, language: string): Token[][] {
  const result = hljs.highlight(code, { language, ignoreIllegals: true }) as unknown as { _emitter: { rootNode: TreeNode } }
  const lines: Token[][] = [[]]
  // oxlint-disable-next-line eslint/no-underscore-dangle -- highlight.js exposes its token tree only as `_emitter`
  walk(result._emitter.rootNode, null, lines)

  return lines
}

/** Lines of `{s, c?}` tokens. A language highlight.js doesn't know comes back as one plain token per line. */
export function highlightLines(code: string, lang?: string): Token[][] {
  const text = code.replace(/\n$/, '')
  const language = lang && hljs.getLanguage(lang) ? lang : undefined
  const key = `${language ?? ''}\n${text}`
  const hit = cache.get(key)

  if (hit) return hit
  const lines = language ? highlighted(text, language) : plainLines(text)
  cache.set(key, lines)

  return lines
}
