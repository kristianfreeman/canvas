import { createElement } from 'react'
import { publish, useChannel, useSeries } from './channels'
import { useCanvas } from './context'
import { Badge, BarChart, Card, Progress, Sparkline, Stat } from './data'
import { Button, Checkbox, Form, Input, Select, TextArea } from './input'
import { Divider, Grid, Row, Spacer, Stack } from './layout'
import { Table } from './table'
import { Code, CodeBlock, Heading, Kbd, KeyChips, Markdown, Text } from './text'

/** The `canvas` module for native TSX, checked against canvas.d.ts like the web kit. */
export const kit = {
  useCanvas, useChannel, useSeries, publish,
  Stack, Row, Grid, Divider, Spacer,
  Heading, Text, Code, CodeBlock, Markdown, Kbd, KeyChips,
  Card, Table, Stat, Badge, Progress, BarChart, Sparkline,
  Button, Input, TextArea, Select, Checkbox, Form,
} satisfies typeof import('canvas')

/** The panel footer for `--buttons`; Swift draws it and posts the clicked label as the result. */
export function footer(buttons: readonly unknown[] | undefined, wait: boolean) {
  const labels = (buttons ?? []).filter((b): b is string => typeof b === 'string' && b.length > 0)

  return labels.length > 0 ? createElement('Footer', { buttons: labels, wait }) : null
}

export { channelStore } from './channels'
export { CanvasProvider } from './context'
