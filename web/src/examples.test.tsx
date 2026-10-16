import { afterEach, expect, test } from 'bun:test'
import type { ComponentType } from 'react'
import { renderToString } from 'react-dom/server'
import { exampleFiles, exampleSource, keysData, sysSample } from './examples.fixtures'
import { CanvasProvider, channelStore } from './kit'
import { evaluateTsx } from './tsx'

const load = (file: string) => evaluateTsx(exampleSource(file)) as ComponentType<{ data: unknown }>

const html = (App: ComponentType<{ data: unknown }>, data?: unknown) =>
  renderToString(
    <CanvasProvider data={data} wait={false}>
      <App data={data} />
    </CanvasProvider>,
  )

const count = (out: string, pattern: RegExp) => out.match(pattern)?.length ?? 0

afterEach(() => channelStore.clear())

test('there are examples to check', () => {
  expect(exampleFiles).toContain('top.tsx')
})

test.each(exampleFiles)('%s compiles and default-exports a component', (file) => {
  expect(typeof load(file)).toBe('function')
})

test('top.tsx renders placeholders before any channel data arrives', () => {
  const out = html(load('top.tsx'))

  expect(count(out, /Waiting for the sampler/g)).toBe(2)
  expect(count(out, /<tr/g)).toBe(7)
  expect(out).toContain('aria-sort="descending"')
})

test('top.tsx renders sampler data, sorted by CPU, and skips malformed processes', () => {
  channelStore.push(sysSample())
  const out = html(load('top.tsx'))

  expect(out).toContain('42%')
  expect(out).toContain('4 cores')
  expect(out).toContain('Thermal fair')
  expect(out).toContain('9.0 GB of 16.0 GB')
  expect(out).toContain('200 GB of 500 GB used')
  expect(out).toContain('2.0 KB/s')
  expect(out.indexOf('WindowServer')).toBeLessThan(out.indexOf('launchd'))
  expect(out).toContain('135.0%')
  expect(out).not.toContain('>bad<')
  expect(out).not.toContain('Waiting for the sampler')
  expect(count(out, /class="is-clickable"/g)).toBe(2)
})

test('keys.tsx draws the same chips on the web kit as the native parser', () => {
  const data = keysData()
  const rows = data.groups.flatMap((group) => group.rows)
  const out = html(load('keys.tsx'), data)

  expect(count(out, /class="cv-keys"/g)).toBe(rows.length)
  expect(count(out, /cv-kbd-accent/g)).toBe(rows.filter((row) => /hyper/i.test(String(row.keys))).length + 1)
  expect(count(out, /class="cv-keys-sep">→</g)).toBe(rows.filter((row) => String(row.keys).includes(' W → ')).length)
  expect(count(out, /cv-keys-arrow/g)).toBe(4)
  expect(out).toContain('>Caps Lock</kbd><span class="cv-keys-note">tap</span>')
  expect(out).not.toMatch(/<style/)
})
