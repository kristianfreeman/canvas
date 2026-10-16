import { contrastText } from './colors'

export type ThemeMode = 'auto' | 'dark' | 'light'

const query = window.matchMedia('(prefers-color-scheme: dark)')
let mode: ThemeMode = 'auto'
let accent = ''
let probe: CanvasRenderingContext2D | null | undefined

function resolvedMode() {
  if (mode !== 'auto') return mode

  return query.matches ? 'dark' : 'light'
}

function apply() {
  document.documentElement.dataset.theme = resolvedMode()
}

query.addEventListener('change', apply)

export function setTheme(theme: unknown) {
  mode = theme === 'dark' || theme === 'light' ? theme : 'auto'
  apply()
}

/** Paints the color into a pixel and reads it back, which resolves any CSS color syntax WebKit understands. */
function rgbOf(color: string) {
  probe ??= document.createElement('canvas').getContext('2d', { willReadFrequently: true })

  if (!probe) return undefined
  probe.clearRect(0, 0, 1, 1)
  probe.fillStyle = color
  probe.fillRect(0, 0, 1, 1)

  return [...probe.getImageData(0, 0, 1, 1).data.subarray(0, 3)]
}

/** Overrides `--accent` (and its derived foreground) with any CSS color; anything else restores the default. */
export function setAccent(value: unknown) {
  const color = typeof value === 'string' && CSS.supports('color', value.trim()) ? value.trim() : ''

  if (color === accent) return
  accent = color
  const style = document.documentElement.style

  if (!color) {
    style.removeProperty('--accent')
    style.removeProperty('--accent-fg')

    return
  }

  style.setProperty('--accent', color)
  const rgb = rgbOf(color)

  if (rgb) style.setProperty('--accent-fg', contrastText(rgb))
  else style.removeProperty('--accent-fg')
}
