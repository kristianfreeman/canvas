import { Button, Card, Row, Sparkline, Stack, Stat, Text, publish, useChannel, useSeries } from 'canvas'

type Data = { channel?: string; label?: string; unit?: string }

const show = (value: number | undefined, unit = '') => (value === undefined ? '–' : `${value}${unit}`)

function useNumbers(channel: string) {
  const latest = useChannel<number>(channel)
  const series = useSeries<number>(channel, 120).filter((value) => typeof value === 'number')

  return { latest, series, peak: series.length ? Math.max(...series) : undefined }
}

/**
 * A live number from a channel:
 *   canvas show examples/live.tsx --data '{"channel":"demo.load","label":"Load"}'
 *   while true; do canvas pub demo.load $((RANDOM % 100)); sleep 0.5; done
 */
export default function Live({ data }: { data?: Data }) {
  const { channel = 'demo.load', label = channel, unit } = data ?? {}
  const { latest, series, peak } = useNumbers(channel)
  const mark = () => publish(`${channel}.mark`, { at: Date.now(), value: latest ?? null })

  return (
    <Stack gap={14}>
      <Card>
        <Stack gap={12}>
          <Row justify="between" align="start">
            <Stat label={label} value={show(latest, unit)} />
            <Stat label="Peak" value={show(peak, unit)} color="muted" />
          </Row>
          <Sparkline data={series} width="100%" height={56} color="accent" />
        </Stack>
      </Card>
      <Row justify="between">
        <Text size="sm" muted>
          {series.length ? `${series.length} samples on ${channel}` : `Waiting for ${channel}`}
        </Text>
        <Button variant="ghost" onClick={mark}>
          Mark
        </Button>
      </Row>
    </Stack>
  )
}
