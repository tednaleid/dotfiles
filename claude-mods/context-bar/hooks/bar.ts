// ABOUTME: Pure helpers that turn a /context breakdown into bar segments and cell widths.
// ABOUTME: Kept free of the engine so tests can exercise the arithmetic directly.

import type { SessionContextBreakdown } from 'claude-code'

import type { Segment, Snapshot } from '../types'

// The four groups the bar draws, in order. System, Tools and Memory are the
// same in every session and draw gray; Messages takes its color from how full
// the window is. Colors are ANSI names, so the terminal's theme decides them.
const GROUPS = [
  { name: 'System', test: /system/i },
  { name: 'Tools', test: /mcp|agent|skill|plugin|command/i },
  { name: 'Memory', test: /memory/i },
  { name: 'Messages', test: /message/i },
] as const

// The same thresholds as claude-statusline.sh's default CLAUDE_CONTEXT_GRADIENT.
export const fillColor = (percentage: number): string =>
  percentage <= 40 ? 'green' : percentage <= 70 ? 'yellow' : 'red'

// Rows matching no group (new categories the engine adds) count as System.
const groupOf = (name: string) =>
  GROUPS.slice(1).find(g => g.test.test(name)) ?? GROUPS[0]

export const toSnapshot = (breakdown: SessionContextBreakdown): Snapshot => {
  const used = new Map<string, number>()
  let free = 0
  let buffer = 0
  for (const row of breakdown.categories) {
    if (row.kind === 'used') {
      const group = groupOf(row.name).name
      used.set(group, (used.get(group) ?? 0) + row.tokens)
    } else if (row.kind === 'free') {
      free += row.tokens
    } else if (row.kind === 'buffer') {
      buffer += row.tokens
    }
  }

  const segments: Segment[] = GROUPS.filter(g => (used.get(g.name) ?? 0) > 0).map(g => ({
    name: g.name,
    color: g.name === 'Messages' ? fillColor(breakdown.percentage) : 'gray',
    tokens: used.get(g.name) ?? 0,
    kind: 'used',
  }))
  if (free > 0) segments.push({ name: 'Free space', color: 'gray', tokens: free, kind: 'free' })
  if (buffer > 0) segments.push({ name: 'Autocompact buffer', color: 'gray', tokens: buffer, kind: 'buffer' })

  return {
    segments,
    usedTokens: breakdown.totalTokens,
    maxTokens: breakdown.rawMaxTokens,
    percentage: breakdown.percentage,
  }
}

// Largest-remainder split of `width` cells across segments by token share.
// Every used segment gets at least one cell, taken from the widest segment,
// so a small group like Memory stays visible on a 1M window.
export const cellWidths = (segments: readonly Segment[], width: number): number[] => {
  const total = segments.reduce((sum, s) => sum + s.tokens, 0)
  if (total <= 0 || width <= 0) return segments.map(() => 0)

  const exact = segments.map(s => (s.tokens / total) * width)
  const cells = exact.map(Math.floor)
  let left = width - cells.reduce((sum, n) => sum + n, 0)
  const byRemainder = exact
    .map((value, i) => ({ i, rest: value - Math.floor(value) }))
    .sort((a, b) => b.rest - a.rest)
  for (const { i } of byRemainder) {
    if (left <= 0) break
    cells[i] = (cells[i] ?? 0) + 1
    left -= 1
  }
  segments.forEach((s, i) => {
    if (s.kind !== 'used' || (cells[i] ?? 0) > 0) return
    const widest = cells.indexOf(Math.max(...cells))
    if ((cells[widest] ?? 0) <= 1) return
    cells[widest] = (cells[widest] ?? 0) - 1
    cells[i] = 1
  })

  return cells
}

export const formatTokens = (tokens: number): string =>
  tokens >= 1_000_000
    ? `${(tokens / 1_000_000).toFixed(1)}M`
    : tokens >= 1000
      ? `${Math.round(tokens / 1000)}k`
      : `${tokens}`
