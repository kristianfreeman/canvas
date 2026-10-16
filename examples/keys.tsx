import { Code, Grid, Heading, Kbd, KeyChips, Row, Spacer, Stack, Text } from 'canvas'

type Shortcut = { keys: string | string[]; desc: string }

type Group = { name: string; rows: Shortcut[] }

type Data = { groups?: Group[] }

/** Splits groups into two columns of similar height, keeping the original order inside each column. */
function balance(groups: Group[]): [Group[], Group[]] {
  const weight = (g: Group) => g.rows.length + 1.6
  const columns: [number[], number[]] = [[], []]
  const totals = [0, 0]
  const order = groups.map((g, i) => i).toSorted((a, b) => weight(groups[b]) - weight(groups[a]))

  for (const i of order) {
    const target = totals[0] <= totals[1] ? 0 : 1
    columns[target].push(i)
    totals[target] += weight(groups[i])
  }

  const pick = (ids: number[]) => ids.toSorted((a, b) => a - b).map((i) => groups[i])
  const [a, b] = [pick(columns[0]), pick(columns[1])]

  return groups.indexOf(a[0]) <= groups.indexOf(b[0]) ? [a, b] : [b, a]
}

/** Pairs each item with a key built from its content; repeats get a counter so keys stay unique. */
function keyed<T>(items: T[], text: (item: T) => string) {
  const seen = new Map<string, number>()

  return items.map((item) => {
    const base = text(item)
    const count = (seen.get(base) ?? 0) + 1
    seen.set(base, count)

    return { key: count === 1 ? base : `${base}#${count}`, item }
  })
}

/**
 * One grid per column, so descriptions line up across its groups. A group name sits in the chip column with an empty
 * cell beside it; the chips' right padding is the gap between the columns, since a grid gap would space the rows too.
 */
function Column({ groups }: { groups: Group[] }) {
  return (
    <Grid columns="max-content 1fr" gap={0}>
      {groups.flatMap((group, index) => [
        <Heading key={`g-${group.name}`} level={4} style={{ marginTop: index === 0 ? 0 : 22, marginBottom: 6 }}>
          {group.name}
        </Heading>,
        <Spacer key={`s-${group.name}`} size={0} />,
        ...keyed(group.rows, (row) => row.desc).flatMap(({ key, item: row }) => [
          <KeyChips key={`k-${group.name}-${key}`} keys={row.keys} style={{ paddingRight: 18 }} />,
          <Text key={`d-${group.name}-${key}`} style={{ paddingTop: 5, paddingBottom: 4 }}>
            {row.desc}
          </Text>,
        ]),
      ])}
    </Grid>
  )
}

function Empty() {
  return (
    <Stack gap={4} align="center" style={{ paddingTop: 40, paddingBottom: 28 }}>
      <Text weight="medium">No shortcuts to show</Text>
      <Text size="sm" muted style={{ textAlign: 'center' }}>
        Pass <Code>--data</Code> with <Code>{'{ groups: [{ name, rows: [{ keys, desc }] }] }'}</Code>
      </Text>
    </Stack>
  )
}

export default function Keys({ data }: { data?: Data }) {
  const groups = (data?.groups ?? []).filter((g) => g && Array.isArray(g.rows) && g.rows.length > 0)

  if (groups.length === 0) return <Empty />
  const [left, right] = balance(groups)

  return (
    <Stack gap={22} style={{ paddingTop: 6 }}>
      <Grid columns={2} gap={40}>
        <Column groups={left} />
        <Column groups={right} />
      </Grid>
      <Row gap={6}>
        <Kbd tone="accent">✦</Kbd>
        <Text size="sm" muted>Hyper</Text>
        <Spacer />
        <Kbd>Esc</Kbd>
        <Text size="sm" muted>to close</Text>
      </Row>
    </Stack>
  )
}
