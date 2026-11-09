import { beforeEach, describe, expect, test } from 'bun:test'
import type { PushMessage } from '../src/channels'
import { exampleFiles, exampleSource, keysData, sysSample } from '../src/examples.fixtures'
import type { Message } from './post'
import { invoke, push, render, reset } from './root'
import { findAll, fnOf, replay, textOf, type TreeNode } from './tree.testing'

const posted: Message[] = []
const SINK = '__post'
;(globalThis as Record<string, unknown>)[SINK] = (message: Message) => posted.push(message)

const tree = () => replay(posted.flatMap((message) => (message.type === 'ops' ? [message.ops] : [])))
const errors = () => posted.filter((message) => message.type === 'error')
const published = () => posted.flatMap((message) => (message.type === 'publish' ? [message] : []))

/** Renders an example as the server would, then pushes channel data, and expects every step to stay native. */
function show(file: string, data?: unknown, batch?: PushMessage[]) {
  expect(render({ kind: 'tsx', source: exampleSource(file), data })).toEqual({ ok: true })

  if (batch) expect(push(batch)).toEqual({ ok: true })
  expect(errors()).toEqual([])

  return tree()
}

function click(target: TreeNode, prop = 'onClick', args: unknown[] = []) {
  expect(invoke(fnOf(target, prop), args)).toEqual({ ok: true })

  return tree()
}

const only = (root: TreeNode, type: string) => {
  const found = findAll(root, type)
  expect(found).toHaveLength(1)

  return found[0]
}

const head = () => findAll(tree(), 'slot').find((s) => s.props.name === 'head')?.children ?? []

/** A grid's children with their position and the cell after each. */
const cellsOf = (grid: TreeNode) => grid.children.map((child, index) => ({ child, index, next: grid.children[index + 1] }))

const rowKeys = (root: TreeNode) => findAll(only(root, 'Table'), 'TableRow').map((row) => row.props.key)

const CASES: { file: string; label: string; data?: unknown; batch?: PushMessage[] }[] = [
  { file: 'approve.tsx', label: 'no data' },
  { file: 'approve.tsx', label: 'a plan', data: { title: 'Ship it', changes: ['One', 'Two'] } },
  { file: 'dashboard.tsx', label: 'no data' },
  { file: 'deploy.tsx', label: 'no data' },
  { file: 'deploy.tsx', label: 'a release', data: { title: 'Ship it', openMs: [40, 20], checks: [{ name: 'CI', ok: false }] } },
  { file: 'keys.tsx', label: 'no data' },
  { file: 'keys.tsx', label: 'keys.json', data: keysData() },
  { file: 'live.tsx', label: 'no data' },
  { file: 'live.tsx', label: 'a channel', data: { channel: 'demo.load', unit: '%' }, batch: [{ channel: 'demo.load', value: 42, history: [10, 42] }] },
  { file: 'top.tsx', label: 'no data' },
  { file: 'top.tsx', label: 'sampler data', batch: sysSample({ percent: 15, charging: false, source: 'battery' }) },
  { file: 'todo.tsx', label: 'no data' },
  { file: 'todo.tsx', label: 'stored items', batch: [{ channel: 'todo.items', value: [{ text: 'a', done: false }] }] },
]

beforeEach(() => {
  reset()
  posted.length = 0
})

describe('examples render natively', () => {
  test('every example has a case without data', () => {
    expect(CASES.filter((c) => c.data === undefined && !c.batch).map((c) => c.file).toSorted()).toEqual(exampleFiles.toSorted())
  })

  test.each(CASES.map((c) => [c.file, c.label, c] as const))('%s with %s', (_file, _label, { file, data, batch }) => {
    expect(show(file, data, batch).children.length).toBeGreaterThan(0)
  })

  test('a DOM tag in an example is caught as needing WebKit', () => {
    const source = exampleSource('keys.tsx').replace('return <Empty />', 'return <div />')

    expect(source).not.toBe(exampleSource('keys.tsx'))
    expect(render({ kind: 'tsx', source })).toMatchObject({ needsWeb: true })
  })
})

describe('keys.tsx natively', () => {
  const data = keysData()
  const rows = data.groups.flatMap((group) => group.rows)

  test('one KeyChips per row, each followed by its description, in two max-content columns', () => {
    const root = show('keys.tsx', data)
    const columns = findAll(root, 'Grid').filter((grid) => grid.props.columns === 'max-content 1fr')

    expect(findAll(root, 'Grid').find((grid) => grid.props.columns === 2)?.children).toEqual(columns)
    expect(findAll(root, 'KeyChips').map((chips) => chips.props.keys).toSorted()).toEqual(rows.map((row) => row.keys).toSorted())

    for (const { child, index, next } of columns.flatMap(cellsOf).filter((cell) => cell.child.type === 'KeyChips')) {
      expect([index % 2, next.type]).toEqual([0, 'Text'])
      expect(rows.find((row) => row.desc === textOf(next))?.keys).toEqual(child.props.keys as string)
    }
  })

  test('group names are level-4 headings, and the footer has the Hyper legend and Esc', () => {
    const root = show('keys.tsx', data)
    const kbds = findAll(root, 'Kbd')

    expect(findAll(root, 'Heading').map((heading) => [heading.props.level, textOf(heading)]).toSorted())
      .toEqual(data.groups.map((group) => [4, group.name]).toSorted())
    expect(kbds.map((kbd) => [textOf(kbd), kbd.props.tone])).toEqual([['✦', 'accent'], ['Esc', undefined]])
  })

  test('without groups it explains the data shape', () => {
    const root = show('keys.tsx', { groups: [{ name: 'Empty', rows: [] }] })

    expect(textOf(root)).toContain('No shortcuts to show')
    expect(findAll(root, 'KeyChips')).toEqual([])
  })
})

describe('top.tsx natively', () => {
  const sample = sysSample({ percent: 15, charging: false, source: 'battery' })

  test('placeholders before the sampler: empty meters and skeleton rows', () => {
    const root = show('top.tsx')

    expect(textOf(root).match(/Waiting for the sampler/g)).toHaveLength(2)
    expect(rowKeys(root)).toHaveLength(6)
    expect(findAll(root, 'Progress').every((bar) => bar.props.value === 0 || bar.props.value === 1)).toBe(true)
  })

  test('sampler data fills the cards and sorts processes by CPU, skipping malformed ones', () => {
    const root = show('top.tsx', undefined, sample)
    const text = textOf(root)

    for (const part of ['42%', '4 cores', 'Thermal fair', '15% · battery', '9.0 GB of 16.0 GB', '200 GB of 500 GB used', '2.0 KB/s', '135.0%']) {
      expect(text).toContain(part)
    }

    expect(rowKeys(root)).toEqual(['812', '1'])
    expect(findAll(root, 'Sparkline').map((line) => line.props.width)).toEqual(['100%', '100%', '100%', '100%'])
    expect(findAll(root, 'Grid').map((grid) => grid.props.columns)).toContain('375fr 125fr 63fr 438fr')
    expect(findAll(root, 'TableCell').filter((cell) => cell.props.sort).map((cell) => [textOf(cell), cell.props.sort]))
      .toEqual([['CPU', 'descending']])
  })

  test('a header click sorts by that column, and a second flips the direction', () => {
    show('top.tsx', undefined, sample)

    let root = click(head()[0])
    expect([rowKeys(root), head()[0].props.sort]).toEqual([['1', '812'], 'ascending'])
    root = click(head()[0])
    expect([rowKeys(root), head()[0].props.sort]).toEqual([['812', '1'], 'descending'])
  })

  test('a row click selects it and publishes top.select', () => {
    const root = click(findAll(show('top.tsx', undefined, sample), 'TableRow')[1])

    expect(published()).toEqual([{ type: 'publish', channel: 'top.select', value: { pid: 1, name: 'launchd', cpu: 0.01, mem: 2 ** 24 } }])
    expect(findAll(root, 'TableRow').map((row) => row.props.selected)).toEqual([undefined, true])
  })
})

describe('approve.tsx and live.tsx natively', () => {
  test('approve submits the decision and comment as the result', () => {
    click(only(show('approve.tsx'), 'Form'), 'onSubmit', [{ decision: 'approve', comment: 'ok' }])

    expect(posted.filter((message) => message.type === 'result')).toEqual([{ type: 'result', value: { decision: 'approve', comment: 'ok' } }])
  })

  test('deploy answers ship or hold from its buttons and shows the open-time drop', () => {
    const root = show('deploy.tsx', { openMs: [300, 3] })

    expect(findAll(root, 'Stat')[0].props).toMatchObject({ delta: '297 ms', tone: 'down', good: true })
    expect(textOf(root)).toContain('3 ms')
    const [hold, ship] = findAll(root, 'Button')
    click(ship)
    click(hold)
    expect(posted.filter((message) => message.type === 'result')).toEqual([
      { type: 'result', value: 'ship' },
      { type: 'result', value: 'hold' },
    ])
  })

  test('live shows the channel and publishes a mark', () => {
    const root = show('live.tsx', { channel: 'demo.load', unit: '%' }, [{ channel: 'demo.load', value: 42, history: [10, 42] }])

    expect(textOf(root)).toContain('42%')
    expect(only(root, 'Sparkline').props.data).toEqual([10, 42])
    click(only(root, 'Button'))
    expect(published()).toEqual([{ type: 'publish', channel: 'demo.load.mark', value: { at: expect.any(Number), value: 42 } }])
  })
})

describe('todo.tsx natively', () => {
  const items = [
    { text: 'Review', done: false },
    { text: 'Reply', done: true },
  ]

  test('checking an item and adding one publish the whole list, persisted, and show at once', () => {
    const root = show('todo.tsx', undefined, [{ channel: 'todo.items', value: items }])
    const boxes = findAll(root, 'Checkbox')

    expect(boxes.map((box) => box.props.checked)).toEqual([false, true])
    const checked = click(boxes[0], 'onChange', [{ checked: true }])

    expect(findAll(checked, 'Checkbox').map((box) => box.props.checked)).toEqual([true, true])
    const added = click(only(checked, 'Form'), 'onSubmit', [{ text: '  Ship  ' }])

    expect(findAll(added, 'Checkbox')).toHaveLength(3)
    expect(published()).toEqual([
      { type: 'publish', channel: 'todo.items', value: [{ ...items[0], done: true }, items[1]], persist: true },
      {
        type: 'publish',
        channel: 'todo.items',
        value: [{ ...items[0], done: true }, items[1], { text: 'Ship', done: false }],
        persist: true,
      },
    ])
  })

  test('a push from elsewhere replaces what was set here', () => {
    const root = show('todo.tsx', undefined, [{ channel: 'todo.items', value: items }])
    click(findAll(root, 'Checkbox')[0], 'onChange', [{ checked: true }])
    expect(push([{ channel: 'todo.items', value: [{ text: 'From the CLI', done: false }] }])).toEqual({ ok: true })

    expect(findAll(tree(), 'Checkbox')).toHaveLength(1)
  })
})
