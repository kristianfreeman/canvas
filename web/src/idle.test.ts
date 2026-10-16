import { expect, test } from 'bun:test'
import { createIdleQueue } from './idle'

function harness(sliceMs = 5) {
  const clock = { t: 0 }
  const pending: (() => void)[] = []
  const queue = createIdleQueue({ schedule: (run) => pending.push(run), now: () => clock.t, sliceMs })

  const runSlice = () => {
    const run = pending.shift()

    if (!run) throw new Error('no slice scheduled')
    run()
  }

  return { clock, pending, queue, runSlice }
}

function* costly(log: string[], name: string, { steps, cost }: { steps: number; cost: () => void }) {
  for (let i = 0; i < steps; i++) {
    cost()
    log.push(`${name}${i}`)
    yield
  }
}

test('a slice stops once it has used its time, and the rest runs in later slices', () => {
  const { clock, queue, runSlice, pending } = harness(5)
  const log: string[] = []
  queue.add(costly(log, 'a', { steps: 7, cost: () => (clock.t += 2) }))

  runSlice()
  expect(log).toEqual(['a0', 'a1', 'a2'])
  runSlice()
  expect(log).toHaveLength(6)
  runSlice()
  expect(log).toHaveLength(7)
  expect(queue.size).toBe(0)
  expect(pending).toHaveLength(0)
})

test('a step longer than a slice still makes progress, one step per slice', () => {
  const { clock, queue, runSlice } = harness(5)
  const log: string[] = []
  queue.add(costly(log, 'slow', { steps: 3, cost: () => (clock.t += 50) }))

  runSlice()
  expect(log).toEqual(['slow0'])
  runSlice()
  expect(log).toEqual(['slow0', 'slow1'])
})

test('nothing runs while held, and work resumes once every hold is released', () => {
  const { queue, runSlice, pending } = harness()
  const log: string[] = []
  const releaseA = queue.hold()
  const releaseB = queue.hold()
  queue.add(costly(log, 'w', { steps: 2, cost: () => {} }))

  expect(pending).toHaveLength(0)
  releaseA()
  releaseA()
  expect(pending).toHaveLength(0)
  releaseB()
  runSlice()
  expect(log).toEqual(['w0', 'w1'])
})

test('a hold taken after a slice was scheduled stops that slice from running steps', () => {
  const { queue, runSlice, pending } = harness()
  const log: string[] = []
  queue.add(costly(log, 'w', { steps: 2, cost: () => {} }))
  const release = queue.hold()

  runSlice()
  expect(log).toEqual([])
  release()
  expect(pending).toHaveLength(1)
  runSlice()
  expect(log).toEqual(['w0', 'w1'])
})

test('front tasks run before queued ones, even mid-task', () => {
  const { clock, queue, runSlice } = harness(3)
  const log: string[] = []
  queue.add(costly(log, 'warm', { steps: 4, cost: () => (clock.t += 2) }))
  runSlice()
  queue.add(costly(log, 'up', { steps: 1, cost: () => {} }), { front: true })

  while (queue.size > 0) runSlice()
  expect(log).toEqual(['warm0', 'warm1', 'up0', 'warm2', 'warm3'])
})

test('a task that throws is dropped and the others keep running', () => {
  const { queue, runSlice } = harness()
  const log: string[] = []
  const warn = console.warn
  console.warn = () => {}

  try {
    queue.add(costly(log, 'bad', { steps: 2, cost: () => {
      throw new Error('boom')
    } }))
    queue.add(costly(log, 'ok', { steps: 1, cost: () => {} }))
    runSlice()
  } finally {
    console.warn = warn
  }

  expect(log).toEqual(['ok0'])
  expect(queue.size).toBe(0)
})
