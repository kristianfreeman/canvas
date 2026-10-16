import { nextTask } from './bridge'

/** A unit of background work. Each `next()` should be one small step; the queue yields between slices. */
export type Task = Iterator<unknown>

export type IdleQueueOptions = {
  schedule?: (run: () => void) => void
  now?: () => number
  sliceMs?: number
}

/** requestIdleCallback where WebKit has it; otherwise a fresh task, which still lets a pending render() run first. */
function scheduleIdle(run: () => void) {
  if (typeof requestIdleCallback === 'function') requestIdleCallback(run, { timeout: 50 })
  else nextTask(run)
}

export type IdleQueue = ReturnType<typeof createIdleQueue>

/**
 * Runs tasks a step at a time in slices of about `sliceMs`, one slice per idle callback. A slice always runs at least
 * one step, so a single step is the longest the page can be busy. While any `hold()` is unreleased, no slice runs.
 */
export function createIdleQueue({ schedule = scheduleIdle, now = () => performance.now(), sliceMs = 5 }: IdleQueueOptions = {}) {
  const tasks: Task[] = []
  const holds = new Set<object>()
  let scheduled = false

  function pump() {
    if (scheduled || holds.size > 0 || tasks.length === 0) return
    scheduled = true
    schedule(slice)
  }

  function step() {
    const task = tasks[0]

    try {
      if (task.next().done) tasks.splice(tasks.indexOf(task), 1)
    } catch (error) {
      tasks.splice(tasks.indexOf(task), 1)
      console.warn('[canvas] background task failed', error)
    }
  }

  function slice() {
    scheduled = false
    const end = now() + sliceMs

    while (tasks.length > 0 && holds.size === 0) {
      step()

      if (now() >= end) break
    }

    pump()
  }

  return {
    /** `front` runs the task before everything already queued, for work the user can see. */
    add(task: Task, options?: { front?: boolean }) {
      if (options?.front) tasks.unshift(task)
      else tasks.push(task)
      pump()
    },
    /** Pauses the queue until the returned function is called. Calling it again is harmless. */
    hold() {
      const token = {}
      holds.add(token)

      return () => {
        if (holds.delete(token)) pump()
      }
    },
    get size() {
      return tasks.length
    },
  }
}

export const idle = createIdleQueue()
