import { Badge, Button, Card, Code, CodeBlock, Grid, Row, Spacer, Sparkline, Stack, Stat, Text, useCanvas } from 'canvas'

type Check = { name: string; ok: boolean; note?: string }

type Release = {
  title: string
  commit: string
  summary: string
  tests: { passed: number; total: number }
  mutants: { killed: number; total: number }
  openMs: number[]
  memoryMb: { before: number; after: number }
  checks: Check[]
  file: string
  diff: string
}

/** Today's numbers from this repo: open times are the server traces of each change, oldest first. */
const example: Release = {
  title: 'Ship instant reopen to Canvas.app',
  commit: 'b50792c',
  summary: 'Closed panels rest hidden and come back without rendering',
  tests: { passed: 459, total: 459 },
  mutants: { killed: 24, total: 24 },
  openMs: [315, 65, 52, 45, 24.6, 1.2],
  memoryMb: { before: 128, after: 46 },
  checks: [
    { name: 'Swift tests', ok: true },
    { name: 'bun tests', ok: true },
    { name: 'Lint', ok: true },
    { name: 'gitleaks', ok: true },
    { name: 'Mutations', ok: true },
    { name: 'On-screen suite', ok: true },
    { name: 'Notarized', ok: false, note: 'pending' },
  ],
  file: 'Sources/CanvasApp/Server+Panels.swift',
  diff: [
    '@@ func show(_ json: [String: Any], command: WireCommand, _ client: Client)',
    '         if let existing = panels[request.id] {',
    '             existing.replace(with: request, caller: client)',
    '             return',
    '         }',
    '-        open(request, record: record, client)',
    '+        if !reopenResting(request, record: record, client) {',
    '+            open(request, record: record, client)',
    '+        }',
  ].join('\n'),
}

function Header({ release }: { release: Release }) {
  return (
    <Stack gap={6}>
      <Row gap={8}>
        <Badge color="warning" dot>
          Needs approval
        </Badge>
        <Badge color="muted">main</Badge>
      </Row>
      <Text size="lg" weight="semibold">
        {release.title}
      </Text>
      <Text muted>
        <Code>{release.commit}</Code> {release.summary}
      </Text>
    </Stack>
  )
}

function Numbers({ release }: { release: Release }) {
  const first = release.openMs[0] ?? 0
  const last = release.openMs[release.openMs.length - 1] ?? 0

  return (
    <Grid columns={3} gap={12}>
      <Card>
        <Stat
          label="Open time"
          value={`${last} ms`}
          delta={`-${Math.round(first - last)} ms`}
          invertDelta
          hint={`was ${first} ms`}
        />
        <Sparkline data={release.openMs} width="100%" height={28} fill />
      </Card>
      <Card>
        <Stat
          label="Idle memory"
          value={`${release.memoryMb.after} MB`}
          delta={`-${release.memoryMb.before - release.memoryMb.after} MB`}
          invertDelta
          hint={`was ${release.memoryMb.before} MB`}
        />
      </Card>
      <Card>
        <Stat
          label="Tests"
          value={`${release.tests.passed}/${release.tests.total}`}
          color="success"
          hint={`${release.mutants.killed}/${release.mutants.total} mutants killed`}
        />
      </Card>
    </Grid>
  )
}

function Answer() {
  const { wait } = useCanvas()

  return (
    <Row gap={8}>
      <Text size="sm" muted>
        {wait ? 'The agent is waiting for your answer.' : 'Preview only; nobody is waiting.'}
      </Text>
      <Spacer />
      <Button value="hold" variant="secondary">
        Hold
      </Button>
      <Button value="ship" variant="primary">
        Ship
      </Button>
    </Row>
  )
}

export default function Deploy({ data }: { data?: Partial<Release> }) {
  const release = { ...example, ...data }

  return (
    <Stack gap={16}>
      <Header release={release} />
      <Numbers release={release} />
      <Row gap={6} wrap>
        {release.checks.map((check) => (
          <Badge key={check.name} color={check.ok ? 'success' : 'warning'} dot>
            {check.note ? `${check.name}: ${check.note}` : check.name}
          </Badge>
        ))}
      </Row>
      <Card title="The change to look at" subtitle={release.file}>
        <CodeBlock code={release.diff} lang="diff" />
      </Card>
      <Answer />
    </Stack>
  )
}
