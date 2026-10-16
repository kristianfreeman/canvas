import { invoke, push, render, reportError, reset, setData, warm } from './root'

const api = { render, setData, invoke, push, reset, warm, reportError }

declare global {
  var canvasNative: typeof api
}

/** The calls Swift makes into the context (docs/native.md, Calls). */
globalThis.canvasNative = api
