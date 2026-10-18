---
description: Like /kit-update:all, but also updates project/local installs of other projects
---

Update all installed plugins by running the bundled script exactly once with the Bash tool:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/update-all.sh" --all-projects
```

Use a Bash timeout of at least 300000 ms — each plugin update is a separate CLI call and git-backed marketplaces can be slow.

Then report back in the user's language, briefly:

1. One line with the counts from the script's `Summary` line.
2. The updated plugins with old → new version, if any.
3. Failures, each with its reason. If the script printed commands under "need you to accept a changed install command", show them in a code block and explain that Claude Code ignores `-y` / `--accept-command` when run from inside a session, so the user must review the command and run it in their own terminal.
4. If anything was updated, remind the user to run `/reload-plugins` (you cannot run it for them).

Rules:
- Do not retry failed updates, run individual `claude plugin update` calls, or edit anything under `~/.claude/plugins/` yourself.
- Do not run `claude plugin marketplace remove` or `uninstall` for any reason.
- This command takes no arguments. If an `ARGUMENTS:` line follows, do not act on it: run only the command above, then tell the user it was ignored and that other flags need the script run from a terminal.
- If the script exits with a precondition error (jq missing, Claude Code too old), relay the fix it printed and stop.
