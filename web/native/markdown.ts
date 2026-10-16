import MarkdownIt from 'markdown-it'
import footnote from 'markdown-it-footnote'
import { highlightLines, type Token as CodeToken } from './highlight'
import { footnoteId, inlines, type Inline, type Token } from './inline'

/** Same options as the web renderer (src/markdown.ts). Task items are recognized here, as markdown-it-task-lists does. */
const md = new MarkdownIt({ html: false, linkify: true, typographer: true }).use(footnote)

type Align = 'left' | 'center' | 'right' | null

export type ListItem = { task?: true; checked?: boolean; blocks: Block[] }

export type Block =
  | { t: 'h'; level: number; inl: Inline[] }
  | { t: 'p'; inl: Inline[] }
  | { t: 'quote'; blocks: Block[] }
  | { t: 'list'; ordered: boolean; start?: number; items: ListItem[] }
  | { t: 'code'; lang: string; lines: CodeToken[][] }
  | { t: 'table'; align: Align[]; head: Inline[][]; rows: Inline[][][] }
  | { t: 'hr' }
  | { t: 'footnotes'; items: { id: string; blocks: Block[] }[] }

type Cursor = { tokens: Token[]; pos: number }

const peek = (c: Cursor) => c.tokens[c.pos]

function skipPast(c: Cursor, type: string) {
  while (c.pos < c.tokens.length && c.tokens[c.pos].type !== type) c.pos++
  c.pos++
}

/** An opening token, its inline content, and everything up to its closing token. */
function inlineBlock(c: Cursor, close: string) {
  c.pos++
  const content = peek(c)?.type === 'inline' ? inlines(peek(c).children) : []
  skipPast(c, close)

  return content
}

function heading(c: Cursor): Block {
  const level = Number(peek(c).tag.slice(1))

  return { t: 'h', level, inl: inlineBlock(c, 'heading_close') }
}

const TASK = /^\[([ xX])\][ \u00a0]/

function taskMarker(first: Block | undefined) {
  if (first?.t !== 'p') return null
  const run = first.inl[0]

  if (run?.t !== 'text') return null
  const match = TASK.exec(run.s)

  return match ? { inl: first.inl, run, match } : null
}

/** Strips a leading `[ ] ` or `[x] ` from the item's first paragraph and marks the item as a task. */
function taskItem(content: Block[]): ListItem {
  const marker = taskMarker(content[0])

  if (!marker) return { blocks: content }
  const { inl, run, match } = marker
  run.s = run.s.slice(match[0].length)

  if (!run.s) inl.shift()

  return { task: true, checked: match[1] !== ' ', blocks: content }
}

function list(c: Cursor): Block {
  const open = peek(c)
  const ordered = open.type === 'ordered_list_open'
  const start = Number(open.attrGet('start') ?? 1)
  const close = ordered ? 'ordered_list_close' : 'bullet_list_close'
  const items: ListItem[] = []
  c.pos++

  while (peek(c)?.type === 'list_item_open') {
    c.pos++
    items.push(taskItem(blocks(c, 'list_item_close')))
  }

  skipPast(c, close)

  return ordered && start !== 1 ? { t: 'list', ordered, start, items } : { t: 'list', ordered, items }
}

function code(c: Cursor): Block {
  const token = c.tokens[c.pos++]
  const lang = token.info ? md.utils.unescapeAll(token.info).trim().split(/\s+/)[0] : ''

  return { t: 'code', lang, lines: highlightLines(token.content, lang || undefined) }
}

type Cell = { align: Align; inl: Inline[] }

function alignOf(token: Token): Align {
  const match = /text-align:\s*(left|center|right)/.exec(String(token.attrGet('style') ?? ''))

  return match ? (match[1] as Align) : null
}

function row(c: Cursor): Cell[] {
  const cells: Cell[] = []
  c.pos++

  while (peek(c) && peek(c).type !== 'tr_close') {
    const align = alignOf(peek(c))
    cells.push({ align, inl: inlineBlock(c, peek(c).type === 'th_open' ? 'th_close' : 'td_close') })
  }

  c.pos++

  return cells
}

function section(c: Cursor, open: string, close: string): Cell[][] {
  if (peek(c)?.type !== open) return []
  const rows: Cell[][] = []
  c.pos++

  while (peek(c)?.type === 'tr_open') rows.push(row(c))
  skipPast(c, close)

  return rows
}

function table(c: Cursor): Block {
  c.pos++
  const [head = []] = section(c, 'thead_open', 'thead_close')
  const body = section(c, 'tbody_open', 'tbody_close')
  skipPast(c, 'table_close')

  return {
    t: 'table',
    align: head.map((cell) => cell.align),
    head: head.map((cell) => cell.inl),
    rows: body.map((cells) => cells.map((cell) => cell.inl)),
  }
}

function footnotes(c: Cursor): Block {
  const items: { id: string; blocks: Block[] }[] = []
  c.pos++

  while (peek(c)?.type === 'footnote_open') {
    const id = footnoteId((peek(c).meta as { id: number }).id)
    c.pos++
    items.push({ id, blocks: blocks(c, 'footnote_close') })
  }

  skipPast(c, 'footnote_block_close')

  return { t: 'footnotes', items }
}

function nested(c: Cursor): Block {
  c.pos++

  return { t: 'quote', blocks: blocks(c, 'blockquote_close') }
}

function rule(c: Cursor): Block {
  c.pos++

  return { t: 'hr' }
}

const READERS: Record<string, (c: Cursor) => Block> = {
  heading_open: heading,
  paragraph_open: (c) => ({ t: 'p', inl: inlineBlock(c, 'paragraph_close') }),
  blockquote_open: nested,
  bullet_list_open: list,
  ordered_list_open: list,
  fence: code,
  code_block: code,
  table_open: table,
  hr: rule,
  footnote_block_open: footnotes,
}

/** Blocks up to (and past) a `close` token, or to the end. Tokens with no reader are skipped. */
function blocks(c: Cursor, close?: string): Block[] {
  const out: Block[] = []

  while (c.pos < c.tokens.length) {
    const token = peek(c)

    if (token.type === close) {
      c.pos++
      break
    }

    const reader = READERS[token.type]

    if (reader) out.push(reader(c))
    else c.pos++
  }

  return out
}

/** The `Markdown.blocks` prop for a Markdown source (docs/native.md, Markdown). */
export function markdownBlocks(source: string): Block[] {
  return blocks({ tokens: md.parse(source, {}), pos: 0 })
}
