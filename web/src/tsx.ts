import { transform } from 'sucrase'
import * as React from 'react'
import { isValidElement } from 'react'
import * as ReactDOM from 'react-dom'
import * as ReactDOMClient from 'react-dom/client'
import * as JSXRuntime from 'react/jsx-runtime'
import { kit } from './kit'
import { Lru } from './lru'
import { AuthorError, SOURCE_URL } from './store'

const MODULES: Record<string, unknown> = {
  react: React,
  'react/jsx-runtime': JSXRuntime,
  'react/jsx-dev-runtime': JSXRuntime,
  'react-dom': ReactDOM,
  'react-dom/client': ReactDOMClient,
  canvas: kit,
}

class CompileError extends AuthorError {
  frame?: string
}

function codeFrame(source: string, line: number, column: number) {
  const lines = source.replace(/\s+$/, '').split('\n')
  const start = Math.max(1, line - 2)
  const end = Math.min(lines.length, line + 2)
  const width = String(end).length
  const out: string[] = []

  for (let n = start; n <= end; n++) {
    const marker = n === line ? '>' : ' '
    out.push(`${marker} ${String(n).padStart(width)} | ${lines[n - 1]}`)

    if (n === line) out.push(`  ${' '.repeat(width)} | ${' '.repeat(Math.max(0, column - 1))}^`)
  }

  return out.join('\n')
}

const compiled = new Lru<string, string>(32)

function transformSource(source: string): string {
  try {
    return transform(source, {
      transforms: ['typescript', 'jsx', 'imports'],
      jsxRuntime: 'classic',
      jsxPragma: 'React.createElement',
      jsxFragmentPragma: 'React.Fragment',
      production: true,
      filePath: SOURCE_URL,
    }).code
  } catch (error) {
    const err = error as Error & { loc?: { line: number; column: number } }
    const message = err.message.replace(/^Error transforming [^:]*:\s*/, '')
    const compileError = new CompileError(`Syntax error: ${message}`)

    if (err.loc) compileError.frame = codeFrame(source, err.loc.line, err.loc.column)
    throw compileError
  }
}

function compile(source: string): string {
  const hit = compiled.get(source)

  if (hit !== undefined) return hit
  const code = transformSource(source)
  compiled.set(source, code)

  return code
}

function requireShim(name: string) {
  if (Object.prototype.hasOwnProperty.call(MODULES, name)) return MODULES[name]
  throw new AuthorError(`Cannot import '${name}'. Only 'react' and 'canvas' can be imported.`)
}

/** Compiles and evaluates a TSX module, returning its default export (a component or an element). */
export function evaluateTsx(source: string): unknown {
  const code = compile(source)
  const module: { exports: Record<string, unknown> & { default?: unknown } } = { exports: {} }
  // Indirect eval of a one-line wrapper keeps stack line numbers equal to source lines and lets JSC honor sourceURL.
  // oxlint-disable-next-line eslint/no-eval -- evaluating agent-supplied TSX is the product; new Function shifts stack lines by 2 in WebKit
  const factory = (0, eval)(`(function (require, module, exports, React) {${code}\n})\n//# sourceURL=${SOURCE_URL}`)
  factory(requireShim, module, module.exports, React)
  const exported = module.exports as unknown
  const value = module.exports.default ?? (typeof exported === 'function' ? exported : undefined)

  if (typeof value === 'function' || isValidElement(value)) return value

  if (value === undefined) {
    throw new AuthorError('The file has no default export. Add `export default function App() { ... }`.')
  }

  throw new AuthorError(`The default export must be a React component, got ${typeof value}.`)
}
