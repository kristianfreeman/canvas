import { expect, test } from 'bun:test'
import json from 'shiki/langs/json.mjs'
import { registerGrammar, setGrammarFetcher } from './highlight'
import { renderMarkdown } from './markdown'

test('raw HTML is escaped, never emitted as tags', () => {
  const html = renderMarkdown('<script>alert(1)</script>\n\nhi <img src=x onerror="alert(1)"> <b>bold</b>')

  expect(html).not.toMatch(/<script/i)
  expect(html).not.toMatch(/<img/i)
  expect(html).not.toContain('<b>')
  expect(html).toContain('&lt;script&gt;alert(1)&lt;/script&gt;')
})

test('a script tag inside a code fence stays text', () => {
  const html = renderMarkdown('```html\n</code></pre><script>x()</script>\n```')

  expect(html).not.toMatch(/<script/i)
  expect(html).toContain('&lt;/code&gt;&lt;/pre&gt;&lt;script&gt;')
})

test('javascript: URLs are neither linked nor linkified, while https URLs are', () => {
  const html = renderMarkdown('[click](javascript:alert(1)) and javascript:alert(2) and https://example.com/a')

  expect(html).not.toMatch(/href="javascript:/i)
  expect(html).toContain('<a href="https://example.com/a">https://example.com/a</a>')
})

test('task lists produce disabled checkboxes inside labels', () => {
  const html = renderMarkdown('- [x] done\n- [ ] todo\n')

  expect(html).toContain('<ul class="contains-task-list">')
  expect(html.match(/<li class="task-list-item" data-line="\d+">/g)).toHaveLength(2)
  expect(html.match(/<input class="task-list-item-checkbox" checked=""/g)).toHaveLength(1)
  expect(html.match(/<input [^>]*disabled=""[^>]*type="checkbox">/g)).toHaveLength(2)
  expect(html).toMatch(/<label[^>]*>.*done<\/label>/)
})

test('list items carry the source line they start on', () => {
  const source = '# Plan\n\n- [ ] one\n- [x] two\n  - [ ] nested\n\n1. first\n'
  const html = renderMarkdown(source)
  const lines = [...html.matchAll(/data-line="(\d+)"/g)].map((match) => Number(match[1]))

  expect(lines).toEqual([2, 3, 4, 6])
})

test('interactive Markdown leaves task checkboxes enabled', () => {
  const source = '- [ ] a\n- [x] b\n'

  expect(renderMarkdown(source, { interactive: true })).not.toContain('disabled')
  expect(renderMarkdown(source).match(/disabled=""/g)).toHaveLength(2)
})

test('footnotes link both ways with numeric captions', () => {
  const html = renderMarkdown('Claim[^src].\n\n[^src]: The source.\n')

  expect(html).toContain('<sup class="footnote-ref"><a href="#fn1" id="fnref1">1</a></sup>')
  expect(html).toContain('<section class="footnotes">')
  expect(html).toContain('href="#fnref1" class="footnote-backref"')
})

test('GFM tables keep column alignment', () => {
  const html = renderMarkdown('| a | b |\n|:--|--:|\n| 1 | 2 |\n')

  expect(html).toContain('<th style="text-align:left">a</th>')
  expect(html).toContain('<td style="text-align:right">2</td>')
})

test('a fence in a known language renders plain and pending until its grammar arrives, then highlighted', () => {
  const fetched: string[] = []
  setGrammarFetcher((name) => fetched.push(name))
  const before = renderMarkdown('```jsonc\n{"a": 1}\n```')

  expect(fetched).toEqual(['json'])
  expect(before).toContain('<pre class="shiki plain" data-pending="json"><code>{&quot;a&quot;: 1}</code></pre>')

  registerGrammar('json', json)
  const after = renderMarkdown('```jsonc\n{"a": 1}\n```')

  expect(after).not.toContain('data-pending')
  expect(after).toContain('--shiki-dark:')
  expect(after).toContain('--shiki-light:')
})

test('an embedding grammar fetches its dependencies and an unknown language stays plain without fetching', () => {
  const fetched: string[] = []
  setGrammarFetcher((name) => fetched.push(name))
  const html = renderMarkdown('```htm\n<p>x</p>\n```\n\n```brainfuck\n+[]\n```')

  expect(fetched).toEqual(['javascript', 'css', 'html'])
  expect(html).toContain('data-pending="html"')
  expect(html).toContain('<pre class="shiki plain"><code>+[]</code></pre>')
})
