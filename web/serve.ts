/**
 * Dev harness: http://localhost:5178/?file=examples/dashboard.tsx&data=examples/keys.json&theme=dark&wait=1
 *
 * Loads dist/index.html in an iframe sized like the native panel (720 wide, height from `size`
 * messages capped at `maxh`), stubs the WebKit message handler, and calls window.canvas.render(),
 * showing the returned height and timing.
 *
 * Query: file, data, source + kind (inline source), title, buttons (comma list), theme, accent, wait,
 * width, maxh, log=0 (hide the message log), bg (page background color), warm=1 (call warm() first),
 * push=<channel> (answer `subscribe` with 60 values of history, then push a random walk every 250ms).
 * GET /messages returns every posted message as JSON (?clear=1 empties it).
 */
import { join, normalize, relative } from 'node:path'

const webDir = import.meta.dir
const repoRoot = join(webDir, '..')
const port = Number(process.env.PORT ?? 5178)
let messages: unknown[] = []

function inside(base: string, path: string) {
  const full = normalize(join(base, path))

  return relative(base, full).startsWith('..') ? null : full
}

const harness = /* html */ `<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>Canvas harness</title>
<style>
  body { margin: 0; font: 12px/1.5 ui-monospace, Menlo, monospace; background: var(--bg, #3a3f4b); color: #ddd; display: flex; gap: 24px; padding: 40px; align-items: flex-start; min-height: 100vh; box-sizing: border-box; }
  #panel { border: 0; display: block; border-radius: 14px; box-shadow: 0 0 0 1px rgba(255,255,255,.1), 0 20px 50px rgba(0,0,0,.45); background: #0a0a0a; overflow: hidden; transition: opacity .2s; }
  #panel.light { background: #ffffff; box-shadow: 0 0 0 1px rgba(0,0,0,.1), 0 20px 50px rgba(0,0,0,.25); }
  #panel.closed { opacity: .25; }
  #side { flex: 1; min-width: 280px; display: flex; flex-direction: column; gap: 10px; }
  #status { background: rgba(0,0,0,.35); border-radius: 10px; padding: 8px 12px; white-space: pre-wrap; }
  #log { max-height: calc(100vh - 140px); overflow: auto; background: rgba(0,0,0,.35); border-radius: 10px; padding: 10px 12px; white-space: pre-wrap; word-break: break-all; }
  #log div { padding: 2px 0; border-bottom: 1px solid rgba(255,255,255,.06); }
  #log .error { color: #ff6961; } #log .result { color: #63e6a0; } #log .close, #log .open, #log .publish { color: #ffd60a; }
</style>
</head>
<body>
<iframe id="panel" src="/dist/index.html"></iframe>
<div id="side"><div id="status">loading…</div><div id="log"></div></div>
<script>
  const params = new URLSearchParams(location.search)
  const frame = document.getElementById('panel')
  const logEl = document.getElementById('log')
  const statusEl = document.getElementById('status')
  const width = Number(params.get('width') || 720)
  const maxh = Number(params.get('maxh') || 765)
  const pushChannel = params.get('push')
  if (params.get('log') === '0') document.getElementById('side').remove()
  if (params.get('bg')) document.body.style.setProperty('--bg', params.get('bg'))
  frame.style.width = width + 'px'
  frame.style.height = '120px'

  const theme = params.get('theme') || 'auto'
  const dark = theme === 'dark' || (theme === 'auto' && matchMedia('(prefers-color-scheme: dark)').matches)
  frame.classList.toggle('light', !dark)

  const walk = { history: [], subscribed: false }
  for (let i = 0, v = 50; i < 60; i++) walk.history.push(v = step(v))
  function step(v) { return Math.max(0, Math.min(100, Math.round((v + (Math.random() - 0.5) * 12) * 10) / 10)) }
  function pushWalk(full) {
    const latest = walk.history[walk.history.length - 1]
    frame.contentWindow.canvas.push([{ channel: pushChannel, value: latest, history: full ? walk.history.slice() : [latest] }])
  }
  if (pushChannel) setInterval(() => {
    walk.history.push(step(walk.history[walk.history.length - 1]))
    if (walk.history.length > 300) walk.history.shift()
    if (walk.subscribed) pushWalk(false)
  }, 250)

  function onMessage(m) {
    if (logEl.isConnected && !(m.type === 'size' && pushChannel)) {
      const row = document.createElement('div')
      row.className = m.type
      row.textContent = JSON.stringify(m)
      logEl.prepend(row)
    }
    fetch('/log', { method: 'POST', body: JSON.stringify(m) })
    if (m.type === 'size') frame.style.height = Math.min(m.height, maxh) + 'px'
    if (m.type === 'close' || m.type === 'result') frame.classList.add('closed')
    if (m.channel === pushChannel && m.type === 'subscribe') { walk.subscribed = true; setTimeout(() => pushWalk(true)) }
    if (m.channel === pushChannel && m.type === 'unsubscribe') walk.subscribed = false
  }

  async function text(path) {
    const res = await fetch('/raw?path=' + encodeURIComponent(path))
    if (!res.ok) throw new Error(path + ': ' + res.status)
    return res.text()
  }

  async function payloadFromParams() {
    const file = params.get('file')
    const source = params.has('source') ? params.get('source') : file ? await text(file) : '# Canvas harness\\n\\nPass ?file=examples/hello.md'
    const kind = params.get('kind') || (file && /\\.(tsx|jsx|ts)$/.test(file) ? 'tsx' : 'markdown')
    const dataParam = params.get('data')
    let data
    if (dataParam) data = /^[\\[{"\\d]/.test(dataParam) ? JSON.parse(dataParam) : JSON.parse(await text(dataParam))
    const buttons = params.get('buttons') ? params.get('buttons').split(',') : undefined
    const accent = params.get('accent') ?? undefined
    return { kind, source, title: params.get('title') ?? file ?? undefined, data, buttons, wait: params.get('wait') === '1', theme, accent }
  }

  function render(payload) {
    const result = frame.contentWindow.canvas.render(payload)
    const ms = (result.jsEnd - result.jsStart).toFixed(2)
    statusEl.textContent = 'render(): height ' + result.height + ', ' + ms + ' ms' + (result.error ? ', error: ' + result.error : '')
    frame.style.height = Math.min(result.height, maxh) + 'px'
    return result
  }

  window.harness = { render, payloadFromParams, canvas: () => frame.contentWindow.canvas }

  frame.addEventListener('load', async () => {
    frame.contentWindow.canvasHarnessPost = onMessage
    try {
      if (params.get('warm') === '1') frame.contentWindow.canvas.warm()
      render(await payloadFromParams())
    } catch (e) {
      onMessage({ type: 'harness-error', message: String(e) })
    }
  })
</script>
</body>
</html>`

const notFound = () => new Response('not found', { status: 404 })

const TYPES: Record<string, string> = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8' }

async function serveDist(url: URL) {
  const path = inside(join(webDir, 'dist'), url.pathname.slice('/dist/'.length))
  const file = path ? Bun.file(path) : null

  if (!file || !(await file.exists())) return new Response('Run `bun run build` first.', { status: 404 })
  const type = TYPES[path!.slice(path!.lastIndexOf('.'))] ?? 'application/octet-stream'

  return new Response(file, { headers: { 'content-type': type, 'cache-control': 'no-store' } })
}

async function serveRaw(url: URL) {
  const path = inside(repoRoot, url.searchParams.get('path') ?? '')
  const file = path ? Bun.file(path) : null

  if (!file || !(await file.exists())) return notFound()

  return new Response(file, { headers: { 'content-type': 'text/plain; charset=utf-8', 'cache-control': 'no-store' } })
}

async function logMessage(req: Request) {
  const message = await req.json()
  messages.push(message)
  console.log('[page]', JSON.stringify(message))

  return new Response('ok')
}

function listMessages(url: URL) {
  const body = JSON.stringify(messages)

  if (url.searchParams.has('clear')) messages = []

  return new Response(body, { headers: { 'content-type': 'application/json' } })
}

Bun.serve({
  port,
  hostname: '127.0.0.1',
  fetch(req) {
    const url = new URL(req.url)

    if (url.pathname === '/') return new Response(harness, { headers: { 'content-type': 'text/html; charset=utf-8' } })

    if (url.pathname.startsWith('/dist/')) return serveDist(url)

    if (url.pathname === '/raw') return serveRaw(url)

    if (url.pathname === '/log' && req.method === 'POST') return logMessage(req)

    if (url.pathname === '/messages') return listMessages(url)

    return notFound()
  },
})

console.log(`Canvas harness on http://localhost:${port}/?file=examples/hello.md`)
