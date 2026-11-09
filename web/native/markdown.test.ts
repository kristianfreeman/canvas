import { describe, expect, test } from 'bun:test'
import { markdownBlocks } from './markdown'

describe('markdownBlocks inline runs', () => {
  test('headings and paragraphs carry inline runs with merged styles', () => {
    expect(markdownBlocks('## Title\n\nplain **bold _both_** ~~gone~~ `code`\nnext')).toEqual([
      { t: 'h', level: 2, inl: [{ t: 'text', s: 'Title' }] },
      {
        t: 'p',
        inl: [
          { t: 'text', s: 'plain ' },
          { t: 'text', s: 'bold ', b: true },
          { t: 'text', s: 'both', b: true, i: true },
          { t: 'text', s: ' ' },
          { t: 'text', s: 'gone', del: true },
          { t: 'text', s: ' ' },
          { t: 'code', s: 'code' },
          { t: 'text', s: ' next' },
        ],
      },
    ])
  })

  test('links nest their runs and hard breaks become br', () => {
    const [p] = markdownBlocks('see [the **docs**](https://example.com)  \nthen')

    expect(p).toEqual({
      t: 'p',
      inl: [
        { t: 'text', s: 'see ' },
        { t: 'link', href: 'https://example.com', inl: [{ t: 'text', s: 'the ' }, { t: 'text', s: 'docs', b: true }] },
        { t: 'br' },
        { t: 'text', s: 'then' },
      ],
    })
  })

  test('unsafe link schemes stay text and raw HTML is text', () => {
    const [p] = markdownBlocks('[x](javascript:alert(1)) <b>hi</b>')

    expect(p.t === 'p' && p.inl.every((run) => run.t === 'text')).toBe(true)
    expect(p.t === 'p' && p.inl.map((run) => (run.t === 'text' ? run.s : '')).join('')).toContain('<b>hi</b>')
  })

})

type Block = ReturnType<typeof markdownBlocks>[number]
type Task = { line?: number; checked?: boolean }

/** Task items with the source line each names, as `TaskList.setChecked` in Swift counts lines. */
function tasks(blocks: Block[]): Task[] {
  return blocks.flatMap((block): Task[] => {
    if (block.t === 'quote') return tasks(block.blocks)
    if (block.t !== 'list') return []

    return block.items.flatMap((item) => [...(item.task ? [{ line: item.line, checked: item.checked }] : []), ...tasks(item.blocks)])
  })
}

describe('markdownBlocks task lines', () => {
  test('each task names the line its marker is on, through nesting, quotes and CRLF', () => {
    const sources = [
      '# Todo\n\n- [ ] one\n- [x] two\n  - [ ] nested\n\n> - [X] quoted\n',
      'intro\r\n\r\n1. [ ] first\r\n2. [x] second\r\n',
      '- [ ] a\n\n  continued paragraph\n- [ ] b\n',
    ]

    for (const source of sources) {
      const lines = source.split(/\r\n?|\n/)
      const found = tasks(markdownBlocks(source))

      expect(found.length).toBeGreaterThan(0)
      for (const { line, checked } of found) {
        expect(line).toBeNumber()
        const text = lines[line ?? -1]

        expect(text).toMatch(/^[\s>]*([-*+]|\d+[.)])\s+\[[ xX]\]/)
        expect(/\[[xX]\]/.test(text)).toBe(checked ?? false)
      }
    }
  })

  test('plain items carry no line', () => {
    const [list] = markdownBlocks('- plain\n')

    expect(list.t === 'list' && list.items[0].line).toBeUndefined()
  })
})

describe('markdownBlocks containers', () => {
  test('lists keep order, start and nesting; task markers become flags', () => {
    const blocks = markdownBlocks('3. a\n4. b\n   - [x] done\n   - [ ] todo\n   - plain')

    expect(blocks).toHaveLength(1)
    const list = blocks[0]

    if (list.t !== 'list') throw new Error(`expected a list, got ${list.t}`)
    expect(list.ordered).toBe(true)
    expect(list.start).toBe(3)
    const nested = list.items[1].blocks[1]

    if (nested.t !== 'list') throw new Error(`expected a nested list, got ${nested.t}`)
    expect(nested.items.map((item) => [item.task, item.checked])).toEqual([[true, true], [true, false], [undefined, undefined]])
    expect(nested.items[0].blocks).toEqual([{ t: 'p', inl: [{ t: 'text', s: 'done' }] }])
  })

  test('tables keep column alignment, head and rows', () => {
    expect(markdownBlocks('| a | b | c |\n|:--|:-:|--:|\n| 1 | **2** | |')).toEqual([
      {
        t: 'table',
        align: ['left', 'center', 'right'],
        head: [[{ t: 'text', s: 'a' }], [{ t: 'text', s: 'b' }], [{ t: 'text', s: 'c' }]],
        rows: [[[{ t: 'text', s: '1' }], [{ t: 'text', s: '2', b: true }], []]],
      },
    ])
  })

  test('footnote references match their items', () => {
    const blocks = markdownBlocks('One[^a] and two[^b].\n\n[^a]: First.\n[^b]: Second.')
    const refs = blocks[0].t === 'p' ? blocks[0].inl.filter((run) => run.t === 'fnref') : []
    const notes = blocks.at(-1)

    expect(refs).toEqual([{ t: 'fnref', id: 'fn1', n: 1 }, { t: 'fnref', id: 'fn2', n: 2 }])
    expect(notes).toEqual({
      t: 'footnotes',
      items: [
        { id: 'fn1', blocks: [{ t: 'p', inl: [{ t: 'text', s: 'First.' }] }] },
        { id: 'fn2', blocks: [{ t: 'p', inl: [{ t: 'text', s: 'Second.' }] }] },
      ],
    })
  })

  test('quotes, rules and code blocks', () => {
    const blocks = markdownBlocks('> quoted\n\n---\n\n    indented\n\n```nope\nx\n```')

    expect(blocks.map((block) => block.t)).toEqual(['quote', 'hr', 'code', 'code'])
    expect(blocks[2]).toEqual({ t: 'code', lang: '', lines: [[{ s: 'indented' }]] })
    expect(blocks[3]).toEqual({ t: 'code', lang: 'nope', lines: [[{ s: 'x' }]] })
  })
})
