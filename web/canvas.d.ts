/**
 * Types for the `canvas` module available to TSX files shown with `canvas show file.tsx`.
 *
 *   import { Card, Stat, useCanvas } from 'canvas'
 *   export default function App({ data }) { ... }
 *
 * Only `react` and `canvas` can be imported. The default export is rendered with props `{ data }`.
 */
declare module 'canvas' {
  import type {
    ButtonHTMLAttributes,
    CSSProperties,
    FormEvent,
    InputHTMLAttributes,
    ReactElement,
    ReactNode,
    SelectHTMLAttributes,
    TextareaHTMLAttributes,
  } from 'react'

  /** An Apple system color, resolved for the current theme (light or dark). */
  export type HueColor = 'red' | 'orange' | 'yellow' | 'green' | 'teal' | 'blue' | 'purple' | 'pink' | 'gray'

  /** `accent` is the macOS accent color or `--accent`; `warning` is orange in light mode and yellow in dark. */
  export type SemanticColor = 'accent' | 'success' | 'warning' | 'danger' | 'info' | 'muted'

  /** A semantic name, a hue name, or any CSS color. */
  export type Color = SemanticColor | HueColor | (string & {})

  type Styled = { className?: string; style?: CSSProperties }

  type Align = 'start' | 'center' | 'end' | 'stretch' | 'baseline'

  type Justify = 'start' | 'center' | 'end' | 'between' | 'around' | 'evenly'

  // ---------- Hook ----------

  export interface CanvasApi {
    /** Sends a JSON value back to the `canvas show --wait` caller, which prints it and closes the panel. */
    submit(value: unknown): void
    /** Closes the panel without a result (`--wait` exits 2). */
    close(): void
    /** Same as the `publish` export. */
    publish(channel: string, value: unknown): void
    /** The parsed `--data` value. `canvas update` and `--stream` replace it without remounting. */
    data: unknown
    /** True when the caller is blocking on `--wait`. */
    wait: boolean
  }

  export function useCanvas(): CanvasApi

  // ---------- Channels ----------

  /**
   * The latest value on a channel (`canvas pub`, another page, or `canvas.sys.*`), or undefined until one arrives.
   * Re-renders only when this channel changes. `every` (ms) asks the sampler for `canvas.sys.*` channels to run
   * at least that often; it defaults to 1000 and the floor is 100.
   */
  export function useChannel<T = unknown>(name: string, options?: { every?: number }): T | undefined

  /** Up to `size` recent values on a channel, oldest first. `size` defaults to 120. */
  export function useSeries<T = unknown>(name: string, size?: number): T[]

  /**
   * Publishes a JSON value to a channel. Names starting with `canvas.` are reserved and rejected. `persist` keeps
   * the channel's latest value across server restarts, as `canvas pub --persist` does.
   */
  export function publish(channel: string, value: unknown, options?: { persist?: boolean }): void

  /**
   * Like `useState`, but the value lives in the persisted channel `name`: it survives closing the panel and
   * restarting the server, other panels on the channel see it, and `canvas get` and `canvas pub` read and change
   * it. `initial` is used until the channel has a value.
   */
  export function useStore<T>(name: string, initial: T): [T, (next: T | ((previous: T) => T)) => void]

  // ---------- Layout ----------

  /** Vertical flex column. `gap` defaults to 12 (px when a number). */
  export function Stack(props: Styled & { gap?: number | string; align?: Align; children?: ReactNode }): ReactElement

  /** Horizontal flex row. `align` defaults to `center`. */
  export function Row(props: Styled & {
    gap?: number | string
    align?: Align
    justify?: Justify
    wrap?: boolean
    children?: ReactNode
  }): ReactElement

  /** CSS grid. A number of `columns` means equal columns; a string is a raw `grid-template-columns`. */
  export function Grid(props: Styled & { columns?: number | string; gap?: number | string; children?: ReactNode }): ReactElement

  export function Divider(props: Styled): ReactElement

  /** Flexible space (`flex: 1`), or a fixed gap when `size` is given. */
  export function Spacer(props: Styled & { size?: number | string }): ReactElement

  // ---------- Text ----------

  export function Heading(props: Styled & { level?: 1 | 2 | 3 | 4; children?: ReactNode }): ReactElement

  export function Text(props: Styled & {
    size?: 'sm' | 'md' | 'lg'
    muted?: boolean
    weight?: number | 'normal' | 'medium' | 'semibold' | 'bold'
    color?: Color
    mono?: boolean
    children?: ReactNode
  }): ReactElement

  /** Inline code. */
  export function Code(props: Styled & { children?: ReactNode }): ReactElement

  /** A Shiki-highlighted block. Pass `code` or a string child. */
  export function CodeBlock(props: Styled & { code?: string; lang?: string; children?: string }): ReactElement

  /** Renders a Markdown string with the same pipeline as `.md` files. */
  export function Markdown(
    props: Styled & {
      source?: string
      children?: string
      /** Makes task checkboxes clickable. `line` is the item's source line, counting from 0. */
      onToggle?: (task: { line: number; checked: boolean }) => void
    },
  ): ReactElement

  /** A key chip. `tone="accent"` tints it with the accent color. */
  export function Kbd(props: Styled & { tone?: 'accent'; children?: ReactNode }): ReactElement

  /**
   * A row of key chips for one shortcut, like `"Hyper W → 1–7"` or `"Caps Lock tap"`. A string is split on spaces,
   * keeping `Caps Lock`, `Page Up`, `Page Down` and `Num Lock` together; an array is taken as the keys. `Hyper` is an
   * accent ✦ chip, `tap`, `hold`, `twice`, `double`, `then`, `or` and `again` are quiet words, and `+` and a `→`
   * between two non-arrow keys are quiet separators. Everything else is a `Kbd`.
   */
  export function KeyChips(props: Styled & { keys: string | string[] }): ReactElement

  // ---------- Data ----------

  export function Card(props: Styled & {
    title?: ReactNode
    subtitle?: ReactNode
    actions?: ReactNode
    /** Defaults to 16. */
    padding?: number | string
    children?: ReactNode
  }): ReactElement

  export type TableRow = Record<string, any>
  export type TableColumn<R extends TableRow = TableRow> =
    | string
    | {
        key: string
        label?: ReactNode
        align?: 'left' | 'center' | 'right'
        width?: number | string
        render?: (row: R, index: number) => ReactNode
      }

  /**
   * Pass `columns` + `rows`, or `<thead>`/`<tbody>` children (WebKit only). A row's key is its `id`, or its index.
   * Sorting is up to you: `sort` marks the sorted column and `onSort` reports header clicks; `rows` is shown as given.
   */
  export function Table<R extends TableRow = TableRow>(props: Styled & {
    columns?: TableColumn<R>[]
    rows?: R[]
    /** The sorted column's key and direction; its header shows ↓ or ↑. */
    sort?: { key: string; descending?: boolean }
    /** Makes the headers clickable; called with the column key. */
    onSort?: (key: string) => void
    /** Makes the rows clickable. */
    onRowClick?: (row: R, index: number) => void
    /** The key (`id` or index) of the highlighted row. */
    selected?: string | number
    children?: ReactNode
  }): ReactElement

  /**
   * A big number. A positive `delta` is green and a negative one red; set `invertDelta`
   * when lower is better (latency, errors). Strings starting with + or - are colored too.
   */
  export function Stat(props: Styled & {
    label: ReactNode
    value: ReactNode
    delta?: number | string
    invertDelta?: boolean
    hint?: ReactNode
    /** Tints the value. */
    color?: Color
    children?: ReactNode
  }): ReactElement

  export function Badge(props: Styled & { color?: Color; dot?: boolean; children?: ReactNode }): ReactElement

  /** `value` is 0..1, or 0..max when `max` is given. */
  export function Progress(props: Styled & {
    value: number
    max?: number
    color?: Color
    label?: ReactNode
    showValue?: boolean
  }): ReactElement

  export function BarChart(props: Styled & {
    data: { label: ReactNode; value: number; color?: Color }[]
    /** Total height in px, labels included. Defaults to 160. */
    height?: number
    color?: Color
    max?: number
    format?: (value: number) => ReactNode
  }): ReactElement

  export function Sparkline(props: Styled & {
    data: number[]
    /** px, or `'100%'` to fill the container. Other CSS widths need the WebKit renderer. Defaults to 120. */
    width?: number | string
    height?: number
    color?: Color
    fill?: boolean
  }): ReactElement

  // ---------- Input ----------

  /**
   * Inside a `Form`, a Button without `onClick` is a submit button and its `name`/`value`
   * are included in the submitted object. Outside a Form, a Button with `value` and no
   * `onClick` calls `submit(value)`.
   */
  export function Button(props: Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'value'> & {
    variant?: 'primary' | 'secondary' | 'ghost' | 'danger'
    value?: unknown
  }): ReactElement

  export function Input(props: Omit<InputHTMLAttributes<HTMLInputElement>, 'size'> & {
    label?: ReactNode
    hint?: ReactNode
  }): ReactElement

  export function TextArea(props: TextareaHTMLAttributes<HTMLTextAreaElement> & {
    label?: ReactNode
    hint?: ReactNode
  }): ReactElement

  export function Select(props: SelectHTMLAttributes<HTMLSelectElement> & {
    label?: ReactNode
    hint?: ReactNode
    options?: (string | { value: string; label?: ReactNode; disabled?: boolean })[]
  }): ReactElement

  export function Checkbox(props: Omit<InputHTMLAttributes<HTMLInputElement>, 'type'> & {
    label?: ReactNode
    hint?: ReactNode
  }): ReactElement

  export type FormValues = Record<string, unknown>

  /**
   * Collects named fields into one object (checkboxes as booleans, number inputs as numbers,
   * plus the submitting button's name/value) and calls `submit(values)`, or `onSubmit` if given.
   * Cmd+Enter submits through the first enabled `variant="primary"` submit button.
   */
  export function Form(props: Styled & {
    onSubmit?: (values: FormValues, event: FormEvent<HTMLFormElement>) => void
    gap?: number | string
    children?: ReactNode
  }): ReactElement
}
