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

export function renderMarkdown(source: string): string {
  return md.render(source)
}
