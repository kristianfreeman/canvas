import { createContext, useContext, useMemo, type ReactNode } from 'react'
import { close, submit } from '../bridge'
import { publish } from './channels'

export type CanvasApi = {
  submit: (value: unknown) => void
  close: () => void
  publish: (channel: string, value: unknown) => void
  data: unknown
  wait: boolean
}

const fallback: CanvasApi = { submit, close, publish, data: undefined, wait: false }
const CanvasContext = createContext<CanvasApi>(fallback)

export function CanvasProvider({ data, wait, children }: { data: unknown; wait: boolean; children: ReactNode }) {
  const api = useMemo(() => ({ submit, close, publish, data, wait }), [data, wait])

  return <CanvasContext.Provider value={api}>{children}</CanvasContext.Provider>
}

export function useCanvas(): CanvasApi {
  return useContext(CanvasContext)
}

export const FormContext = createContext(false)
