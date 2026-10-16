import { Badge, BarChart, Card, Grid, Progress, Row, Sparkline, Stack, Stat, Table, Text } from 'canvas'

const stats = [
  { label: 'Deploys, 7 days', value: '48', delta: '+12%', trend: [4, 6, 5, 7, 6, 9, 11], color: 'accent' },
  { label: 'Success rate', value: '97.9%', delta: '+1.4%', trend: [94, 95, 93, 96, 97, 96, 98], color: 'green' },
  { label: 'p95 build time', value: '6m 12s', delta: '-38s', invert: true, trend: [8.1, 7.6, 7.9, 7.2, 6.8, 6.5, 6.2], color: 'teal' },
  { label: 'Open incidents', value: '1', delta: '-2', invert: true, trend: [3, 3, 4, 2, 2, 1, 1], color: 'orange' },
]

const builds = [
  { label: 'Mon', value: 38 },
  { label: 'Tue', value: 52 },
  { label: 'Wed', value: 47 },
  { label: 'Thu', value: 61 },
  { label: 'Fri', value: 44 },
  { label: 'Sat', value: 12 },
  { label: 'Sun', value: 9 },
]

const budgets = [
  { service: 'api-gateway', remaining: 0.72, color: 'green' },
  { service: 'web', remaining: 0.91, color: 'green' },
  { service: 'billing-worker', remaining: 0.34, color: 'warning' },
  { service: 'search', remaining: 0.12, color: 'danger' },
]

type Deploy = {
  service: string
  version: string
  author: string
  duration: string
  when: string
  status: 'live' | 'rolling' | 'failed' | 'rolled back'
}

const deploys: Deploy[] = [
  { service: 'api-gateway', version: 'v2.14.0', author: 'kristian', duration: '5m 48s', when: '12m ago', status: 'rolling' },
  { service: 'web', version: 'v8.3.1', author: 'maya', duration: '4m 02s', when: '1h ago', status: 'live' },
  { service: 'billing-worker', version: 'v1.9.4', author: 'sam', duration: '7m 31s', when: '3h ago', status: 'failed' },
  { service: 'search', version: 'v3.0.0', author: 'jordan', duration: '9m 10s', when: '5h ago', status: 'rolled back' },
  { service: 'web', version: 'v8.3.0', author: 'maya', duration: '3m 57s', when: 'yesterday', status: 'live' },
]

const STATUS_COLOR: Record<Deploy['status'], string> = {
  live: 'success',
  rolling: 'info',
  failed: 'danger',
  'rolled back': 'warning',
}

export default function Dashboard() {
  return (
    <Stack gap={14}>
      <Grid columns={4} gap={12}>
        {stats.map((s) => (
          <Card key={s.label} padding={14}>
            <Stack gap={10}>
              <Stat label={s.label} value={s.value} delta={s.delta} invertDelta={s.invert} />
              <Sparkline data={s.trend} width="100%" height={28} color={s.color} />
            </Stack>
          </Card>
        ))}
      </Grid>

      <Grid columns="1.55fr 1fr" gap={12}>
        <Card title="Builds per day" subtitle="All pipelines, this week">
          <BarChart data={builds} height={150} />
        </Card>
        <Card title="Error budget" subtitle="30-day window, remaining">
          <Stack gap={13}>
            {budgets.map((b) => (
              <Progress key={b.service} label={b.service} value={b.remaining} color={b.color} showValue />
            ))}
          </Stack>
        </Card>
      </Grid>

      <Card title="Recent deploys" actions={<Text size="sm" muted>production</Text>}>
        <Table<Deploy>
          columns={[
            { key: 'service', label: 'Service', render: (d) => <Text weight="medium">{d.service}</Text> },
            { key: 'version', label: 'Version', render: (d) => <Text mono muted>{d.version}</Text> },
            { key: 'author', label: 'Author' },
            { key: 'duration', label: 'Duration', align: 'right' },
            { key: 'when', label: 'When', align: 'right', render: (d) => <Text muted>{d.when}</Text> },
            {
              key: 'status',
              label: 'Status',
              align: 'right',
              render: (d) => (
                <Badge color={STATUS_COLOR[d.status]} dot>
                  {d.status}
                </Badge>
              ),
            },
          ]}
          rows={deploys}
        />
      </Card>

      <Row justify="between">
        <Text size="sm" muted>Updated just now</Text>
        <Text size="sm" muted>Data is illustrative</Text>
      </Row>
    </Stack>
  )
}
