---
description: Dry run of /kit-update:all-projects — also lists project/local installs of other projects, without changing anything
---

Run this once with the Bash tool and change nothing:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/update-all.sh" --dry-run --all-projects
```

Report back in the user's language: how many installs would be checked (with their scopes) — a dry run can't tell which ones actually have a newer version, so don't say they will all change — what was skipped and why, and which plugins are not updatable through marketplaces (session, skills-dir or claude.ai-synced). End with one line saying `/kit-update:all-projects` will apply it.

This command takes no arguments. If an `ARGUMENTS:` line follows, do not act on it: run only the command above, then tell the user it was ignored and that other flags need the script run from a terminal.
