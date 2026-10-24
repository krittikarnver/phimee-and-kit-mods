# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A Claude Code plugin marketplace (`.claude-plugin/marketplace.json`) with one folder per plugin under `plugins/`. Each plugin works and installs on its own. `9arm-skills` is listed in the marketplace but lives in an external GitHub repo, and `kit-scrutinize` depends on it.

There are two kinds of plugin here:

- **Hooks-module mods** (`kit-time`, `kit-usage`, `kit-checkpoint`). `hooks/hooks.json` is `{ "modules": ["./register.tsx"] }` (`./register.ts` in `kit-checkpoint`, which has no UI), and the module exports `register: Register` from `'claude-code'`. The module runs in the engine's own sandbox with no Node and no DOM, so everything goes through `$` (`$.session.usage()`, `$.clock`, `$.store`, `$.fs`, `$.ui`). JSX renders through `$.ui.resolve(e)`.
- **Markdown plugins** (`kit-scrutinize`: skill + agent; `kit-update`: commands that run `scripts/update-all.sh`, `scripts/reload-all.sh` and `scripts/restart-all.sh`).

## Commands

```bash
claude plugin validate ./plugins/<name>   # manifest + what the module hooks/calls, what the engine would refuse
claude plugin test ./plugins/<name>       # runs every *.test.ts(x) under the folder; there's no single-test filter
claude --plugin-dir ./plugins/<name>      # start a session with the local copy loaded
tsc -p ./plugins/<name>                   # type-check; only works after the engine has generated types (below)
bash plugins/kit-update/scripts/update-all.sh --dry-run   # KIT_UPDATE_CLAUDE_BIN=<fake> to stub the claude CLI
bash plugins/kit-update/scripts/reload-all.test.sh       # self-check for reload-all.sh against a fake tmux and herdr (KIT_UPDATE_TMUX_BIN, KIT_UPDATE_HERDR_BIN)
bash plugins/kit-update/scripts/restart-all.test.sh      # self-check for restart-all.sh and restart-worker.sh against a fake tmux and herdr (~45 s)
```

## Mod conventions

- **Types are generated, not committed.** Each mod's `tsconfig.json` extends `./.claude-plugin/types/tsconfig.json`, which the engine writes when it loads the mod (e.g. via `--plugin-dir`). It's gitignored, so `tsc` fails on a fresh checkout until the mod has been loaded once. The full API, with every event and `$` method documented, is in `.claude-plugin/types/claude-code/index.d.ts`.
- **Session state** goes through `atom({ plugin, key })` + `read`/`update`, and every key must be declared in `types/index.d.ts` under `interface PluginState` (named in `plugin.json` as `"types"`). `validate` enforces this.
- **Pure logic is kept testable.** Formatting lives in plain exported functions (`kit-usage/hooks/format.ts`, the `format*` exports in `kit-time/hooks/register.tsx`, `kit-checkpoint/hooks/logic.ts`), and tests import those from `'claude-code/testing'` instead of driving hooks. `kit-checkpoint/hooks/register.test.ts` is the exception: it drives the hooks against a mocked engine (`world()`), because the clear/handoff flow depends on event order.
- **How context reaches Claude:** `prompt.submit` hooks call `next({ ...e, context: [...(e.context ?? []), line] })`. Lines start with `[plugin-name]`. A hook must never block a prompt: catch, then `next(e)`.
- **Time is Asia/Bangkok** (fixed UTC+7 offset, no DST). Dates use Thai month abbreviations and the BE year (+543).

## Repo conventions

- User-facing text is Thai: README, `plugin.json` descriptions, marketplace descriptions, toasts, and the context lines injected for Claude.
- A new plugin needs three things: an entry in `.claude-plugin/marketplace.json`, an `/plugin install` line in the README, and a README section.
- Bump `version` in the plugin's `plugin.json` whenever you change a plugin. Commit subjects name the plugin, e.g. `kit-update 0.1.1: ...`.
- Untracked notes under `docs/` (handoffs) are temporary. Don't commit them.
