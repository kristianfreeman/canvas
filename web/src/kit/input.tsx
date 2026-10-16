import {
  useContext,
  type ButtonHTMLAttributes,
  type CSSProperties,
  type FormEvent,
  type InputHTMLAttributes,
  type MouseEvent,
  type ReactNode,
  type SelectHTMLAttributes,
  type TextareaHTMLAttributes,
} from 'react'
import { FormContext, useCanvas } from './context'
import { cx, px } from './util'

type ButtonProps = Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'value'> & {
  variant?: 'primary' | 'secondary' | 'ghost' | 'danger'
  value?: unknown
}

export function Button({ variant = 'secondary', value, onClick, type, className, children, ...rest }: ButtonProps) {
  const inForm = useContext(FormContext)
  const { submit } = useCanvas()
  const resolvedType = type ?? (inForm && !onClick ? 'submit' : 'button')
  const nativeValue = typeof value === 'string' || typeof value === 'number' ? value : undefined

  const handleClick = (event: MouseEvent<HTMLButtonElement>) => {
    if (onClick) return onClick(event)

    if (value !== undefined && resolvedType !== 'submit') submit(value)
  }

  return (
    <button
      {...rest}
      type={resolvedType}
      value={nativeValue}
      data-variant={variant}
      className={cx('cv-btn', `cv-btn-${variant}`, className)}
      onClick={handleClick}
    >
      {children}
    </button>
  )
}

function Field({ label, hint, children }: { label?: ReactNode; hint?: ReactNode; children: ReactNode }) {
  if (label === undefined && hint === undefined) return <>{children}</>

  return (
    <label className="cv-field">
      {label !== undefined && <span className="cv-label">{label}</span>}
      {children}
      {hint !== undefined && <span className="cv-hint">{hint}</span>}
    </label>
  )
}

type InputProps = Omit<InputHTMLAttributes<HTMLInputElement>, 'size'> & { label?: ReactNode; hint?: ReactNode }

export function Input({ label, hint, className, type = 'text', ...rest }: InputProps) {
  return (
    <Field label={label} hint={hint}>
      <input {...rest} type={type} className={cx('cv-input', className)} />
    </Field>
  )
}

type TextAreaProps = TextareaHTMLAttributes<HTMLTextAreaElement> & { label?: ReactNode; hint?: ReactNode }

export function TextArea({ label, hint, className, rows = 4, ...rest }: TextAreaProps) {
  return (
    <Field label={label} hint={hint}>
      <textarea {...rest} rows={rows} className={cx('cv-input', 'cv-textarea', className)} />
    </Field>
  )
}

type Option = string | { value: string; label?: ReactNode; disabled?: boolean }

type SelectProps = SelectHTMLAttributes<HTMLSelectElement> & {
  label?: ReactNode
  hint?: ReactNode
  options?: Option[]
}

export function Select({ label, hint, options, className, children, ...rest }: SelectProps) {
  return (
    <Field label={label} hint={hint}>
      <span className={cx('cv-select', className)}>
        <select {...rest} className="cv-input">
          {options?.map((o) =>
            typeof o === 'string' ? (
              <option key={o} value={o}>
                {o}
              </option>
            ) : (
              <option key={o.value} value={o.value} disabled={o.disabled}>
                {o.label ?? o.value}
              </option>
            ),
          )}
          {children}
        </select>
      </span>
    </Field>
  )
}

type CheckboxProps = Omit<InputHTMLAttributes<HTMLInputElement>, 'type'> & { label?: ReactNode; hint?: ReactNode }

export function Checkbox({ label, hint, className, ...rest }: CheckboxProps) {
  return (
    <label className={cx('cv-check', className)}>
      <input {...rest} type="checkbox" className="cv-check-input" />
      <span className="cv-check-text">
        {label}
        {hint !== undefined && <span className="cv-hint">{hint}</span>}
      </span>
    </label>
  )
}

export type FormValues = Record<string, unknown>

const BUTTON_TYPES = new Set(['submit', 'button', 'reset'])

function isCollected(el: HTMLInputElement) {
  if (!el.name || el.disabled) return false

  return el.tagName !== 'BUTTON' && el.tagName !== 'FIELDSET' && !BUTTON_TYPES.has(el.type)
}

function numberValue(el: HTMLInputElement) {
  return el.value === '' ? null : Number(el.value)
}

/** Readers by control `type`; anything not listed submits its string value. */
const READERS: Record<string, (el: HTMLInputElement) => unknown> = {
  checkbox: (el) => el.checked,
  number: numberValue,
  range: numberValue,
  'select-multiple': (el) => Array.from((el as unknown as HTMLSelectElement).selectedOptions).map((o) => o.value),
}

/** A checked radio wins; an unchecked group still reports its name as null. */
function collectRadio(values: FormValues, el: HTMLInputElement) {
  if (el.checked) values[el.name] = el.value
  else if (!(el.name in values)) values[el.name] = null
}

/** Reads every named control: checkboxes become booleans, number inputs numbers, multi-selects arrays. */
function collect(form: HTMLFormElement, submitter: HTMLElement | null): FormValues {
  const values: FormValues = {}

  for (const element of Array.from(form.elements)) {
    const el = element as HTMLInputElement

    if (!isCollected(el)) continue

    if (el.type === 'radio') collectRadio(values, el)
    else values[el.name] = READERS[el.type] ? READERS[el.type](el) : el.value
  }

  const button = submitter as HTMLButtonElement | null

  if (button?.name) values[button.name] = button.value

  return values
}

type FormProps = {
  onSubmit?: (values: FormValues, event: FormEvent<HTMLFormElement>) => void
  gap?: number | string
  className?: string
  style?: CSSProperties
  children?: ReactNode
}

export function Form({ onSubmit, gap = 16, className, style, children }: FormProps) {
  const { submit } = useCanvas()

  const handleSubmit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    const native = event.nativeEvent as SubmitEvent
    const values = collect(event.currentTarget, native.submitter ?? null)

    if (onSubmit) onSubmit(values, event)
    else submit(values)
  }

  return (
    <FormContext.Provider value={true}>
      <form className={cx('cv-form', className)} style={{ gap: px(gap), ...style }} onSubmit={handleSubmit}>
        {children}
      </form>
    </FormContext.Provider>
  )
}
