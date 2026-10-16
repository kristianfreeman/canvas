import { beforeEach, describe, expect, test } from 'bun:test'
import type { Op } from './ops'
import type { Message } from './post'
import { invoke, render, reset, setData, warm } from './root'

const posted: Message[] = []
const SINK = '__post'
;(globalThis as Record<string, unknown>)[SINK] = (message: Message) => posted.push(message)

const batches = () => posted.flatMap((message) => (message.type === 'ops' ? [message.ops] : []))
const lastOps = () => batches().at(-1) ?? []

function tsx(body: string) {
  return render({ kind: 'tsx', source: `import { Button, Stack, Text, Card } from 'canvas'\nimport { useState } from 'react'\n${body}` })
}

const COUNTER = `export default function App({ data }) {
  const [n, setN] = useState(0)
  return <Stack><Text muted>{data?.label}</Text><Button onClick={() => setN(n + 1)}>{'n=' + n}</Button></Stack>
}`

function functionOf(ops: Op[], type: string) {
  const create = ops.find((op) => op.op === 'create' && op.type === type)

  return create?.op === 'create' ? (create.props.onClick as { $fn: number }).$fn : undefined
}

beforeEach(() => {
  reset()
  posted.length = 0
})

describe('native runtime', () => {
  test('a render posts one batch that builds the tree bottom-up and attaches it to the root last', () => {
    expect(render({ kind: 'tsx', source: 'import { Card } from "canvas"\nexport default () => <Card title="T">body</Card>' })).toEqual({ ok: true })
    expect(batches()).toHaveLength(1)
    const ops = lastOps()
    const card = ops.find((op) => op.op === 'create' && op.type === 'Card')

    expect(card).toMatchObject({ props: { padding: 16 } })
    expect(ops.at(-1)).toEqual({ op: 'append', parent: 0, child: card?.op === 'create' ? card.id : -1 })
    expect(ops.filter((op) => op.op === 'create').map((op) => op.op === 'create' && op.type)).toEqual(['Card', 'slot'])
    expect(ops.find((op) => op.op === 'create' && op.type === 'slot')).toMatchObject({ props: { name: 'title' } })
  })

  test("a Sparkline fills its container with '100%'; any other percentage needs WebKit", () => {
    expect(render({ kind: 'tsx', source: 'import { Sparkline } from "canvas"\nexport default () => <Sparkline data={[1, 2]} width="100%" />' })).toEqual({ ok: true })
    expect(lastOps().find((op) => op.op === 'create' && op.type === 'Sparkline')).toMatchObject({ props: { width: '100%' } })
    expect(render({ kind: 'tsx', source: 'import { Sparkline } from "canvas"\nexport default () => <Sparkline data={[1, 2]} width="50%" />' })).toMatchObject({ needsWeb: true })
  })

  test('a table without handlers sends no sort, selection or click props', () => {
    const source = 'import { Table } from "canvas"\nexport default () => <Table columns={["a"]} rows={[{ id: "x", a: 1 }]} selected="y" />'

    expect(render({ kind: 'tsx', source })).toEqual({ ok: true })
    const keys = lastOps().flatMap((op) => (op.op === 'create' && op.type.startsWith('Table') ? Object.keys(op.props) : []))

    expect(keys).toContain('key')
    expect(keys.filter((key) => ['sort', 'onClick', 'selected'].includes(key))).toEqual([])
  })

  test('an unchanged re-render posts nothing and a changed prop posts the full set', () => {
    tsx(COUNTER)
    posted.length = 0
    setData(undefined)
    expect(batches()).toEqual([])
    setData({ label: 'hi' })
    expect(lastOps().filter((op) => op.op !== 'text' && op.op !== 'append')).toEqual([])
    expect(lastOps().some((op) => op.op === 'text' && op.text === 'hi')).toBe(true)
  })

})

describe('native runtime state across renders', () => {
  test('function ids are stable across renders and call the latest closure', () => {
    tsx(COUNTER)
    const id = functionOf(lastOps(), 'Button')

    expect(id).toBeNumber()
    invoke(id as number, [])
    invoke(id as number, [])
    expect(lastOps()).toEqual([expect.objectContaining({ op: 'setText', text: 'n=2' })])
    expect(batches().flat().some((op) => op.op === 'props')).toBe(false)
  })

  test('the batch after a fallback first removes the root children Swift still shows', () => {
    tsx(COUNTER)
    const shown = lastOps().flatMap((op) => (op.op === 'append' && op.parent === 0 ? [op.child] : []))
    posted.length = 0

    expect(tsx('export default () => <div />')).toMatchObject({ needsWeb: true })
    expect(batches()).toEqual([])
    tsx(COUNTER)
    expect(lastOps().slice(0, shown.length)).toEqual(shown.map((child) => ({ op: 'remove', parent: 0, child })))
  })

  test('after reset nothing is removed: Swift starts from an empty tree', () => {
    tsx(COUNTER)
    reset()
    posted.length = 0
    tsx(COUNTER)
    expect(lastOps().some((op) => op.op === 'remove')).toBe(false)
  })

  test('warm leaves shown content alone and posts nothing', () => {
    tsx(COUNTER)
    const id = functionOf(lastOps(), 'Button') as number
    posted.length = 0
    warm()
    expect(posted).toEqual([])
    invoke(id, [])
    expect(lastOps()).toEqual([expect.objectContaining({ op: 'setText', text: 'n=1' })])
  })

  test('ids are never reused, even across resets', () => {
    tsx(COUNTER)
    const first = new Set(lastOps().flatMap((op) => (op.op === 'create' || op.op === 'text' ? [op.id] : [])))
    reset()
    tsx(COUNTER)
    const second = lastOps().flatMap((op) => (op.op === 'create' || op.op === 'text' ? [op.id] : []))

    expect(second.some((id) => first.has(id))).toBe(false)
  })
})
