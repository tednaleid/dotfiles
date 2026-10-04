// ABOUTME: Tests for the context-bar mod: cell arithmetic, drawing above the prompt, and the toggle command.
// ABOUTME: The engine's session.usage is answered with a fixed breakdown so the bar is deterministic.

import type { CommandRunInput, RenderElement, SessionContextBreakdown, SessionUsage } from 'claude-code'
import { expect, test } from 'claude-code/testing'

import { cellWidths, fillColor, toSnapshot } from '../hooks/bar'

const BREAKDOWN = {
  categories: [
    { name: 'System prompt', tokens: 20_000, color: 'promptBorder', isDeferred: false, kind: 'used' },
    { name: 'System tools', tokens: 10_000, color: 'inactive', isDeferred: false, kind: 'used' },
    { name: 'Skills', tokens: 4_000, color: 'warning', isDeferred: false, kind: 'used' },
    { name: 'Custom agents', tokens: 1_000, color: 'suggestion', isDeferred: false, kind: 'used' },
    { name: 'Memory files', tokens: 2_000, color: 'remember', isDeferred: false, kind: 'used' },
    { name: 'Messages', tokens: 60_000, color: 'permission', isDeferred: false, kind: 'used' },
    { name: 'MCP tools (deferred)', tokens: 9_000, color: 'inactive', isDeferred: true, kind: 'deferred' },
    { name: 'Free space', tokens: 87_000, color: 'promptBorder', isDeferred: false, kind: 'free' },
    { name: 'Autocompact buffer', tokens: 33_000, color: 'inactive', isDeferred: false, kind: 'buffer' },
  ],
  totalTokens: 80_000,
  maxTokens: 200_000,
  rawMaxTokens: 200_000,
  autocompactSource: 'model-default',
  percentage: 40,
  gridRows: [],
  model: 'test',
  memoryFiles: [],
  mcpTools: [],
  agents: [],
} as unknown as SessionContextBreakdown

const USAGE: SessionUsage = {
  startedAt: 0,
  context: { tokens: 80_000, window: 200_000, percent: 40, breakdown: BREAKDOWN },
  rateLimits: [],
}

const TOGGLE: CommandRunInput = {
  command: 'context-bar',
  args: '',
  origin: { kind: 'composer' },
  presentation: { isFullscreen: false, columns: 100 },
}

const BAND = {
  component: 'AbovePrompt',
  props: { hasSurvey: false, isWorking: false, maxRows: 10, bodyColumns: 100, scroll: { offset: 0, bodyRows: 10 }, view: {} },
} as const

test('cell widths always fill the bar exactly', () => {
  const segs = [3, 3, 3].map(tokens => ({ name: 'x', color: 'c', tokens, kind: 'used' as const }))
  expect(cellWidths(segs, 10).reduce((a, b) => a + b, 0)).toBe(10)
  expect(cellWidths([], 10)).toEqual([])
})

test('fixed groups are gray and messages follow the window fill', () => {
  const colors = Object.fromEntries(toSnapshot(BREAKDOWN).segments.map(s => [s.name, s.color]))
  expect(colors).toEqual({
    System: 'gray',
    Tools: 'gray',
    Memory: 'gray',
    Messages: 'green',
    'Free space': 'gray',
    'Autocompact buffer': 'gray',
  })
  expect([40, 41, 70, 71].map(fillColor)).toEqual(['green', 'yellow', 'yellow', 'red'])
})

test('a tiny used segment still gets one cell', () => {
  const segs = [
    { name: 'Memory', color: 'yellow', tokens: 2_000, kind: 'used' as const },
    { name: 'Free space', color: 'gray', tokens: 998_000, kind: 'free' as const },
  ]
  expect(cellWidths(segs, 140)).toEqual([1, 139])
})

test('starts hidden, and /context-bar toggles the bar and legend', async ($, on) => {
  on('session.usage', () => ({ value: USAGE }))
  on('command.register', (_, e) => ({ value: { command: e.name } }))
  on('ui.render', ($, e) => {
    const { Box } = $.ui.resolve(e)
    return h(Box, { key: 'engine' }) as RenderElement
  })
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })

  const initial = await $.ui.mount({ plugin: 'context-bar', surface: 'terminal', ...BAND })
  expect(await initial.find({ key: 'bar' })).toBeUndefined()
  expect(await initial.find({ key: 'engine' })).toBeDefined()
  await initial.unmount()

  expect((await $.command.run(TOGGLE)).text).toBe('Context bar shown.')
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'context-bar', surface, ...BAND })
    expect(await ui.find({ type: 'Text', text: /80k\/200k \(40%\)/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Messages 60k/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /System 30k/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Tools 5k/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Memory 2k/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /deferred/ })).toBeUndefined()
    await ui.unmount()
  }

  expect((await $.command.run(TOGGLE)).text).toBe('Context bar hidden.')
  const hidden = await $.ui.mount({ plugin: 'context-bar', surface: 'terminal', ...BAND })
  expect(await hidden.find({ key: 'bar' })).toBeUndefined()
  await hidden.unmount()
})
