#!/usr/bin/env bash
# Self-check for user-said.sh against a fake CLAUDE_CONFIG_DIR and a throwaway git repo.
# Run: bash plugins/kit-scrutinize/scripts/user-said.test.sh

set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
FAKE=$(mktemp -d "${TMPDIR:-/tmp}/kit-user-said-test.XXXXXX")
trap 'rm -rf "$FAKE"' EXIT
export CLAUDE_CONFIG_DIR="$FAKE/config"
fails=0

check() { # NAME WANT(1 = must appear, 0 = must not) TEXT OUTPUT
  if { [[ "$2" == 1 ]] && [[ "$4" != *"$3"* ]]; } || { [[ "$2" == 0 ]] && [[ "$4" == *"$3"* ]]; }; then
    echo "FAIL: $1"; fails=$((fails + 1))
  else
    echo "ok: $1"
  fi
}

repo="$FAKE/repo"
mkdir -p "$repo/docs" "$CLAUDE_CONFIG_DIR/projects/p1/s1/subagents"
git -C "$repo" init -q
spec="$repo/docs/2026-01-01-thing-design.md"
echo "# thing" >"$spec"

# no transcript, no handoff
out=$(bash "$here/user-said.sh" "$spec")
check "nothing found says NONE" 1 "NONE: no transcript or kit-checkpoint handoff mentions 2026-01-01-thing-design.md" "$out"

# a handoff only
mkdir -p "$repo/.git/kit-handoff"
printf '# Handoff\nspec docs/2026-01-01-thing-design.md\n## ตัดสินใจอะไรไปแล้ว\n- ผู้ใช้เลือก A\n' >"$repo/.git/kit-handoff/20260101-000000-g1.md"
printf '# Handoff\nanother file\n' >"$repo/.git/kit-handoff/20260101-000001-g1.md"
out=$(bash "$here/user-said.sh" "$spec")
check "handoff that mentions the file is printed" 1 "ผู้ใช้เลือก A" "$out"
check "handoff that doesn't mention it is not" 0 "another file" "$out"

# a transcript: a question, the answer, and everything that isn't the user typing
t="$CLAUDE_CONFIG_DIR/projects/p1/s1.jsonl"
{
  echo '{"type":"user","message":{"role":"user","content":"<command-name>/clear</command-name>"}}'
  echo '{"type":"user","message":{"role":"user","content":"The kit-checkpoint plugin sent a message:\n# Handoff from a plugin"}}'
  echo '{"type":"user","isMeta":true,"message":{"role":"user","content":"meta caveat"}}'
  echo '{"type":"assistant","message":{"content":[{"type":"text","text":"Which one, A or B?"}]}}'
  echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{}}]}}'
  echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"tool output"}]}}'
  echo '{"type":"user","message":{"role":"user","content":"B please"}}'
  echo '{"type":"user","message":{"role":"user","content":"<task-notification>done</task-notification>"}}'
  echo '{"type":"user","message":{"role":"user","content":"[kit-update restart 1234] write a handoff"}}'
  echo '{"type":"attachment","attachment":{"type":"queued_command","prompt":"and keep it short"}}'
  echo '{"type":"user","message":{"role":"user","content":"\n\n<pasted_content id=\"9\">\nnotes the user pasted\n</pasted_content>"}}'
  echo '{"type":"assistant","message":{"content":[{"type":"text","text":"Wrote docs/2026-01-01-thing-design.md"}]}}'
  printf '{"type":"user","message":{"role":"user","content":"half writ'
} >"$t"
echo '{"type":"user","message":{"role":"user","content":"subagent prompt 2026-01-01-thing-design.md"}}' >"$CLAUDE_CONFIG_DIR/projects/p1/s1/subagents/a.jsonl"
out=$(bash "$here/user-said.sh" "$spec")
check "transcript header" 1 "=== transcript $t" "$out"
check "question before the answer" 1 $'CLAUDE: …Which one, A or B?\nUSER: B please' "$out"
check "queued prompt kept, with no question repeated" 1 $'---\nUSER: and keep it short' "$out"
check "pasted text kept" 1 "notes the user pasted" "$out"
for noise in "/clear" "Handoff from a plugin" "meta caveat" "tool output" "task-notification" "kit-update restart" "half writ" "subagent prompt"; do
  check "skips: $noise" 0 "$noise" "$out"
done
check "transcript wins over handoff" 0 "ผู้ใช้เลือก A" "$out"

echo "$([[ $fails == 0 ]] && echo PASS || echo "FAILED: $fails")"
exit $((fails > 0))
