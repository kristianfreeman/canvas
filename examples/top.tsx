import { memo, useCallback, useMemo, useState, type ReactNode } from 'react'
import { Badge, Card, Grid, Heading, Progress, Row, Sparkline, Stack, Table, Text, publish, useSeries, type TableColumn } from 'canvas'

/**
 * A system monitor over the native sampler's canvas.sys.* channels:
 *   canvas show examples/top.tsx --id top --width 820
 * Clicking a process publishes {pid, name, cpu, mem} on top.select:
 *   canvas sub top.select
 */

type Cpu = { total: number; cores: number[] }
type Memory = { total: number; used: number; app: number; wired: number; compressed: number; swapUsed: number }
type Net = { rx: number; tx: number; rxTotal: number; txTotal: number }
type Disk = { read: number; write: number; used: number; total: number }
type Proc = { pid: number; name: string; cpu: number; mem: number }
type Battery = { percent: number; charging: boolean; source: string } | null
type Thermal = { state: 'nominal' | 'fair' | 'serious' | 'critical' }
type SortKey = 'name' | 'pid' | 'cpu' | 'mem'
type Sort = { key: SortKey; descending: boolean }
type LegendEntry = { label: string; value: string; color: string }
type Placeholder = { id: number; width: number }

const HISTORY = 60
const DASH = '—'
const UNITS = ['B', 'KB', 'MB', 'GB', 'TB']
const PLACEHOLDER_CORES: unknown[] = Array.from({ length: 8 })
const PLACEHOLDER_ROWS: Placeholder[] = [220, 190, 160, 130, 100, 70].map((width) => ({ id: width, width }))
const THERMAL_COLOR: Record<string, string> = { nominal: 'success', fair: 'yellow', serious: 'orange', critical: 'danger' }

const COLUMNS: { key: SortKey; label: string; align: 'left' | 'right'; width?: number }[] = [
  { key: 'name', label: 'Process', align: 'left' },
  { key: 'pid', label: 'PID', align: 'right', width: 72 },
  { key: 'cpu', label: 'CPU', align: 'right', width: 132 },
  { key: 'mem', label: 'Memory', align: 'right', width: 96 },
]

const MEMORY_PARTS = [
  { label: 'App', key: 'app', color: 'accent' },
  { label: 'Wired', key: 'wired', color: 'orange' },
  { label: 'Compressed', key: 'compressed', color: 'purple' },
] as const

const finite = (value: unknown): value is number => typeof value === 'number' && Number.isFinite(value)

const ratio = (part: unknown, whole: unknown) => (finite(part) && finite(whole) && whole > 0 ? part / whole : undefined)

function bytes(value: number | undefined) {
  if (!finite(value)) return DASH
  let size = Math.max(0, value)
  let unit = 0

  while (size >= 1024 && unit < UNITS.length - 1) {
    size /= 1024
    unit++
  }

  return `${size < 100 && unit > 0 ? size.toFixed(1) : Math.round(size)} ${UNITS[unit]}`
}

const rate = (value: number | undefined) => (finite(value) ? `${bytes(value)}/s` : DASH)

const percent = (value: number | undefined, digits = 0) => (finite(value) ? `${(value * 100).toFixed(digits)}%` : DASH)

function loadColor(load: number) {
  if (load >= 0.85) return 'danger'

  return load >= 0.6 ? 'warning' : 'accent'
}

/** The channel's recent values, oldest first, and the latest one. */
function useSys<T>(channel: string) {
  const series = useSeries<T>(`canvas.sys.${channel}`, HISTORY)

  return { series, latest: series.at(-1) }
}

function useNumbers<T>(series: T[], pick: (value: T) => unknown) {
  return useMemo(() => series.map(pick).filter(finite), [series, pick])
}

const pickTotal = (cpu: Cpu) => cpu?.total
const pickRx = (net: Net) => net?.rx
const pickTx = (net: Net) => net?.tx
const pickUsed = (memory: Memory) => ratio(memory?.used, memory?.total)

const Num = ({ children }: { children: ReactNode }) => <Text size="sm" mono>{children}</Text>

const Label = ({ children }: { children: ReactNode }) => <Text size="sm" muted>{children}</Text>

/** An empty track until there's a value. */
function Meter({ value, flex }: { value: number | undefined; flex?: boolean }) {
  return <Progress value={value ?? 0} color={value === undefined ? undefined : loadColor(value)} style={flex ? { flex: 1 } : undefined} />
}

/** `load` is a whole percent, so a core whose rounded load didn't change skips re-rendering. */
const CoreMeter = memo(function CoreMeter({ id, load }: { id: number; load?: number }) {
  return (
    <Row gap={10}>
      <Text size="sm" muted style={{ width: 18 }}>{id}</Text>
      <Meter value={load === undefined ? undefined : load / 100} flex />
      <Row justify="end" style={{ width: 36 }}>
        <Num>{load === undefined ? DASH : `${load}%`}</Num>
      </Row>
    </Row>
  )
})

function CpuCard() {
  const { series, latest } = useSys<Cpu>('cpu')
  const totals = useNumbers(series, pickTotal)
  const loads = Array.isArray(latest?.cores) ? latest.cores : PLACEHOLDER_CORES
  const cores = loads.map((load, index) => ({ id: index + 1, load: finite(load) ? Math.round(load * 100) : undefined }))

  return (
    <Card title="CPU" subtitle={latest ? `${cores.length} cores` : 'Waiting for the sampler'} actions={<Heading level={1}>{percent(latest?.total)}</Heading>}>
      <Stack gap={18}>
        <Sparkline data={totals} width="100%" height={52} color="accent" />
        <Grid columns={4} gap={14}>
          {cores.map((core) => (
            <CoreMeter key={core.id} id={core.id} load={core.load} />
          ))}
        </Grid>
      </Stack>
    </Card>
  )
}

function Legend({ items }: { items: LegendEntry[] }) {
  return (
    <Grid columns="auto 1fr auto" gap={8}>
      {items.flatMap(({ label, value, color }) => [
        <Text key={`${label}-swatch`} size="sm" color={color}>●</Text>,
        <Label key={`${label}-label`}>{label}</Label>,
        <Num key={`${label}-value`}>{value}</Num>,
      ])}
    </Grid>
  )
}

/** One bar split into parts, as grid tracks in thousandths so the shares stay plain `fr` sizes. */
function SplitBar({ parts }: { parts: { label: string; color: string; share: number }[] }) {
  const shown = parts.filter((part) => part.share > 0)
  const used = shown.reduce((sum, part) => sum + part.share, 0)
  const tracks = [...shown.map((part) => part.share), Math.max(0, 1 - used)].map((share) => `${Math.round(share * 1000)}fr`)

  return (
    <Grid columns={tracks.join(' ')} gap={2}>
      {shown.map((part) => (
        <Progress key={part.label} value={1} color={part.color} />
      ))}
      <Progress value={0} />
    </Grid>
  )
}

function MemoryCard() {
  const { series, latest } = useSys<Memory>('memory')
  const used = useNumbers(series, pickUsed)
  const parts = MEMORY_PARTS.map(({ label, key, color }) => ({ label, color, value: bytes(latest?.[key]), share: ratio(latest?.[key], latest?.total) ?? 0 }))

  return (
    <Card title="Memory" subtitle={`${bytes(latest?.used)} of ${bytes(latest?.total)}`} actions={<Heading level={1}>{percent(used.at(-1))}</Heading>}>
      <Stack gap={14}>
        <Sparkline data={used} width="100%" height={40} color="purple" />
        <SplitBar parts={parts} />
        <Legend items={[...parts, { label: 'Swap', value: bytes(latest?.swapUsed), color: 'gray' }]} />
      </Stack>
    </Card>
  )
}

function Throughput({ label, value, data, color }: { label: string; value: string; data: number[]; color: string }) {
  return (
    <Stack gap={6}>
      <Row justify="between">
        <Label>{label}</Label>
        <Num>{value}</Num>
      </Row>
      <Sparkline data={data} width="100%" height={30} color={color} />
    </Stack>
  )
}

function NetworkCard() {
  const { series, latest } = useSys<Net>('net')
  const rx = useNumbers(series, pickRx)
  const tx = useNumbers(series, pickTx)

  return (
    <Card title="Network" subtitle={`${bytes(latest?.rxTotal)} in · ${bytes(latest?.txTotal)} out`}>
      <Stack gap={14}>
        <Throughput label="Received" value={rate(latest?.rx)} data={rx} color="teal" />
        <Throughput label="Sent" value={rate(latest?.tx)} data={tx} color="pink" />
      </Stack>
    </Card>
  )
}

function DiskCard() {
  const { latest } = useSys<Disk>('disk')
  const read = { label: 'Read', value: rate(latest?.read), color: 'blue' }
  const write = { label: 'Write', value: rate(latest?.write), color: 'orange' }

  return (
    <Card title="Disk" subtitle={`${bytes(latest?.used)} of ${bytes(latest?.total)} used`}>
      <Stack gap={14}>
        <Meter value={ratio(latest?.used, latest?.total)} />
        <Legend items={[read, write]} />
      </Stack>
    </Card>
  )
}

function PowerBadge({ battery }: { battery: Battery | undefined }) {
  if (!battery || !finite(battery.percent)) return null
  const state = battery.charging ? 'charging' : battery.source

  return (
    <Badge color={battery.percent < 20 && !battery.charging ? 'danger' : 'muted'}>
      {`${Math.round(battery.percent)}%${state ? ` · ${state}` : ''}`}
    </Badge>
  )
}

function StatusBadges() {
  const { latest: thermal } = useSys<Thermal>('thermal')
  const { latest: battery } = useSys<Battery>('battery')
  const state = thermal?.state && Object.hasOwn(THERMAL_COLOR, thermal.state) ? thermal.state : undefined

  return (
    <Row gap={8}>
      <PowerBadge battery={battery} />
      <Badge color={state ? THERMAL_COLOR[state] : 'muted'} dot>
        {`Thermal ${state ?? DASH}`}
      </Badge>
    </Row>
  )
}

function compareProcs({ key, descending }: Sort) {
  const direction = descending ? -1 : 1

  return (a: Proc, b: Proc) => (key === 'name' ? a.name.localeCompare(b.name) : a[key] - b[key]) * direction || a.pid - b.pid
}

const isProc = (p: Proc) => p && finite(p.pid) && typeof p.name === 'string' && finite(p.cpu) && finite(p.mem)

/** Well-formed processes, keyed by pid so the table's selection follows a process as it moves. */
function validProcs(value: unknown) {
  if (!Array.isArray(value)) return []

  return value.filter(isProc).map(({ pid, name, cpu, mem }: Proc) => ({ id: pid, pid, name, cpu, mem }))
}

/** The meter is full at one core. */
function CpuCell({ cpu }: { cpu: number }) {
  return (
    <Row gap={10} justify="end">
      <Progress value={Math.min(1, cpu)} style={{ width: 44 }} />
      <Num>{percent(cpu, 1)}</Num>
    </Row>
  )
}

function procColumns(selected: number | undefined): TableColumn<Proc>[] {
  const cells: Record<SortKey, (p: Proc) => ReactNode> = {
    name: (p) => <Text weight={p.pid === selected ? 'semibold' : 'medium'}>{p.name}</Text>,
    pid: (p) => <Num>{p.pid}</Num>,
    cpu: (p) => <CpuCell cpu={p.cpu} />,
    mem: (p) => <Num>{bytes(p.mem)}</Num>,
  }

  return COLUMNS.map((column) => ({ ...column, render: cells[column.key] }))
}

/** Skeleton rows: empty tracks, the name column's narrowing down the table. */
const PLACEHOLDER_COLUMNS: TableColumn<Placeholder>[] = COLUMNS.map((column) => ({
  ...column,
  render: (row) => <Progress value={0} style={column.key === 'name' ? { maxWidth: row.width } : undefined} />,
}))

const isSortKey = (key: string): key is SortKey => COLUMNS.some((column) => column.key === key)

function ProcessCard() {
  const { latest } = useSys<Proc[]>('procs')
  const [sort, setSort] = useState<Sort>({ key: 'cpu', descending: true })
  const [selected, setSelected] = useState<number>()
  const procs = useMemo(() => validProcs(latest).toSorted(compareProcs(sort)), [latest, sort])
  const columns = useMemo(() => procColumns(selected), [selected])

  const onSort = useCallback((key: string) => {
    if (isSortKey(key)) setSort((prev) => ({ key, descending: prev.key === key ? !prev.descending : key !== 'name' }))
  }, [])

  const onSelect = useCallback(({ pid, name, cpu, mem }: Proc) => {
    setSelected(pid)
    publish('top.select', { pid, name, cpu, mem })
  }, [])

  return (
    <Card title="Processes" subtitle={procs.length ? `Top ${procs.length} by CPU` : 'Waiting for the sampler'}>
      {procs.length === 0 ? (
        <Table columns={PLACEHOLDER_COLUMNS} rows={PLACEHOLDER_ROWS} sort={sort} onSort={onSort} />
      ) : (
        <Table columns={columns} rows={procs} sort={sort} onSort={onSort} onRowClick={onSelect} selected={selected} />
      )}
    </Card>
  )
}

export default function Top() {
  return (
    <Stack gap={14}>
      <Row justify="between">
        <Text size="sm" muted>Sampled every second</Text>
        <StatusBadges />
      </Row>
      <CpuCard />
      <Grid columns={3} gap={14}>
        <MemoryCard />
        <NetworkCard />
        <DiskCard />
      </Grid>
      <ProcessCard />
    </Stack>
  )
}
