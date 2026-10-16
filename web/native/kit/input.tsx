import { useContext, type ReactNode } from 'react'
import type { FormValues } from 'canvas'
import { size } from '../fallback'
import { toJSONValue } from '../post'
import { FormContext, useCanvas } from './context'
import { h, slot, styleOf } from './host'
import type { PropsOf } from './props'

type Handler = ((event: never) => unknown) | undefined

type Change = { value?: unknown; checked?: unknown } | undefined

const noop = () => {}

/** Enough of a DOM event for handlers written against the web kit (`e.target.value`, `e.preventDefault()`). */
function syntheticEvent(type: string, target: Record<string, unknown>) {
  return { type, target, currentTarget: target, nativeEvent: {}, preventDefault: noop, stopPropagation: noop }
}

/** Swift calls `onChange` with `[{value}]` or `[{checked}]`; the author's handler gets an event. */
function changeHandler(handler: Handler, name: string | undefined) {
  if (!handler) return undefined

  return (change: Change) => {
    const target = { name, value: change?.value ?? '', checked: Boolean(change?.checked) }

    return handler(syntheticEvent('change', target) as never)
  }
}

function clickHandler(onClick: Handler, fallback: (() => void) | undefined) {
  if (onClick) return () => onClick(syntheticEvent('click', {}) as never)

  return fallback
}

export function Button({ variant = 'secondary', value, onClick, type, disabled, name, children, ...rest }: PropsOf<'Button'>) {
  const inForm = useContext(FormContext)
  const { submit } = useCanvas()
  const isSubmit = (type ?? (inForm && !onClick ? 'submit' : 'button')) === 'submit'
  const submitValue = !isSubmit && value !== undefined ? () => submit(value) : undefined

  return h(
    'Button',
    {
      variant,
      disabled: Boolean(disabled),
      onClick: clickHandler(onClick, submitValue),
      submit: isSubmit,
      name,
      value: value === undefined ? undefined : toJSONValue(value),
      style: styleOf(rest),
    },
    children,
  )
}

function fieldSlots(label: ReactNode, hint: ReactNode) {
  return [slot('label', label), slot('hint', hint)]
}

export function Input({ label, hint, name, value, defaultValue, placeholder, type = 'text', disabled, onChange, ...rest }: PropsOf<'Input'>) {
  return h(
    'Input',
    {
      name,
      value: value ?? defaultValue,
      placeholder,
      type,
      disabled: Boolean(disabled),
      onChange: changeHandler(onChange, name),
      style: styleOf(rest),
    },
    ...fieldSlots(label, hint),
  )
}

export function TextArea({ label, hint, name, value, defaultValue, placeholder, rows = 4, onChange, ...rest }: PropsOf<'TextArea'>) {
  return h(
    'TextArea',
    { name, value: value ?? defaultValue, placeholder, rows, onChange: changeHandler(onChange, name), style: styleOf(rest) },
    ...fieldSlots(label, hint),
  )
}

type Option = NonNullable<PropsOf<'Select'>['options']>[number]

function option(o: Option) {
  if (typeof o === 'string') return { value: o, label: o }
  const label = typeof o.label === 'string' || typeof o.label === 'number' ? String(o.label) : o.value

  return o.disabled ? { value: o.value, label, disabled: true } : { value: o.value, label }
}

export function Select({ label, hint, name, value, defaultValue, options, onChange, children, ...rest }: PropsOf<'Select'>) {
  return h(
    'Select',
    {
      name,
      value: value ?? defaultValue,
      options: (options ?? []).map(option),
      onChange: changeHandler(onChange, name),
      style: styleOf(rest),
    },
    ...fieldSlots(label, hint),
    children,
  )
}

export function Checkbox({ label, hint, name, checked, defaultChecked, onChange, ...rest }: PropsOf<'Checkbox'>) {
  return h(
    'Checkbox',
    { name, checked: checked ?? defaultChecked, onChange: changeHandler(onChange, name), style: styleOf(rest) },
    ...fieldSlots(label, hint),
  )
}

/** Swift collects the fields and calls `onSubmit` with `[values]`; without the author's handler the values are the result. */
export function Form({ onSubmit, gap = 16, children, ...rest }: PropsOf<'Form'>) {
  const { submit } = useCanvas()

  const handleSubmit = (values: FormValues | undefined) => {
    if (onSubmit) onSubmit(values ?? {}, syntheticEvent('submit', {}) as never)
    else submit(values ?? {})
  }

  return (
    <FormContext.Provider value={true}>
      {h('Form', { gap: size(gap, 'Form gap'), onSubmit: handleSubmit, style: styleOf(rest) }, children)}
    </FormContext.Provider>
  )
}
