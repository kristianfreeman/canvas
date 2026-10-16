import type MarkdownIt from 'markdown-it'

export type Token = ReturnType<InstanceType<typeof MarkdownIt>['parse']>[number]

export type Inline =
  | { t: 'text'; s: string; b?: true; i?: true; del?: true }
  | { t: 'code'; s: string }
  | { t: 'link'; href: string; inl: Inline[] }
  | { t: 'br' }
  | { t: 'fnref'; id: string; n: number }

type TextRun = Extract<Inline, { t: 'text' }>

type State = { targets: Inline[][]; b: number; i: number; del: number }

export const footnoteId = (index: number) => `fn${index + 1}`

function target(state: State) {
  return state.targets[state.targets.length - 1]
}

function sameStyle(run: TextRun, state: State) {
  return Boolean(run.b) === state.b > 0 && Boolean(run.i) === state.i > 0 && Boolean(run.del) === state.del > 0
}

function addText(state: State, s: string) {
  if (!s) return
  const runs = target(state)
  const last = runs.at(-1)

  if (last?.t === 'text' && sameStyle(last, state)) {
    last.s += s

    return
  }

  const run: TextRun = { t: 'text', s }

  if (state.b > 0) run.b = true

  if (state.i > 0) run.i = true

  if (state.del > 0) run.del = true
  runs.push(run)
}

function openLink(state: State, token: Token) {
  const link = { t: 'link' as const, href: String(token.attrGet('href') ?? ''), inl: [] as Inline[] }
  target(state).push(link)
  state.targets.push(link.inl)
}

type Handler = (state: State, token: Token) => void

const HANDLERS: Record<string, Handler> = {
  text: (state, token) => addText(state, token.content),
  softbreak: (state) => addText(state, ' '),
  hardbreak: (state) => target(state).push({ t: 'br' }),
  code_inline: (state, token) => target(state).push({ t: 'code', s: token.content }),
  strong_open: (state) => state.b++,
  strong_close: (state) => state.b--,
  em_open: (state) => state.i++,
  em_close: (state) => state.i--,
  s_open: (state) => state.del++,
  s_close: (state) => state.del--,
  link_open: openLink,
  link_close: (state) => state.targets.length > 1 && state.targets.pop(),
  footnote_ref: (state, token) => {
    const meta = token.meta as { id: number }
    target(state).push({ t: 'fnref', id: footnoteId(meta.id), n: meta.id + 1 })
  },
}

/** Inline runs from an `inline` token's children. Images keep their alt text; raw HTML is already text. */
export function inlines(children: Token[] | null): Inline[] {
  const out: Inline[] = []
  const state: State = { targets: [out], b: 0, i: 0, del: 0 }

  for (const token of children ?? []) {
    const handler = HANDLERS[token.type]

    if (handler) handler(state, token)
    else addText(state, token.content)
  }

  return out
}
