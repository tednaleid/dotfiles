// ABOUTME: Type contract for the context-bar mod's session state.
// ABOUTME: Declares the breakdown snapshot and the visibility flag under PluginState.

export type Segment = { name: string; color: string; tokens: number; kind: 'used' | 'free' | 'buffer' }

export type Snapshot = { segments: Segment[]; usedTokens: number; maxTokens: number; percentage: number }

declare module 'claude-code' {
  interface PluginState {
    'context-bar': { snapshot: Snapshot | null; isShown: boolean }
  }
}
