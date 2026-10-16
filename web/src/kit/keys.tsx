import { Kbd } from './text'
import { cx, keyed, type Styled } from './util'

type Chip = { kind: 'key' | 'hyper' | 'note'; text: string } | { kind: 'then' | 'plus' }

const MULTI_WORD = ['Caps Lock', 'Page Up', 'Page Down', 'Num Lock']
const NOTES = new Set(['tap', 'hold', 'twice', 'double', 'then', 'or', 'again'])
const ARROWS = new Set(['←', '↑', '↓', '→'])

/** Whitespace-separated words, with two-word keys like `Caps Lock` kept together. */
function tokenize(keys: string | string[]): string[] {
  if (Array.isArray(keys)) return keys
  const words = keys.trim().split(/\s+/).filter(Boolean)
  const tokens: string[] = []

  for (let i = 0; i < words.length; i++) {
    const pair = `${words[i]} ${words[i + 1] ?? ''}`.toLowerCase()
    const multi = MULTI_WORD.find((m) => m.toLowerCase() === pair)

    if (multi) {
      tokens.push(multi)
      i++
    } else tokens.push(words[i])
  }

  return tokens
}

/** `→` between two non-arrow keys is a sequence separator ("Hyper W → 1–7"); next to other arrows it's a key. */
function isSeparator(token: string, prev: string | undefined, next: string | undefined) {
  if (token !== '→' || !prev || !next) return false

  return !ARROWS.has(prev) && !ARROWS.has(next)
}

function parseKeys(keys: string | string[]): Chip[] {
  const tokens = tokenize(keys)

  return tokens.map((token, i): Chip => {
    if (isSeparator(token, tokens[i - 1], tokens[i + 1])) return { kind: 'then' }

    if (token === '+') return { kind: 'plus' }

    if (NOTES.has(token.toLowerCase())) return { kind: 'note', text: token }

    if (token.toLowerCase() === 'hyper') return { kind: 'hyper', text: 'Hyper' }

    return { kind: 'key', text: token }
  })
}

const chipText = (chip: Chip) => ('text' in chip ? `${chip.kind}:${chip.text}` : chip.kind)

function KeyChip({ chip }: { chip: Chip }) {
  switch (chip.kind) {
    case 'then':
      return <span className="cv-keys-sep">→</span>
    case 'plus':
      return <span className="cv-keys-sep">+</span>
    case 'note':
      return <span className="cv-keys-note">{chip.text}</span>
    case 'hyper':
      return (
        <Kbd tone="accent" className="cv-keys-hyper">
          ✦
        </Kbd>
      )
    default:
      return <Kbd className={ARROWS.has(chip.text) ? 'cv-keys-arrow' : undefined}>{chip.text}</Kbd>
  }
}

export function KeyChips({ keys, className, style }: Styled & { keys: string | string[] }) {
  return (
    <div className={cx('cv-keys', className)} style={style}>
      {keyed(parseKeys(keys), chipText).map(({ key, item }) => (
        <KeyChip key={key} chip={item} />
      ))}
    </div>
  )
}
