import { Badge, Button, Card, Code, Form, Row, Spacer, Stack, Text, TextArea, useCanvas } from 'canvas'

type Plan = {
  title: string
  service: string
  from: string
  to: string
  environment: string
  changes: string[]
}

const example: Plan = {
  title: 'Deploy api-gateway to production',
  service: 'api-gateway',
  from: 'v2.13.2',
  to: 'v2.14.0',
  environment: 'production',
  changes: [
    'Rate limiter moves from per-instance to Redis-backed buckets',
    'New /v2/batch endpoint behind the batch-api flag (off)',
    'Upgrade to Bun 1.4.2; cold start drops about 18%',
    'Migration 0042 adds an index on requests(created_at)',
  ],
}

export default function Approve({ data }: { data?: Partial<Plan> }) {
  const plan = { ...example, ...data }
  const { wait } = useCanvas()

  return (
    <Form>
      <Stack gap={6}>
        <Row gap={8}>
          <Badge color="warning" dot>
            Needs approval
          </Badge>
          <Badge color="muted">{plan.environment}</Badge>
        </Row>
        <Text size="lg" weight="semibold">
          {plan.title}
        </Text>
        <Text muted>
          <Code>{plan.service}</Code> {plan.from} → {plan.to}
        </Text>
      </Stack>

      <Card title="What changes">
        <Stack gap={9}>
          {plan.changes.map((change) => (
            <Row key={change} gap={10} align="start">
              <Text color="accent">•</Text>
              <Text>{change}</Text>
            </Row>
          ))}
        </Stack>
      </Card>

      <TextArea name="comment" label="Comment" placeholder="Optional note for the agent" rows={3} />

      <Row gap={8}>
        <Text size="sm" muted>
          {wait ? 'The agent is waiting for your answer.' : 'Preview only; nobody is waiting.'}
        </Text>
        <Spacer />
        <Button type="submit" name="decision" value="reject" variant="secondary">
          Reject
        </Button>
        <Button type="submit" name="decision" value="approve" variant="primary">
          Approve
        </Button>
      </Row>
    </Form>
  )
}
