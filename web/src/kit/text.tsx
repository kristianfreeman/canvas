import { createElement, useMemo, type ReactNode } from 'react'
import { codeBlockHtml } from '../highlight'
import { renderMarkdown, taskChange, type TaskToggle } from '../markdown'
import { cx, resolveColor, type Styled } from './util'

type HeadingProps = Styled & { level?: 1 | 2 | 3 | 4; children?: ReactNode }

export function Heading({ level = 2, className, style, children }: HeadingProps) {
  const tag = `h${Math.min(4, Math.max(1, level))}`

  return createElement(tag, { className: cx('cv-heading', `cv-h${level}`, className), style }, children)
}

type TextProps = Styled & {
  size?: 'sm' | 'md' | 'lg'
  muted?: boolean
  weight?: number | 'normal' | 'medium' | 'semibold' | 'bold'
  color?: string
  mono?: boolean
  children?: ReactNode
}

const WEIGHTS = { normal: 400, medium: 500, semibold: 600, bold: 700 }

export function Text({ size = 'md', muted, weight, color, mono, className, style, children }: TextProps) {
  return (
    <div
      className={cx('cv-text', `cv-text-${size}`, muted && 'cv-muted', mono && 'cv-mono', className)}
      style={{
        fontWeight: typeof weight === 'string' ? WEIGHTS[weight] : weight,
        color: color ? resolveColor(color) : undefined,
        ...style,
      }}
    >
      {children}
    </div>
  )
}

export function Code({ className, style, children }: Styled & { children?: ReactNode }) {
  return (
    <code className={cx('cv-code', className)} style={style}>
      {children}
    </code>
  )
}

function childText(children: ReactNode) {
  if (typeof children === 'string') return children

  return Array.isArray(children) ? children.join('') : ''
}

type CodeBlockProps = Styled & { code?: string; lang?: string; children?: ReactNode }

export function CodeBlock({ code, lang, className, style, children }: CodeBlockProps) {
  const source = code ?? childText(children)
  const html = useMemo(() => codeBlockHtml(source, lang), [source, lang])

  return <div className={cx('cv-codeblock-host', className)} style={style} dangerouslySetInnerHTML={{ __html: html }} />
}

type MarkdownProps = Styled & { source?: string; children?: ReactNode; onToggle?: (task: TaskToggle) => void }

export function Markdown({ source, className, style, children, onToggle }: MarkdownProps) {
  const text = source ?? childText(children)
  const interactive = Boolean(onToggle)
  const html = useMemo(() => renderMarkdown(text, { interactive }), [text, interactive])
  const onChange = (event: { target: EventTarget | null }) => {
    const task = taskChange(event.target)

    if (task) onToggle?.(task)
  }

  return (
    <div
      className={cx('cv-prose', className)}
      style={style}
      onChange={interactive ? onChange : undefined}
      dangerouslySetInnerHTML={{ __html: html }}
    />
  )
}

export function Kbd({ tone, className, style, children }: Styled & { tone?: 'accent'; children?: ReactNode }) {
  return (
    <kbd className={cx('cv-kbd', tone === 'accent' && 'cv-kbd-accent', className)} style={style}>
      {children}
    </kbd>
  )
}
