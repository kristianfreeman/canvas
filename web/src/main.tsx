import { flushSync } from 'react-dom'
import { createRoot } from 'react-dom/client'
import { push, render, reset, setData, type RenderResult } from './api'
import { installEventHandlers } from './events'
import { installGrammarLoader } from './grammar-loader'
import { Shell } from './Shell'
import { reportError, type Payload } from './store'
import { setAccent, setTheme } from './theme'
import { warm } from './warm'

declare global {
  interface Window {
    canvas: {
      render(payload: Payload | string): RenderResult
      setData(data: unknown): { height: number }
      push(batch: unknown): void
      reset(): void
      warm(): void
      /** Sets `--accent` and its contrasting `--accent-fg` to any CSS color; anything else restores the default. */
      setAccent(color?: string | null): void
    }
  }
}

setTheme('auto')
installGrammarLoader()
installEventHandlers()

const root = createRoot(document.getElementById('root')!, {
  onUncaughtError: (error) => reportError(error),
})

// The first render() must find the shell committed, so mount it synchronously.
flushSync(() => root.render(<Shell />))

window.canvas = { render, setData, push, reset, warm, setAccent }
