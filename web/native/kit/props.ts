import type * as Canvas from 'canvas'

/** A kit component's props, straight from canvas.d.ts, so the shim takes exactly what TSX files are typed against. */
export type PropsOf<K extends keyof typeof Canvas> = (typeof Canvas)[K] extends (props: infer P) => unknown ? P : never
