import {
  Component,
  createElement,
  isValidElement,
  useCallback,
  useEffect,
  useLayoutEffect,
  useRef,
  type ComponentType,
  type ReactNode,
  type Ref,
} from 'react'
import { close, post, submit } from './bridge'
import { CanvasProvider } from './kit'
import { measureSurface } from './measure'
import { getState, reportError, useStore, type CanvasError, type Content, type Payload } from './store'

class ErrorBoundary extends Component<{ id: number; children: ReactNode }, { failed: boolean }> {
  state = { failed: false }

  static getDerivedStateFromError() {
    return { failed: true }
  }

  componentDidCatch(error: unknown) {
    reportError(error, this.props.id)
  }

  render() {
    return this.state.failed ? null : this.props.children
  }
}

function ErrorBox({ error }: { error: CanvasError }) {
  return (
    <div className="cv-error" role="alert">
      <div className="cv-error-label">Error</div>
      <div className="cv-error-message">{error.message}</div>
      {error.stack && <pre className="cv-error-stack">{error.stack}</pre>}
    </div>
  )
}

function CloseIcon() {
  return (
    <svg width="12" height="12" viewBox="0 0 12 12" aria-hidden>
      <path d="M2.5 2.5l7 7M9.5 2.5l-7 7" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
    </svg>
  )
}

function hasContent() {
  const { id, payload, error } = getState()

  return id > 0 && (payload !== null || error !== null)
}

/** Reports the page's natural size to Swift and keeps the header and footer edge shadows in sync with scrolling. */
function usePanelSize(hasFooter: boolean) {
  const headerRef = useRef<HTMLElement>(null)
  const scrollRef = useRef<HTMLElement>(null)
  const contentRef = useRef<HTMLDivElement>(null)
  const footerRef = useRef<HTMLElement>(null)
  const lastSize = useRef('')

  const updateEdges = useCallback(() => {
    const el = scrollRef.current

    if (!el) return
    headerRef.current?.classList.toggle('is-scrolled', el.scrollTop > 0)
    footerRef.current?.classList.toggle('is-overflowing', el.scrollTop + el.clientHeight < el.scrollHeight - 1)
  }, [])

  const measure = useCallback(() => {
    if (!hasContent()) return
    const { width, height } = measureSurface()
    const key = `${getState().id}:${width}x${height}`
    updateEdges()

    if (key === lastSize.current) return
    lastSize.current = key
    post({ type: 'size', width, height })
  }, [updateEdges])

  useEffect(() => {
    const observer = new ResizeObserver(() => measure())

    for (const el of [headerRef.current, contentRef.current, hasFooter ? footerRef.current : null]) {
      if (el) observer.observe(el, { box: 'border-box' })
    }

    return () => observer.disconnect()
  }, [measure, hasFooter])

  useEffect(() => {
    document.fonts?.ready.then(() => measure())
  }, [measure])

  useLayoutEffect(() => measure())

  return { headerRef, scrollRef, contentRef, footerRef, updateEdges }
}

/** Markdown HTML goes straight into the DOM so React never diffs the document body. */
function MarkdownBody({ html }: { html: string }) {
  const ref = useRef<HTMLDivElement>(null)

  useLayoutEffect(() => {
    if (ref.current) ref.current.innerHTML = html
  }, [html])

  return <div className="cv-prose" ref={ref} />
}

function Body({ content, data }: { content: Content; data: unknown }) {
  if (content.kind === 'markdown') return <MarkdownBody html={content.html} />

  if (content.kind === 'none') return null
  const exported = content.component

  return (
    <div className="cv-app">
      {isValidElement(exported) ? exported : createElement(exported as ComponentType<{ data: unknown }>, { data })}
    </div>
  )
}

/** The first label is the primary button, placed rightmost. */
function Footer({ buttons, ref }: { buttons: string[]; ref: Ref<HTMLElement> }) {
  return (
    <footer className="cv-footer" ref={ref}>
      {buttons
        .map((label, index) => ({ label, index }))
        .toReversed()
        .map(({ label, index }) => (
          <button
            key={index}
            type="button"
            className={index === 0 ? 'cv-btn cv-btn-primary' : 'cv-btn cv-btn-secondary'}
            data-canvas-primary={index === 0 ? '' : undefined}
            onClick={() => submit(label)}
          >
            {label}
            {index === 0 && <span className="cv-btn-hint">⌘↩</span>}
          </button>
        ))}
    </footer>
  )
}

const NO_PAYLOAD: Partial<Payload> = {}

function footerButtons(payload: Payload | null) {
  return payload?.buttons?.filter((b) => typeof b === 'string' && b.length > 0) ?? []
}

export function Shell() {
  const { id, payload, content, error } = useStore()
  const { title = '', data, wait = false } = payload ?? NO_PAYLOAD
  const buttons = footerButtons(payload)
  const { headerRef, scrollRef, contentRef, footerRef, updateEdges } = usePanelSize(buttons.length > 0)

  return (
    <div className="cv-surface">
      <header className="cv-header" ref={headerRef}>
        <div className="cv-title">{title}</div>
        <button type="button" className="cv-close" aria-label="Close" tabIndex={-1} onClick={close}>
          <CloseIcon />
        </button>
      </header>
      <main className="cv-scroll" ref={scrollRef} onScroll={updateEdges}>
        <div className="cv-content" ref={contentRef}>
          {error && <ErrorBox error={error} />}
          <CanvasProvider key={id} data={data} wait={wait}>
            <ErrorBoundary key={id} id={id}>
              <Body content={content} data={data} />
            </ErrorBoundary>
          </CanvasProvider>
        </div>
      </main>
      {buttons.length > 0 && <Footer buttons={buttons} ref={footerRef} />}
    </div>
  )
}
