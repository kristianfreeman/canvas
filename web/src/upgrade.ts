import { canonicalLanguage } from './grammars'
import { highlight, warmGrammar } from './highlight'

export type BlockLike = {
  readonly isConnected: boolean
  readonly textContent: string | null
  outerHTML: string
  getAttribute(name: string): string | null
}

/** `querySelectorAll` must return a snapshot (a static NodeList), since blocks are replaced while iterating. */
export type RootLike = { querySelectorAll(selector: string): Iterable<BlockLike> }

export const DEFERRED_SELECTOR = 'pre[data-deferred]'

/**
 * Swaps each plain `data-deferred` block for its highlighted HTML, one block per step after compiling the grammar's
 * regexes in steps of their own. Blocks are found when the task starts, and ones replaced since are skipped.
 */
export function* upgradeTask(root: RootLike): Generator<void, void, unknown> {
  for (const pre of root.querySelectorAll(DEFERRED_SELECTOR)) {
    const lang = canonicalLanguage(pre.getAttribute('data-deferred') ?? undefined)

    if (!lang) continue
    yield* warmGrammar(lang)

    if (!pre.isConnected) continue
    pre.outerHTML = highlight(pre.textContent ?? '', lang)
    yield
  }
}
