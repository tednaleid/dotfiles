// ABOUTME: Type contract for the turn-timer mod's session state.
// ABOUTME: Declares the label drawn in the prompt footer's mode area.

export type TurnTimerLabel = string | null

declare module 'claude-code' {
  interface PluginState {
    'turn-timer': { label: TurnTimerLabel }
  }
}
