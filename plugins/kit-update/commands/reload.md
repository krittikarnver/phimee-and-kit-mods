---
description: Type /reload-plugins into every idle Claude Code session running in tmux or herdr
---

Run this once with the Bash tool:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/reload-all.sh"
```

Report back in the user's language, briefly: the counts from the `Summary` line, the sessions that were reloaded, and each skipped one with its reason. If this session is among the skipped, tell the user to run `/reload-plugins` here themselves (you cannot run it for them). If there is no tmux or herdr server, say that each session needs `/reload-plugins` typed by hand.

Rules:
- Do not retry skipped sessions or type into any tmux or herdr pane yourself.
- This command takes no arguments. If an `ARGUMENTS:` line follows, do not act on it: run only the command above, then tell the user it was ignored.
