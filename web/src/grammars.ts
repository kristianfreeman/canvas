/** Grammars shipped as `dist/langs/<name>.js`. Each script holds only its own grammar; `GRAMMAR_DEPS` lists the embedded ones. */
export const GRAMMARS = [
  'typescript', 'tsx', 'javascript', 'jsx', 'json', 'shellscript', 'python', 'swift',
  'go', 'rust', 'html', 'css', 'yaml', 'toml', 'markdown', 'sql', 'diff',
] as const

export type GrammarName = (typeof GRAMMARS)[number]

export const GRAMMAR_DEPS: Partial<Record<GrammarName, GrammarName[]>> = { html: ['javascript', 'css'] }

export const COMMON_GRAMMARS: GrammarName[] = ['typescript', 'tsx', 'javascript', 'json', 'shellscript', 'python', 'swift', 'diff']

/** Includes every alias the grammars declare themselves, since they aren't loaded when a fence is resolved; build.ts checks this. */
export const ALIASES: Record<string, GrammarName> = {
  bash: 'shellscript',
  sh: 'shellscript',
  zsh: 'shellscript',
  shell: 'shellscript',
  console: 'shellscript',
  terminal: 'shellscript',
  js: 'javascript',
  mjs: 'javascript',
  cjs: 'javascript',
  ts: 'typescript',
  mts: 'typescript',
  cts: 'typescript',
  jsonc: 'json',
  json5: 'json',
  yml: 'yaml',
  md: 'markdown',
  py: 'python',
  rs: 'rust',
  golang: 'go',
  patch: 'diff',
  htm: 'html',
  xml: 'html',
  svg: 'html',
}

const NAMES = new Set<string>(GRAMMARS)

export function canonicalLanguage(lang: string | undefined): GrammarName | undefined {
  const name = lang?.trim().toLowerCase()

  if (!name) return undefined

  if (NAMES.has(name)) return name as GrammarName

  return ALIASES[name]
}

/** The grammar and its embedded grammars, dependencies first. */
export function grammarClosure(name: GrammarName): GrammarName[] {
  return [...(GRAMMAR_DEPS[name] ?? []), name]
}
