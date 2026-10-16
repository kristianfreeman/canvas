import { createContext } from 'react'
import { DiscreteEventPriority, NoEventPriority } from 'react-reconciler/constants'
import { checkClassName, nativeStyle, needsWeb } from './fallback'
import { dropFunctions } from './functions'
import { record, ROOT } from './ops'
import { refreshFunctions, sameProps, wireProps, type Props } from './props'

export type Instance = { id: number; type: string; props: Props; json: string; children: Node[]; sent: boolean }
export type TextInstance = { id: number; text: string; sent: boolean; type?: undefined }
type Node = Instance | TextInstance
export type Container = { id: typeof ROOT }

/** Marks host elements the kit shim makes, so its lowercase `slot` passes the DOM-tag check. */
export const KIT_MARK = Object.freeze({})

export const HOST_TYPES = new Set([
  'Stack', 'Row', 'Grid', 'Divider', 'Spacer', 'Heading', 'Text', 'Code', 'CodeBlock', 'Markdown', 'Kbd',
  'KeyChips', 'Card', 'Table', 'TableRow', 'TableCell', 'Stat', 'Badge', 'Progress', 'BarChart', 'Sparkline',
  'Button', 'Input', 'TextArea', 'Select', 'Checkbox', 'Form', 'Footer', 'slot',
])

/** Ids are never reused within a context, so a late op can't hit a newer node. */
let nextId = 1

function validate(type: string, props: Props) {
  if (type === 'slot' && props.kitMark !== KIT_MARK) needsWeb('<slot> is a DOM tag')

  if (/^[a-z]/.test(type) && type !== 'slot') needsWeb(`<${type}> is a DOM tag`)

  if (!HOST_TYPES.has(type)) needsWeb(`<${type}> is not a native element`)
  checkClassName(props)
  nativeStyle(props.style)
}

/** Records the node and its initial subtree the first time it's attached, so discarded renders never reach Swift. */
function emit(node: Node) {
  if (node.sent) return
  node.sent = true

  if (node.type === undefined) return record({ op: 'text', id: node.id, text: node.text })
  const props = wireProps(node.id, node.props)
  node.json = JSON.stringify(props)
  record({ op: 'create', id: node.id, type: node.type, props })

  for (const child of node.children) {
    emit(child)
    record({ op: 'append', parent: node.id, child: child.id })
  }

  node.children = []
}

function attach(parent: number, child: Node, before?: Node) {
  emit(child)
  record(before ? { op: 'insert', parent, child: child.id, before: before.id } : { op: 'append', parent, child: child.id })
}

function update(instance: Instance, next: Props) {
  const prev = instance.props
  instance.props = next

  if (sameProps(prev, next)) return refreshFunctions(instance.id, next)
  const props = wireProps(instance.id, next)
  const json = JSON.stringify(props)

  if (json === instance.json) return
  instance.json = json
  record({ op: 'props', id: instance.id, props })
}

let priority = NoEventPriority

export function setPriority(next: number) {
  priority = next
}

const noop = () => {}

const capabilities = {
  supportsMutation: true,
  supportsPersistence: false,
  supportsHydration: false,
  supportsMicrotasks: true,
  isPrimaryRenderer: true,
  warnsIfNotActing: false,
  noTimeout: -1,
  rendererVersion: '1',
  rendererPackageName: 'canvas-native',
  extraDevToolsConfig: null,
  NotPendingTransition: null,
  HostTransitionContext: createContext(null),
}

const creation = {
  createInstance(type: string, props: Props): Instance {
    validate(type, props)

    return { id: nextId++, type, props, json: '', children: [], sent: false }
  },
  createTextInstance: (text: string): TextInstance => ({ id: nextId++, text, sent: false }),
  appendInitialChild: (parent: Instance, child: Node) => parent.children.push(child),
  finalizeInitialChildren: () => false,
  shouldSetTextContent: () => false,
  getRootHostContext: () => ({}),
  getChildHostContext: (parent: object) => parent,
  getPublicInstance: (instance: Node) => instance,
  prepareForCommit: () => null,
  preparePortalMount: noop,
}

const mutation = {
  appendChild: (parent: Instance, child: Node) => attach(parent.id, child),
  appendChildToContainer: (_: Container, child: Node) => attach(ROOT, child),
  insertBefore: (parent: Instance, child: Node, before: Node) => attach(parent.id, child, before),
  insertInContainerBefore: (_: Container, child: Node, before: Node) => attach(ROOT, child, before),
  removeChild: (parent: Instance, child: Node) => record({ op: 'remove', parent: parent.id, child: child.id }),
  removeChildFromContainer: (_: Container, child: Node) => record({ op: 'remove', parent: ROOT, child: child.id }),
  commitUpdate: (instance: Instance, ...[, , next]: [string, Props, Props]) => update(instance, next),
  commitTextUpdate(text: TextInstance, _old: string, next: string) {
    text.text = next
    record({ op: 'setText', id: text.id, text: next })
  },
  detachDeletedInstance: (node: Node) => dropFunctions(node.id),
  resetTextContent: noop,
  clearContainer: noop,
  commitMount: noop,
  hideInstance: noop,
  unhideInstance: noop,
  hideTextInstance: noop,
  unhideTextInstance: noop,
}

const scheduling = {
  scheduleTimeout: (fn: () => void, ms?: number) => setTimeout(fn, ms),
  cancelTimeout: (id: ReturnType<typeof setTimeout>) => clearTimeout(id),
  scheduleMicrotask: (fn: () => void) => queueMicrotask(fn),
  setCurrentUpdatePriority: setPriority,
  getCurrentUpdatePriority: () => priority,
  resolveUpdatePriority: () => (priority === NoEventPriority ? DiscreteEventPriority : priority),
  resolveEventType: () => null,
  resolveEventTimeStamp: () => -1.1,
  trackSchedulerEvent: noop,
  shouldAttemptEagerTransition: () => false,
  requestPostPaintCallback: noop,
  bindToConsole: (method: 'log' | 'warn' | 'error', args: unknown[]) => console[method].bind(console, ...args),
}

/** Focus, scopes, forms and suspended commits: DOM features with nothing to do natively. */
const unused = {
  resetFormInstance: noop,
  getInstanceFromNode: () => null,
  getInstanceFromScope: () => null,
  beforeActiveInstanceBlur: noop,
  afterActiveInstanceBlur: noop,
  prepareScopeUpdate: noop,
  maySuspendCommit: () => false,
  maySuspendCommitOnUpdate: () => false,
  maySuspendCommitInSyncRender: () => false,
  mayResourceSuspendCommit: () => false,
  preloadInstance: () => true,
  startSuspendingCommit: noop,
  suspendInstance: noop,
  waitForCommitToBeReady: () => null,
  getSuspendedCommitReason: () => null,
}

/**
 * Mutation-mode host config. Ops are recorded during the commit and posted by `onCommit` (resetAfterCommit). Updates
 * outside a transition are discrete, so every setState commits synchronously or in the next microtask.
 */
export function hostConfig(onCommit: () => void) {
  return { ...capabilities, ...creation, ...mutation, ...scheduling, ...unused, resetAfterCommit: onCommit }
}
