export type Generation = number

declare module 'claude-code' {
  interface PluginState {
    'kit-checkpoint': { gen: Generation }
  }
}
