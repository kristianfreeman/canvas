import MarkdownIt from 'markdown-it'
import footnote from 'markdown-it-footnote'
import taskLists from 'markdown-it-task-lists'
import { codeBlockHtml } from './highlight'

const md = new MarkdownIt({ html: false, linkify: true, typographer: true })
  .use(footnote)
  .use(taskLists, { enabled: false, label: true })

md.renderer.rules.fence = (tokens, idx) => {
  const token = tokens[idx]
  const info = token.info ? md.utils.unescapeAll(token.info).trim() : ''
  const lang = info.split(/\s+/)[0] || undefined

  return codeBlockHtml(token.content, lang)
}

md.renderer.rules.footnote_caption = (tokens, idx) => {
  const meta = tokens[idx].meta as { id: number; subId: number }

  return meta.subId > 0 ? `${meta.id + 1}:${meta.subId}` : `${meta.id + 1}`
}

md.renderer.rules.code_block = (tokens, idx) => codeBlockHtml(tokens[idx].content)

/** Each list item carries the source line it starts on, from 0, so a task click can name it. */
md.core.ruler.push('canvas_item_lines', (state) => {
  for (const token of state.tokens) {
    if (token.type === 'list_item_open' && token.map) token.attrSet('data-line', String(token.map[0]))
  }
})

/** `interactive` leaves task checkboxes enabled, for Markdown whose tasks can be checked. */
export function renderMarkdown(source: string, { interactive = false } = {}): string {
  const html = md.render(source)

  return interactive ? html.replace(/(<input class="task-list-item-checkbox"[^>]*?) disabled=""/g, '$1') : html
}

export type TaskToggle = { line: number; checked: boolean }

/** The task a checkbox change inside rendered Markdown is about, or null for any other change. */
export function taskChange(target: EventTarget | null): TaskToggle | null {
  if (!(target instanceof HTMLInputElement) || !target.classList.contains('task-list-item-checkbox')) return null
  const line = Number(target.closest('li[data-line]')?.getAttribute('data-line'))

  return Number.isInteger(line) && line >= 0 ? { line, checked: target.checked } : null
}
