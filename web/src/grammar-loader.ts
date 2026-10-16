import type { LanguageRegistration } from 'shiki/core'
import type { GrammarName } from './grammars'
import { onGrammarReady, registerGrammar, setGrammarFetcher } from './highlight'
import { idle } from './idle'
import { DEFERRED_SELECTOR, upgradeTask } from './upgrade'

declare global {
  interface Window {
    canvasGrammars?: Partial<Record<string, LanguageRegistration[]>>
  }
}

const fetched = new Set<GrammarName>()

function onScriptLoad(name: GrammarName) {
  const grammars = window.canvasGrammars?.[name]

  if (!grammars) return console.warn(`[canvas] grammar script for ${name} registered nothing`)

  try {
    registerGrammar(name, grammars)
  } catch (error) {
    console.warn(`[canvas] grammar ${name} failed to load`, error)
  }
}

/** Classic scripts, since file:// blocks module scripts and fetch (connect-src 'none'). */
function fetchGrammar(name: GrammarName) {
  if (fetched.has(name)) return
  fetched.add(name)
  const script = document.createElement('script')
  script.src = `langs/${name}.js`
  script.async = true
  script.addEventListener('load', () => onScriptLoad(name))
  script.addEventListener('error', () => console.warn(`[canvas] could not load langs/${name}.js`))
  document.head.append(script)
}

/** Highlights plain `data-deferred` blocks in idle slices, ahead of other background work; the ResizeObserver reports any height change. */
export function scheduleUpgrades() {
  if (document.querySelector(DEFERRED_SELECTOR)) idle.add(upgradeTask(document), { front: true })
}

/** Blocks that rendered plain while their grammar was loading join the deferred ones. */
function deferPending(name: GrammarName) {
  for (const pre of document.querySelectorAll<HTMLElement>(`pre[data-pending="${name}"]`)) {
    pre.removeAttribute('data-pending')
    pre.dataset.deferred = name
  }

  scheduleUpgrades()
}

export function installGrammarLoader() {
  setGrammarFetcher(fetchGrammar)
  onGrammarReady(deferPending)
}
