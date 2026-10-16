import type { ReactNode } from 'react'
import { cssVars, cx, keyed, px, resolveColor, type Styled } from './util'

type CardProps = Styled & {
  title?: ReactNode
  subtitle?: ReactNode
  actions?: ReactNode
  padding?: number | string
  children?: ReactNode
}

export function Card({ title, subtitle, actions, padding = 16, className, style, children }: CardProps) {
  const hasHeader = title !== undefined || subtitle !== undefined || actions !== undefined

  return (
    <section className={cx('cv-card', className)} style={{ padding: px(padding), ...style }}>
      {hasHeader && (
        <header className="cv-card-header">
          <div className="cv-card-titles">
            {title !== undefined && <div className="cv-card-title">{title}</div>}
            {subtitle !== undefined && <div className="cv-card-subtitle">{subtitle}</div>}
          </div>
          {actions !== undefined && <div className="cv-card-actions">{actions}</div>}
        </header>
      )}
      {children}
    </section>
  )
}

type StatProps = Styled & {
  label: ReactNode
  value: ReactNode
  delta?: number | string
  invertDelta?: boolean
  hint?: ReactNode
  color?: string
  children?: ReactNode
}

type Tone = 'up' | 'down' | 'flat'

const UP_PREFIXES = ['+', '▲', '↑']
const DOWN_PREFIXES = ['-', '−', '▼', '↓']
const SIGN: Record<Tone, string> = { up: '+', down: '−', flat: '' }
const ARROW: Record<Tone, string> = { up: '▲', down: '▼', flat: '' }

function numberTone(delta: number): Tone {
  if (delta > 0) return 'up'

  return delta < 0 ? 'down' : 'flat'
}

function deltaTone(delta: number | string): Tone {
  if (typeof delta === 'number') return numberTone(delta)
  const s = delta.trim()

  if (UP_PREFIXES.some((prefix) => s.startsWith(prefix))) return 'up'

  if (DOWN_PREFIXES.some((prefix) => s.startsWith(prefix))) return 'down'

  return 'flat'
}

function deltaText(delta: number | string) {
  if (typeof delta === 'string') return delta

  return `${SIGN[numberTone(delta)]}${Math.abs(delta).toLocaleString()}`
}

function StatDelta({ delta, invert }: { delta: number | string; invert?: boolean }) {
  const tone = deltaTone(delta)
  const good = tone === 'flat' ? undefined : (tone === 'up') !== Boolean(invert)

  return (
    <div className={cx('cv-stat-delta', good === true && 'is-good', good === false && 'is-bad')}>
      {ARROW[tone]} {deltaText(delta).replace(/^[+\-−▲▼↑↓]\s*/, '')}
    </div>
  )
}

export function Stat({ label, value, delta, invertDelta, hint, color, className, style, children }: StatProps) {
  return (
    <div className={cx('cv-stat', className)} style={style}>
      <div className="cv-stat-label">{label}</div>
      <div className="cv-stat-line">
        <div className="cv-stat-value" style={color ? { color: resolveColor(color) } : undefined}>
          {value}
        </div>
        {delta !== undefined && <StatDelta delta={delta} invert={invertDelta} />}
      </div>
      {hint !== undefined && <div className="cv-stat-hint">{hint}</div>}
      {children}
    </div>
  )
}

type BadgeProps = Styled & { color?: string; dot?: boolean; children?: ReactNode }

export function Badge({ color, dot, className, style, children }: BadgeProps) {
  return (
    <span className={cx('cv-badge', className)} style={cssVars({ '--c': resolveColor(color) }, style)}>
      {dot && <span className="cv-badge-dot" />}
      {children}
    </span>
  )
}

type ProgressProps = Styled & {
  value: number
  max?: number
  color?: string
  label?: ReactNode
  showValue?: boolean
}

export function Progress({ value, max, color, label, showValue, className, style }: ProgressProps) {
  const ratio = Math.max(0, Math.min(1, max ? value / max : value))
  const showHeader = label !== undefined || showValue

  return (
    <div className={cx('cv-progress', className)} style={cssVars({ '--c': resolveColor(color) }, style)}>
      {showHeader && (
        <div className="cv-progress-header">
          <span>{label}</span>
          {showValue && <span className="cv-progress-value">{Math.round(ratio * 100)}%</span>}
        </div>
      )}
      <div
        className="cv-progress-track"
        role="progressbar"
        aria-valuenow={Math.round(ratio * 100)}
        aria-valuemin={0}
        aria-valuemax={100}
      >
        <div className="cv-progress-fill" style={{ width: `${ratio * 100}%` }} />
      </div>
    </div>
  )
}

type BarDatum = { label: ReactNode; value: number; color?: string }

const barKey = (d: BarDatum) => (typeof d.label === 'string' || typeof d.label === 'number' ? String(d.label) : 'bar')

type BarChartProps = Styled & {
  data: BarDatum[]
  height?: number
  color?: string
  max?: number
  format?: (value: number) => ReactNode
}

export function BarChart({ data, height = 160, color, max, format, className, style }: BarChartProps) {
  const top = max ?? Math.max(0, ...data.map((d) => d.value))

  return (
    <div className={cx('cv-bars', className)} style={{ height, ...style }}>
      {keyed(data, barKey).map(({ key, item: d }) => {
        const ratio = top > 0 ? Math.max(0, d.value) / top : 0

        return (
          <div className="cv-bar-col" key={key}>
            <div className="cv-bar-track">
              <div className="cv-bar-value">{format ? format(d.value) : d.value.toLocaleString()}</div>
              <div
                className="cv-bar"
                style={{ height: `${ratio * 100}%`, background: resolveColor(d.color ?? color) }}
              />
            </div>
            <div className="cv-bar-label">{d.label}</div>
          </div>
        )
      })}
    </div>
  )
}

type SparklineProps = Styled & {
  data: number[]
  width?: number | string
  height?: number
  color?: string
  fill?: boolean
}

export function Sparkline({ data, width = 120, height = 32, color, fill = true, className, style }: SparklineProps) {
  const stroke = resolveColor(color)

  if (data.length === 0) return <div className={cx('cv-spark', className)} style={{ width: px(width), height, ...style }} />
  const min = Math.min(...data)
  const max = Math.max(...data)
  const pad = 3
  const span = max - min || 1

  const points = data.map((v, i) => {
    const x = data.length === 1 ? 50 : (i / (data.length - 1)) * 100
    const y = pad + (1 - (v - min) / span) * (height - pad * 2)

    return [x, y] as const
  })

  const line = points.map(([x, y]) => `${x},${y}`).join(' ')
  const area = `0,${height} ${line} 100,${height}`
  const [lastX, lastY] = points[points.length - 1]

  return (
    <div className={cx('cv-spark', className)} style={{ width: px(width), height, ...style }}>
      <svg viewBox={`0 0 100 ${height}`} preserveAspectRatio="none" width="100%" height={height} aria-hidden>
        {fill && <polygon points={area} fill={stroke} opacity={0.12} />}
        <polyline
          points={line}
          fill="none"
          stroke={stroke}
          strokeWidth={1.5}
          strokeLinejoin="round"
          strokeLinecap="round"
          vectorEffect="non-scaling-stroke"
        />
      </svg>
      <span className="cv-spark-dot" style={{ left: `${lastX}%`, top: lastY, background: stroke }} />
    </div>
  )
}
