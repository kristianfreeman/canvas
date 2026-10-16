function partHeight(selector: string) {
  return document.querySelector(selector)?.getBoundingClientRect().height ?? 0
}

/** Natural size: header + the unconstrained content wrapper + footer, never the viewport, so the window resizing can't feed back into it. */
export function measureSurface() {
  const height = Math.ceil(partHeight('.cv-header') + partHeight('.cv-content') + partHeight('.cv-footer'))
  const width = Math.ceil(document.documentElement.getBoundingClientRect().width)

  return { width, height }
}
