import { expect, test } from 'bun:test'
import { contrastText, resolveColor } from './colors'

test('semantic names resolve to their tokens', () => {
  expect(resolveColor('accent')).toBe('var(--accent)')
  expect(resolveColor('success')).toBe('var(--success)')
  expect(resolveColor('warning')).toBe('var(--warning)')
  expect(resolveColor('danger')).toBe('var(--danger)')
  expect(resolveColor('info')).toBe('var(--info)')
  expect(resolveColor('muted')).toBe('var(--fg-muted)')
})

test('hue names resolve to the system color tokens, shadowing CSS named colors', () => {
  expect(resolveColor('red')).toBe('var(--red)')
  expect(resolveColor('gray')).toBe('var(--gray)')
  expect(resolveColor('teal')).toBe('var(--teal)')
})

test('anything else passes through as a CSS color, including retired palette names and prototype keys', () => {
  expect(resolveColor('#12abef')).toBe('#12abef')
  expect(resolveColor('oklch(70% 0.1 200)')).toBe('oklch(70% 0.1 200)')
  expect(resolveColor('mauve')).toBe('mauve')
  expect(resolveColor('constructor')).toBe('constructor')
})

test('a missing color uses the fallback', () => {
  expect(resolveColor(undefined)).toBe('var(--accent)')
  expect(resolveColor('', 'var(--gray)')).toBe('var(--gray)')
})

test('accent foreground: white on saturated darks, black on light colors', () => {
  expect(contrastText([0, 122, 255])).toBe('#ffffff')
  expect(contrastText([255, 59, 48])).toBe('#ffffff')
  expect(contrastText([175, 82, 222])).toBe('#ffffff')
  expect(contrastText([255, 204, 0])).toBe('#000000')
  expect(contrastText([52, 199, 89])).toBe('#000000')
  expect(contrastText([203, 166, 247])).toBe('#000000')
  expect(contrastText([255, 255, 255])).toBe('#000000')
  expect(contrastText([0, 0, 0])).toBe('#ffffff')
})
