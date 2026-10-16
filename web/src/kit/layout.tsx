import type { CSSProperties, ReactNode } from 'react'
import { cx, px, type Styled } from './util'

type Align = 'start' | 'center' | 'end' | 'stretch' | 'baseline'

type Justify = 'start' | 'center' | 'end' | 'between' | 'around' | 'evenly'

const ALIGN: Record<Align, string> = {
  start: 'flex-start', center: 'center', end: 'flex-end', stretch: 'stretch', baseline: 'baseline',
}

const JUSTIFY: Record<Justify, string> = {
  start: 'flex-start', center: 'center', end: 'flex-end',
  between: 'space-between', around: 'space-around', evenly: 'space-evenly',
}

type StackProps = Styled & { gap?: number | string; align?: Align; children?: ReactNode }

export function Stack({ gap = 12, align, className, style, children }: StackProps) {
  return (
    <div
      className={cx('cv-stack', className)}
      style={{ gap: px(gap), alignItems: align ? ALIGN[align] : undefined, ...style }}
    >
      {children}
    </div>
  )
}

type RowProps = Styled & {
  gap?: number | string
  align?: Align
  justify?: Justify
  wrap?: boolean
  children?: ReactNode
}

export function Row({ gap = 12, align = 'center', justify, wrap, className, style, children }: RowProps) {
  return (
    <div
      className={cx('cv-row', className)}
      style={{
        gap: px(gap),
        alignItems: ALIGN[align],
        justifyContent: justify ? JUSTIFY[justify] : undefined,
        flexWrap: wrap ? 'wrap' : undefined,
        ...style,
      }}
    >
      {children}
    </div>
  )
}

type GridProps = Styled & { columns?: number | string; gap?: number | string; children?: ReactNode }

export function Grid({ columns = 2, gap = 12, className, style, children }: GridProps) {
  const template = typeof columns === 'number' ? `repeat(${columns}, minmax(0, 1fr))` : columns

  return (
    <div className={cx('cv-grid', className)} style={{ gridTemplateColumns: template, gap: px(gap), ...style }}>
      {children}
    </div>
  )
}

export function Divider({ className, style }: Styled) {
  return <hr className={cx('cv-divider', className)} style={style} />
}

export function Spacer({ size, className, style }: Styled & { size?: number | string }) {
  const sized: CSSProperties = size === undefined ? { flex: 1 } : { flex: 'none', width: px(size), height: px(size) }

  return <div className={cx('cv-spacer', className)} style={{ ...sized, ...style }} aria-hidden />
}
