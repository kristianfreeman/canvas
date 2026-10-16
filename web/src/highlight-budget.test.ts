import { beforeAll, expect, test } from 'bun:test'
import toml from 'shiki/langs/toml.mjs'
import yaml from 'shiki/langs/yaml.mjs'
import { highlight, registerGrammar, requestGrammar, setGrammarFetcher, warmGrammar, withHighlightBudget } from './highlight'
import { renderMarkdown } from './markdown'
import { upgradeTask, type BlockLike } from './upgrade'

const HIGHLIGHTED = /<pre class="shiki shiki-themes/g
const DEFERRED = /<pre class="shiki plain" data-deferred="yaml"><code>([^<]*)<\/code><\/pre>/g

const count = (html: string, pattern: RegExp) => html.match(pattern)?.length ?? 0

/** Ten distinct fences of equal length, so every block costs the same. */
const fences = (prefix: string) => Array.from({ length: 10 }, (_, i) => `\`\`\`yaml\n${prefix}: ${i}\n\`\`\``).join('\n\n')

/** A clock that moves `step` ms each time it's read, so every highlight measures exactly `step` ms. */
function ticking(step: number) {
  let t = 0

  return () => (t += step)
}

function drain(task: Iterator<unknown>) {
  let steps = 0

  while (!task.next().done) steps++

  return steps
}

beforeAll(() => {
  setGrammarFetcher(() => {})
  registerGrammar('yaml', yaml)
  registerGrammar('toml', toml)
  requestGrammar('yaml')
  requestGrammar('toml')
  drain(warmGrammar('yaml'))
  highlight('seed: x', 'yaml')
})

test('a 4 ms budget where each block costs 1 ms highlights four fences and defers the other six', () => {
  const html = withHighlightBudget(4, () => renderMarkdown(fences('one')), ticking(1))

  expect(count(html, HIGHLIGHTED)).toBe(4)
  expect(count(html, DEFERRED)).toBe(6)
})

test('a block whose estimated cost no longer fits is deferred before the budget is spent', () => {
  const html = withHighlightBudget(4, () => renderMarkdown(fences('two')), ticking(3))

  expect(count(html, HIGHLIGHTED)).toBe(1)
  expect(count(html, DEFERRED)).toBe(9)
})

test('without a budget every fence is highlighted', () => {
  const html = renderMarkdown(fences('three'))

  expect(count(html, HIGHLIGHTED)).toBe(10)
  expect(html).not.toContain('data-deferred')
})

test('already highlighted code renders highlighted even with no budget at all', () => {
  renderMarkdown(fences('four'))
  const html = withHighlightBudget(0, () => renderMarkdown(fences('four')), ticking(100))

  expect(count(html, HIGHLIGHTED)).toBe(10)
})

test('a grammar whose regexes are not compiled yet is deferred inside a budget, however large', () => {
  const inside = withHighlightBudget(1000, () => highlight('a = 1', 'toml'))

  expect(inside).toBe('<pre class="shiki plain" data-deferred="toml"><code>a = 1</code></pre>')
  expect(highlight('a = 1', 'toml')).toContain('shiki-themes')
})

const unescape = (html: string) =>
  html.replace(/&quot;/g, '"').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&')

/** Stands in for a deferred `<pre>`; `outerHTML` starts empty and holds whatever the upgrade wrote. */
function fakeBlocks(html: string): BlockLike[] {
  return [...html.matchAll(DEFERRED)].map(([, code]) => ({
    isConnected: true,
    textContent: unescape(code),
    getAttribute: (name: string) => (name === 'data-deferred' ? 'yaml' : null),
    outerHTML: '',
  }))
}

test('the upgrade task highlights each deferred block in its own step, after which a re-render needs no budget', () => {
  const source = fences('five')
  const blocks = fakeBlocks(withHighlightBudget(4, () => renderMarkdown(source), ticking(3)))
  const stale = { ...blocks.pop()!, isConnected: false }
  const steps = drain(upgradeTask({ querySelectorAll: () => [...blocks, stale] }))

  expect(blocks).toHaveLength(8)
  expect(steps).toBeGreaterThanOrEqual(blocks.length)
  for (const block of blocks) expect(block.outerHTML).toMatch(/^<pre class="shiki shiki-themes[^]*--shiki-dark:/)
  expect(stale.outerHTML).toBe('')

  const again = withHighlightBudget(0, () => renderMarkdown(source), ticking(100))
  expect(count(again, HIGHLIGHTED)).toBe(9)
  expect(count(again, DEFERRED)).toBe(1)
})
