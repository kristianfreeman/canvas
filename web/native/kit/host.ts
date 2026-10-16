import { createElement, type ReactNode } from 'react'
import { checkClassName, nativeStyle } from '../fallback'
import { KIT_MARK } from '../host'

type HostProps = Record<string, unknown>

/** A host element: one of the native types in docs/native.md. */
export function h(type: string, props: HostProps, ...children: ReactNode[]) {
  return createElement(type, props, ...children)
}

/** A `slot` child holding a ReactNode prop, or nothing when the prop is undefined. */
export function slot(name: string, content: ReactNode) {
  return content === undefined ? null : createElement('slot', { key: name, name, kitMark: KIT_MARK }, content)
}

/** The `style` prop every kit element forwards, after the className and style checks. */
export function styleOf(props: { className?: unknown; style?: unknown }) {
  checkClassName(props)

  return nativeStyle(props.style)
}
