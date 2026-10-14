export type EpochMs = number

declare module 'claude-code' {
  interface PluginState {
    'kit-time': { lastAt: EpochMs | null; now: EpochMs }
  }
}
