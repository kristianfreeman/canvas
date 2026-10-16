import type { Op } from './ops'

/** The view tree Swift would hold after applying the ops, for tests. Text nodes have type `#text`. */
export type TreeNode = { id: number; type: string; props: Record<string, unknown>; children: TreeNode[]; text?: string }

type Nodes = Map<number, TreeNode>

function node(nodes: Nodes, id: number) {
  const found = nodes.get(id)

  if (!found) throw new Error(`op refers to unknown node ${id}`)

  return found
}

function detach(nodes: Nodes, id: number) {
  for (const other of nodes.values()) other.children = other.children.filter((child) => child.id !== id)
}

/** As in Swift's ViewTree, attaching a node that has a parent moves it. */
function attach(nodes: Nodes, op: { parent: number; child: number; before?: number }) {
  detach(nodes, op.child)
  const children = node(nodes, op.parent).children
  const at = op.before === undefined ? -1 : children.findIndex((child) => child.id === op.before)

  if (at < 0) children.push(node(nodes, op.child))
  else children.splice(at, 0, node(nodes, op.child))
}

const appliers: { [K in Op['op']]: (nodes: Nodes, op: Extract<Op, { op: K }>) => void } = {
  create: (nodes, op) => nodes.set(op.id, { id: op.id, type: op.type, props: op.props, children: [] }),
  text: (nodes, op) => nodes.set(op.id, { id: op.id, type: '#text', props: {}, children: [], text: op.text }),
  append: attach,
  insert: attach,
  remove: (nodes, op) => detach(nodes, op.child),
  props: (nodes, op) => {
    node(nodes, op.id).props = op.props
  },
  setText: (nodes, op) => {
    node(nodes, op.id).text = op.text
  },
}

export function replay(batches: Op[][]): TreeNode {
  const nodes: Nodes = new Map([[0, { id: 0, type: '#root', props: {}, children: [] }]])

  for (const op of batches.flat()) (appliers[op.op] as (nodes: Nodes, op: Op) => void)(nodes, op)

  return node(nodes, 0)
}

/** Every node of `type` under `root`, in document order. */
export function findAll(root: TreeNode, type: string): TreeNode[] {
  return root.children.flatMap((child) => [...(child.type === type ? [child] : []), ...findAll(child, type)])
}

export function textOf(root: TreeNode): string {
  return root.text ?? root.children.map(textOf).join('')
}

/** The `$fn` id of a function prop. */
export function fnOf(target: TreeNode, prop: string): number {
  const value = target.props[prop] as { $fn?: number } | undefined

  if (typeof value?.$fn !== 'number') throw new Error(`${target.type} has no function prop ${prop}`)

  return value.$fn
}
