type Fn = (...args: unknown[]) => unknown

/** Function props by `$fn` id. An id stays with its node and prop while the prop stays a function. */
const fns = new Map<number, Fn>()
const byNode = new Map<number, Map<string, number>>()
let nextId = 1

export function functionId(node: number, prop: string, fn: Fn) {
  let props = byNode.get(node)

  if (!props) {
    props = new Map()
    byNode.set(node, props)
  }

  let id = props.get(prop)

  if (id === undefined) {
    id = nextId++
    props.set(prop, id)
  }

  fns.set(id, fn)

  return id
}

/** Forgets the node's function props that aren't in `keep`. */
export function pruneFunctions(node: number, keep: ReadonlySet<string>) {
  const props = byNode.get(node)

  if (!props) return

  for (const [prop, id] of props) {
    if (keep.has(prop)) continue
    props.delete(prop)
    fns.delete(id)
  }
}

export function dropFunctions(node: number) {
  pruneFunctions(node, new Set())
  byNode.delete(node)
}

export function clearFunctions() {
  fns.clear()
  byNode.clear()
}

export function callFunction(id: number, args: unknown[]) {
  const fn = fns.get(id)

  if (!fn) throw new Error(`No function ${id}; its node is gone or the prop changed`)

  return fn(...args)
}
