export type UsageLine = string

declare module 'claude-code' {
  interface PluginState {
    'kit-usage': { line: UsageLine | null }
  }
}
