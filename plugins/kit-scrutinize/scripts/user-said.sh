#!/usr/bin/env bash
# What the user said while a spec or plan was being made, for /kit-scrutinize:explain. Read only.
# From every Claude Code transcript that mentions the file's name, prints each prompt the user
# typed, after the end of Claude's last message before it (the question it answers).
# If no transcript mentions the file (they're deleted after cleanupPeriodDays), prints the
# kit-checkpoint handoffs that do instead: Claude wrote those, not the user.
# Usage: bash user-said.sh <spec or plan>

set -uo pipefail
file=${1:?usage: user-said.sh <spec or plan>}
name=$(basename -- "$file")
projects="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"

# */*.jsonl only: subagent transcripts sit one level deeper and hold no user words
transcripts=$(grep -lF -- "$name" "$projects"/*/*.jsonl 2>/dev/null)
if [[ -n "$transcripts" ]]; then
  # oldest first, so the conversation that designed the file comes before the ones that built it
  printf '%s\n' "$transcripts" | tr '\n' '\0' | xargs -0 ls -tr | while IFS= read -r t; do
    printf '=== transcript %s\n' "$t"
    # -R + fromjson?: the current session's last line may be half written
    jq -Rrn '
      def is_prompt: (.type == "user" and (.message.content | type) == "string" and (.isMeta | not))
        or (.type == "attachment" and .attachment.type == "queued_command");
      def ptext: if .type == "user" then .message.content else .attachment.prompt end;
      # typed by the user: not a slash command, shell escape, task notification, or a message a
      # plugin sent in their place (a kit-checkpoint handoff, a kit-update restart request)
      def typed: ((startswith("<") | not) or startswith("<pasted_content"))
        and (test("^The [^\\n]* plugin sent a message:") | not) and (startswith("[kit-update restart") | not);
      foreach (inputs | fromjson? | objects) as $e ({q: "", out: null};
        if $e.type == "assistant" then
          ([$e.message.content[]? | select(.type == "text") | .text] | join("\n")) as $t
          | .out = null | if $t == "" then . else .q = $t end
        elif ($e | is_prompt) then
          ($e | ptext | sub("^\\s+"; "")) as $p
          | if ($p | typed) then .out = {q, p: $p} | .q = "" else .out = null end
        else .out = null end;
        .out // empty)
      | "---", (if .q == "" then empty else "CLAUDE: …" + .q[-500:] end), "USER: " + .p
    ' "$t"
  done
  exit 0
fi

gitdir=$(git -C "$(dirname -- "$file")" rev-parse --absolute-git-dir 2>/dev/null)
handoffs=$([[ -n "$gitdir" ]] && grep -lF -- "$name" "$gitdir"/kit-handoff/*.md 2>/dev/null)
if [[ -n "$handoffs" ]]; then
  printf '%s\n' "$handoffs" | while IFS= read -r h; do
    printf '=== handoff %s\n' "$h"
    cat "$h"
  done
else
  echo "NONE: no transcript or kit-checkpoint handoff mentions $name"
fi
