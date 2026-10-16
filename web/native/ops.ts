import { post } from './post'

export type Op =
  | { op: 'create'; id: number; type: string; props: Record<string, unknown> }
  | { op: 'text'; id: number; text: string }
  | { op: 'append'; parent: number; child: number }
  | { op: 'insert'; parent: number; child: number; before: number }
  | { op: 'remove'; parent: number; child: number }
  | { op: 'props'; id: number; props: Record<string, unknown> }
  | { op: 'setText'; id: number; text: string }

export const ROOT = 0

let pending: Op[] = []
let muted = false
/** Root children Swift's tree holds, as of the last posted batch. */
let shown: number[] = []
/** Root children Swift still holds that the runtime has forgotten; the next batch removes them first. */
let stale: number[] = []

export function record(op: Op) {
  if (!muted) pending.push(op)
}

function track(op: Op) {
  if (op.op !== 'append' && op.op !== 'insert' && op.op !== 'remove') return
  shown = shown.filter((id) => id !== op.child)

  if (op.parent !== ROOT || op.op === 'remove') return
  const at = op.op === 'insert' ? shown.indexOf(op.before) : -1

  if (at < 0) shown.push(op.child)
  else shown.splice(at, 0, op.child)
}

/** Posts the commit's ops as one batch. */
export function flush() {
  if (muted) return
  const batch: Op[] = [...stale.map((child): Op => ({ op: 'remove', parent: ROOT, child })), ...pending]
  pending = []
  stale = []

  if (batch.length === 0) return

  for (const op of batch) track(op)
  post({ type: 'ops', ops: batch })
}

/** Drops the commit in progress without posting it. */
export function discard() {
  pending = []
}

/** Runs `body` with ops neither recorded nor posted. */
export function silently(body: () => void) {
  const outer = muted
  muted = true

  try {
    body()
  } finally {
    muted = outer
    pending = []
  }
}

/**
 * Forgets the tree after a silent unmount. With `swiftKeeps`, Swift's tree still holds the old root children, so the
 * next batch removes them; otherwise Swift starts from an empty tree too.
 */
export function forgetTree(swiftKeeps: boolean) {
  stale = swiftKeeps ? [...stale, ...shown] : []
  shown = []
}
