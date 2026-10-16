/** The highlight scopes Swift colors (docs/native.md, Highlighting). */
export const SCOPES = [
  'keyword', 'string', 'number', 'comment', 'title', 'type', 'attr', 'variable', 'literal', 'built_in', 'meta',
  'symbol', 'regexp', 'addition', 'deletion', 'punctuation', 'property', 'tag', 'section',
] as const

export type Scope = (typeof SCOPES)[number]

const KNOWN = new Set<string>(SCOPES)

/** highlight.js scopes outside the list, by the color GitHub's themes give them. `null` means plain text. */
const MAPPED: Record<string, Scope | null> = {
  'title.class': 'type',
  'title.class.inherited': 'type',
  'variable.language': 'keyword',
  'char.escape': 'string',
  'selector-tag': 'tag',
  'selector-id': 'attr',
  'selector-class': 'attr',
  'selector-attr': 'attr',
  'selector-pseudo': 'attr',
  'template-tag': 'keyword',
  'template-variable': 'variable',
  doctag: 'keyword',
  operator: 'keyword',
  attribute: 'attr',
  name: 'tag',
  bullet: 'punctuation',
  code: 'string',
  formula: 'string',
  link: 'string',
  quote: 'comment',
  subst: null,
  params: null,
}

/**
 * The contract scope for a highlight.js scope nested inside `inherited`. Code regions (`subst`, `params`, embedded
 * languages) reset to plain; scopes with no color of their own (`emphasis`, `function`) keep the enclosing one.
 */
export function reduceScope(scope: string, inherited: Scope | null): Scope | null {
  if (scope in MAPPED) return MAPPED[scope]

  if (scope.startsWith('language:')) return null
  const top = scope.split('.')[0]

  if (KNOWN.has(top)) return top as Scope

  return top in MAPPED ? MAPPED[top] : inherited
}
