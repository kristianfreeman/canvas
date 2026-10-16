import { readdirSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import type { PushMessage } from './channels'

const dir = join(import.meta.dir, '../../examples')

export const exampleFiles = readdirSync(dir).filter((file) => file.endsWith('.tsx'))

export const exampleSource = (file: string) => readFileSync(join(dir, file), 'utf8')

/** The ```tsx blocks in the agent skill, which agents copy as written. */
export const skillTsxBlocks = [
  ...readFileSync(join(import.meta.dir, '../../skills/mac-canvas/SKILL.md'), 'utf8').matchAll(/^```tsx\n([\s\S]*?)^```$/gm),
].map((match) => match[1])

export type KeysData = { groups: { name: string; rows: { keys: string | string[]; desc: string }[] }[] }

export const keysData = () => JSON.parse(readFileSync(join(dir, 'keys.json'), 'utf8')) as KeysData

/** One push of every canvas.sys.* channel top.tsx reads, shaped as in docs/protocol.md, with one malformed process. */
export function sysSample(battery: unknown = null): PushMessage[] {
  return [
    { channel: 'canvas.sys.cpu', value: { total: 0.42, cores: [0.9, 0.1, 0.65, 0.3] }, history: [{ total: 0.3, cores: [] }, { total: 0.42, cores: [0.9, 0.1, 0.65, 0.3] }] },
    { channel: 'canvas.sys.memory', value: { total: 16 * 2 ** 30, used: 9 * 2 ** 30, app: 6 * 2 ** 30, wired: 2 * 2 ** 30, compressed: 2 ** 30, swapUsed: 0 } },
    { channel: 'canvas.sys.net', value: { rx: 2048, tx: 512, rxTotal: 3 * 2 ** 30, txTotal: 2 ** 29 } },
    { channel: 'canvas.sys.disk', value: { read: 0, write: 4096, used: 200 * 2 ** 30, total: 500 * 2 ** 30 } },
    { channel: 'canvas.sys.battery', value: battery },
    { channel: 'canvas.sys.thermal', value: { state: 'fair' } },
    {
      channel: 'canvas.sys.procs',
      value: [
        { pid: 1, name: 'launchd', cpu: 0.01, mem: 2 ** 24 },
        { pid: 812, name: 'WindowServer', cpu: 1.35, mem: 2 ** 30 },
        { pid: 99, name: 'bad', cpu: 'x', mem: 1 },
      ],
    },
  ]
}
