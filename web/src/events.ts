import { escapeClose, post } from './bridge'
import { reportError } from './store'

const EDITABLE = 'input, textarea, select, [contenteditable=""], [contenteditable="true"]'

/** The first Esc only blurs a focused field; the next one closes the panel. */
function handleEscape(event: KeyboardEvent) {
  // Always swallow Esc so the native panel doesn't also close (or close on a blur-only Esc).
  event.preventDefault()
  event.stopPropagation()
  const active = document.activeElement as HTMLElement | null

  if (active && active !== document.body && active.matches(EDITABLE)) active.blur()
  else escapeClose()
}

/** Cmd+Enter presses the footer's primary button, else submits the focused (or first) form. */
function pressPrimary(event: KeyboardEvent) {
  const footerPrimary = document.querySelector<HTMLButtonElement>('[data-canvas-primary]')

  if (footerPrimary) {
    event.preventDefault()
    footerPrimary.click()

    return
  }

  const form = (document.activeElement as HTMLElement | null)?.closest('form') ?? document.querySelector('form')

  if (!form) return
  event.preventDefault()

  const submitter = form.querySelector<HTMLButtonElement>('button[type="submit"][data-variant="primary"]:not(:disabled)')

  form.requestSubmit(submitter ?? undefined)
}

function scrollToHash(href: string) {
  const id = decodeURIComponent(href.slice(1))
  const target = id ? document.getElementById(id) ?? document.getElementsByName(id)[0] : null

  if (target) target.scrollIntoView({ behavior: 'smooth', block: 'start' })
  else if (!id) document.querySelector('.cv-scroll')?.scrollTo({ top: 0, behavior: 'smooth' })
}

function handleLinkClick(event: MouseEvent) {
  const anchor = (event.target as Element | null)?.closest?.('a[href]') as HTMLAnchorElement | null

  if (!anchor) return
  event.preventDefault()
  const href = anchor.getAttribute('href') ?? ''

  if (href.startsWith('#')) {
    scrollToHash(href)

    return
  }

  const url = anchor.href

  if (/^(javascript|data|blob):/i.test(url)) return
  post({ type: 'open', url })
}

export function installEventHandlers() {
  window.addEventListener(
    'keydown',
    (event) => {
      if (event.key === 'Escape') handleEscape(event)
      else if (event.key === 'Enter' && event.metaKey && !event.isComposing) pressPrimary(event)
    },
    true,
  )

  document.addEventListener('click', handleLinkClick)

  document.addEventListener('auxclick', (event) => {
    if ((event.target as Element | null)?.closest?.('a[href]')) event.preventDefault()
  })

  // Native forms outside the kit's Form would otherwise navigate the webview.
  window.addEventListener('submit', (event) => event.preventDefault())
  document.addEventListener('dragover', (event) => event.preventDefault())
  document.addEventListener('drop', (event) => event.preventDefault())

  window.addEventListener('error', (event) => {
    if (/ResizeObserver loop/.test(event.message ?? '')) return
    reportError(event.error ?? event.message)
  })

  window.addEventListener('unhandledrejection', (event) => {
    reportError(event.reason ?? 'Unhandled promise rejection')
  })
}
