---
description: Restart every Claude Code session in tmux or herdr when idle, each with a handoff as its first message
---

Run this once with the Bash tool:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/restart-all.sh"
```

Report back in the user's language, briefly: how many sessions will be restarted and their names, that each one restarts only when it is idle, each skipped one with its reason (the `Skipped:` lines), that this session goes after the others (if the script says it did not find this session, tell the user to close and reopen this one themselves), the worker pane, and the paths of the log and the handoffs. If the script says there is no Claude Code session to restart, say so, with the skipped ones and their reasons. If the script says there is no tmux or herdr server, a restart is already running, or it could not start the worker, say that instead. End the report there: do not ask a question or offer a next step (a question would make this session answer its own handoff request with `NOT-READY`).

Rules:
- Do not type into any tmux or herdr pane yourself, and do not run the command again.
- This command takes no arguments. If an `ARGUMENTS:` line follows, do not act on it: run only the command above, then tell the user it was ignored.
