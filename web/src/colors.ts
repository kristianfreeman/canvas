/** Apple system colors; styles.css defines each as `--<name>` for the current theme. */
export const HUES = ['red', 'orange', 'yellow', 'green', 'teal', 'blue', 'purple', 'pink', 'gray'] as const

const SEMANTIC: Record<string, string> = {
  accent: 'var(--accent)',
  success: 'var(--success)',
  warning: 'var(--warning)',
  danger: 'var(--danger)',
  info: 'var(--info)',
  muted: 'var(--fg-muted)',
}

const HUE_SET = new Set<string>(HUES)

/** Maps a semantic or hue name to its CSS variable; anything else is passed through as a CSS color. */
export function resolveColor(color: string | undefined, fallback = 'var(--accent)') {
  if (!color) return fallback

  if (Object.hasOwn(SEMANTIC, color)) return SEMANTIC[color]

  if (HUE_SET.has(color)) return `var(--${color})`

  return color
}

function channel(value: number) {
  const c = value / 255

  return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4
}

export function luminance([r, g, b]: readonly number[]) {
  return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
}

/** White text when it reaches 3:1 against the color (the WCAG bar for UI and bold text), else black. */
export function contrastText(rgb: readonly number[]): '#ffffff' | '#000000' {
  return 1.05 / (luminance(rgb) + 0.05) >= 3 ? '#ffffff' : '#000000'
}
