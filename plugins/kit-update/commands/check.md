---
description: Dry run — list the plugin installs that /kit-update:all would update, without changing anything
argument-hint: "[--all-projects] [--only REGEX] [--scope ...]"
---

Run this once with the Bash tool and change nothing:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/update-all.sh" --dry-run $ARGUMENTS
```

Report back in the user's language: how many installs would be updated (with their scopes), what was skipped and why, and which plugins are not updatable through marketplaces (session, skills-dir or claude.ai-synced). End with one line saying `/kit-update:all` will apply it.
