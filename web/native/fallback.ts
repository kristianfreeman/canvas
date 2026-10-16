/** The tree uses something only the WebKit renderer can draw (docs/native.md, Fallback to WebKit). */
export class NeedsWeb extends Error {}

let flagged: NeedsWeb | null = null

/**
 * Throws, and remembers the first reason until `takeFallback`. Remembering matters because an error boundary in the
 * author's code can swallow the throw, and the commit that follows must still be dropped.
 */
export function needsWeb(reason: string): never {
  const error = new NeedsWeb(reason)
  flagged ??= error
  throw error
}

export function fallbackPending() {
  return flagged !== null
}

export function takeFallback() {
  const error = flagged
  flagged = null

  return error
}

const SIZE_KEYS = new Set([
  'margin', 'marginTop', 'marginRight', 'marginBottom', 'marginLeft',
  'padding', 'paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft',
  'width', 'minWidth', 'maxWidth', 'height',
])

const TEXT_ALIGN = new Set(['left', 'center', 'right'])
const PX = /^\s*(-?\d+(?:\.\d+)?)px\s*$/

const show = (value: unknown) => JSON.stringify(value) ?? String(value)

/** Points from a number or a `px` string; anything else needs the web. */
export function size(value: unknown, what: string): number | undefined {
  if (value === undefined || value === null) return undefined

  if (typeof value === 'number' && Number.isFinite(value)) return value
  const match = typeof value === 'string' ? PX.exec(value) : null

  if (match) return Number(match[1])

  return needsWeb(`${what} ${show(value)} is not a number or a px length`)
}

function finite(value: unknown, what: string) {
  if (typeof value === 'number' && Number.isFinite(value)) return value

  return needsWeb(`${what} ${show(value)} is not a number`)
}

function styleValue(key: string, value: unknown): number | string {
  if (SIZE_KEYS.has(key)) return size(value, `style.${key}`) as number

  if (key === 'flex' || key === 'opacity') return finite(value, `style.${key}`)

  if (key === 'textAlign' && typeof value === 'string' && TEXT_ALIGN.has(value)) return value

  return needsWeb(`style.${key}: ${show(value)} has no native equivalent`)
}

/** The allowed style keys with sizes as points, or undefined when nothing is left. */
export function nativeStyle(style: unknown): Record<string, number | string> | undefined {
  if (style === undefined || style === null) return undefined

  if (typeof style !== 'object') return needsWeb(`style ${show(style)} is not an object`)
  const out: Record<string, number | string> = {}

  for (const [key, value] of Object.entries(style)) {
    if (value !== undefined && value !== null) out[key] = styleValue(key, value)
  }

  return Object.keys(out).length > 0 ? out : undefined
}

const TRACK = /^(\d+(\.\d+)?(fr|px)?|auto|min-content|max-content)$/

/** `Grid.columns` as a count or a list of simple track sizes. */
export function gridColumns(columns: unknown): number | string {
  if (typeof columns === 'number' && Number.isInteger(columns) && columns > 0) return columns
  const tracks = typeof columns === 'string' ? columns.trim().split(/\s+/) : []

  if (tracks.length > 0 && tracks.every((track) => TRACK.test(track))) return tracks.join(' ')

  return needsWeb(`Grid columns ${show(columns)} has no native equivalent`)
}

export function checkClassName(props: { className?: unknown }) {
  if (props.className) needsWeb(`className ${show(props.className)} needs the web renderer`)
}
