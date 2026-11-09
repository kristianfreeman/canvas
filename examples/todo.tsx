import { Badge, Button, Card, Checkbox, Form, Input, Row, Stack, Text, useStore } from 'canvas'

type Item = { text: string; done: boolean }

/**
 * A to-do list whose items live in the persisted channel `todo.items`, so they survive closing the panel and
 * restarting the server. Read them with `canvas get todo.items`; replace them with `canvas pub todo.items '[...]'
 * --persist`.
 */
export default function Todo() {
  const [items, setItems] = useStore<Item[]>('todo.items', [])
  const left = items.filter((item) => !item.done).length

  const toggle = (index: number) =>
    setItems((list) => list.map((item, i) => (i === index ? { ...item, done: !item.done } : item)))
  // Item text is the key, so a duplicate isn't added.
  const add = (text: unknown) => {
    const trimmed = typeof text === 'string' ? text.trim() : ''
    if (trimmed) setItems((list) => (list.some((item) => item.text === trimmed) ? list : [...list, { text: trimmed, done: false }]))
  }
  const clearDone = () => setItems((list) => list.filter((item) => !item.done))

  return (
    <Card
      title="To do"
      actions={<Badge color={left ? 'accent' : 'success'}>{left ? `${left} left` : 'All done'}</Badge>}
    >
      <Stack gap={10}>
        {items.length === 0 ? <Text muted>Nothing yet. Add the first item below.</Text> : null}
        {items.map((item, i) => (
          <Checkbox key={item.text} name={`item${i}`} label={item.text} checked={item.done} onChange={() => toggle(i)} />
        ))}
        <Form onSubmit={(values) => add(values.text)}>
          <Row gap={8}>
            <Input name="text" placeholder="Add an item" style={{ flex: 1 }} />
            <Button variant="primary">Add</Button>
            <Button variant="ghost" onClick={clearDone} disabled={items.length === left}>
              Clear done
            </Button>
          </Row>
        </Form>
      </Stack>
    </Card>
  )
}
