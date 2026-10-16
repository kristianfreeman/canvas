import { isValidElement, type ReactNode } from 'react'
import { cx, px, type Styled } from './util'

type Row = Record<string, any>

type Column<R extends Row> = string | {
  key: string
  label?: ReactNode
  align?: 'left' | 'center' | 'right'
  width?: number | string
  render?: (row: R, index: number) => ReactNode
}

type Resolved<R extends Row> = Exclude<Column<R>, string>

type Sort = { key: string; descending?: boolean }

type TableProps<R extends Row> = Styled & {
  columns?: Column<R>[]
  rows?: R[]
  sort?: Sort
  onSort?: (key: string) => void
  onRowClick?: (row: R, index: number) => void
  selected?: string | number
  children?: ReactNode
}

function isRenderable(value: unknown): value is ReactNode {
  return isValidElement(value) || typeof value === 'string' || typeof value === 'number'
}

function cell(value: unknown): ReactNode {
  if (value === null || value === undefined) return ''

  if (isRenderable(value)) return value

  if (typeof value === 'boolean') return value ? 'Yes' : 'No'

  if (Array.isArray(value)) return value.map((v) => (isValidElement(v) ? v : String(v)))

  return JSON.stringify(value)
}

function direction(sort: Sort | undefined, key: string) {
  if (sort?.key !== key) return undefined

  return sort.descending ? 'descending' : 'ascending'
}

type HeadProps = { column: Resolved<Row>; sort?: Sort; onSort?: (key: string) => void }

/** With `sort`, every header holds an arrow, hidden on the unsorted ones, so headers keep their width when it moves. */
function HeadCell({ column, sort, onSort }: HeadProps) {
  const sorted = direction(sort, column.key)

  const label = (
    <>
      {column.label}
      {sort && (
        <span className="cv-table-arrow" style={{ visibility: sorted ? 'visible' : 'hidden' }}>
          {sort.descending ? '↓' : '↑'}
        </span>
      )}
    </>
  )

  return (
    <th style={{ textAlign: column.align, width: px(column.width) }} aria-sort={onSort ? (sorted ?? 'none') : sorted}>
      {onSort ? (
        <button type="button" className={cx('cv-table-sort', sorted && 'is-active')} onClick={() => onSort(column.key)}>
          {label}
        </button>
      ) : (
        label
      )}
    </th>
  )
}

type BodyProps<R extends Row> = {
  columns: Resolved<R>[]
  row: R
  index: number
  selected: boolean
  onRowClick?: (row: R, index: number) => void
}

function BodyRow<R extends Row>({ columns, row, index, selected, onRowClick }: BodyProps<R>) {
  return (
    <tr
      className={onRowClick ? 'is-clickable' : undefined}
      aria-selected={selected || undefined}
      onClick={onRowClick && (() => onRowClick(row, index))}
    >
      {columns.map((c) => (
        <td key={c.key} style={{ textAlign: c.align }}>
          {c.render ? c.render(row, index) : cell(row[c.key])}
        </td>
      ))}
    </tr>
  )
}

const rowKey = (row: Row, index: number) => String((row.id as string | number | undefined) ?? index)

export function Table<R extends Row = Row>({ columns, rows, sort, onSort, onRowClick, selected, className, style, children }: TableProps<R>) {
  if (!columns) {
    return (
      <div className={cx('cv-table-wrap', className)} style={style}>
        <table className="cv-table">{children}</table>
      </div>
    )
  }

  const cols = columns.map((c): Resolved<R> => (typeof c === 'string' ? { key: c, label: c } : { label: c.key, ...c }))
  const current = selected === undefined ? undefined : String(selected)

  return (
    <div className={cx('cv-table-wrap', className)} style={style}>
      <table className="cv-table">
        <thead>
          <tr>
            {cols.map((c) => (
              <HeadCell key={c.key} column={c as Resolved<Row>} sort={sort} onSort={onSort} />
            ))}
          </tr>
        </thead>
        <tbody>
          {rows?.map((row, i) => (
            <BodyRow key={rowKey(row, i)} columns={cols} row={row} index={i} selected={rowKey(row, i) === current} onRowClick={onRowClick} />
          ))}
        </tbody>
      </table>
    </div>
  )
}
