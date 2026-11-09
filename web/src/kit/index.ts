import { publish, useChannel, useSeries, useStore } from './channels'
import { useCanvas } from './context'
import { Badge, BarChart, Card, Progress, Sparkline, Stat } from './data'
import { Button, Checkbox, Form, Input, Select, TextArea } from './input'
import { KeyChips } from './keys'
import { Divider, Grid, Row, Spacer, Stack } from './layout'
import { Table } from './table'
import { Code, CodeBlock, Heading, Kbd, Markdown, Text } from './text'

/** The `canvas` module that TSX files import. Checked against canvas.d.ts so the published types can't drift. */
export const kit = {
  useCanvas, useChannel, useSeries, useStore, publish,
  Stack, Row, Grid, Divider, Spacer,
  Heading, Text, Code, CodeBlock, Markdown, Kbd, KeyChips,
  Card, Table, Stat, Badge, Progress, BarChart, Sparkline,
  Button, Input, TextArea, Select, Checkbox, Form,
} satisfies typeof import('canvas')

export { channelStore } from './channels'
export { CanvasProvider } from './context'
