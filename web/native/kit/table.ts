import { isValidElement, type ReactNode } from 'react'
import type { TableColumn, TableRow } from 'canvas'
import { size } from '../fallback'
import { h, slot, styleOf } from './host'
import type { PropsOf } from './props'

type Column = Exclude<TableColumn, string>

function isRenderable(value: unknown): value is ReactNode {
  return isValidElement(value) || typeof value === 'string' || typeof value === 'number'
}

/** A row value as the web table shows it. */
function cell(value: unknown): ReactNode {
  if (value === null || value === undefined) return ''

  if (isRenderable(value)) return value

  if (typeof value === 'boolean') return value ? 'Yes' : 'No'

  if (Array.isArray(value)) return value.map((v) => (isValidElement(v) ? v : String(v)))

  return JSON.stringify(value)
}

type Sort = PropsOf<'Table'>['sort']

type RowClick<R extends TableRow> = ((row: R, index: number) => void) | undefined

type Body<R extends TableRow> = { cols: Column[]; selected: string | undefined; onRowClick: RowClick<R> }

function bodyRow<R extends TableRow>({ cols, selected, onRowClick }: Body<R>, row: R, index: number) {
  const key = String((row.id as string | number | undefined) ?? index)

  return h(
    'TableRow',
    { key, hostKey: key, selected: key === selected || undefined, onClick: onRowClick && (() => onRowClick(row, index)) },
    cols.map((c) => h('TableCell', { key: c.key, align: c.align }, c.render ? c.render(row, index) : cell(row[c.key]))),
  )
}

function direction(sort: Sort, key: string) {
  if (sort?.key !== key) return undefined

  return sort.descending ? 'descending' : 'ascending'
}

function headCell(c: Column, sort: Sort, onSort: ((key: string) => void) | undefined) {
  return h('TableCell', { key: c.key, align: c.align, sort: direction(sort, c.key), onClick: onSort && (() => onSort(c.key)) }, c.label)
}

type TableProps<R extends TableRow> = Omit<PropsOf<'Table'>, 'columns' | 'rows' | 'onRowClick'> & {
  columns?: TableColumn<R>[]
  rows?: R[]
  onRowClick?: RowClick<R>
}

export function Table<R extends TableRow = TableRow>({ columns, rows, sort, onSort, onRowClick, selected, children, ...rest }: TableProps<R>) {
  const style = styleOf(rest)

  if (!columns) return h('Table', { columns: [], style }, children)
  const cols = columns.map((c) => (typeof c === 'string' ? { key: c, label: c } : { label: c.key, ...c })) as Column[]
  const wire = cols.map((c) => ({ key: c.key, align: c.align, width: size(c.width, `column ${c.key} width`) }))
  const body: Body<R> = { cols, selected: selected === undefined ? undefined : String(selected), onRowClick }

  return h(
    'Table',
    { columns: wire, style },
    slot('head', cols.map((c) => headCell(c, sort, onSort))),
    rows?.map((row, index) => bodyRow(body, row, index)),
  )
}
