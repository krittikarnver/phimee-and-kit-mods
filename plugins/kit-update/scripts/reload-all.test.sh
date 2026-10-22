#!/usr/bin/env bash
# Self-check for reload-all.sh against a fake tmux and a fake herdr: which panes get keys, which are skipped.
# Run: bash plugins/kit-update/scripts/reload-all.test.sh

set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
FAKE=$(mktemp -d "${TMPDIR:-/tmp}/kit-reload-test.XXXXXX")
trap 'rm -rf "$FAKE"' EXIT

cat >"$FAKE/tmux" <<'EOF'
#!/usr/bin/env bash
# fake tmux: panes from $FAKE/panes, screens from $FAKE/screen-<id>, keys logged to $FAKE/sent
case "$1" in
  list-panes) [[ -f "$FAKE/panes" ]] && cat "$FAKE/panes" ;;
  capture-pane) cat "$FAKE/screen-$4" ;;
  send-keys) shift; echo "$*" >>"$FAKE/sent" ;;
esac
EOF
cat >"$FAKE/herdr" <<'EOF'
#!/usr/bin/env bash
# fake herdr: agents from $FAKE/agents, screens from $FAKE/hscreen-<pane>, prompts logged to $FAKE/prompted
case "$1 $2" in
  "agent list") [[ -f "$FAKE/agents" ]] && cat "$FAKE/agents" ;;
  "agent read") cat "$FAKE/hscreen-$3" ;;
  "agent prompt") echo "$3 $4" >>"$FAKE/prompted" ;;
esac
EOF
chmod +x "$FAKE/tmux" "$FAKE/herdr"
export FAKE KIT_UPDATE_TMUX_BIN="$FAKE/tmux" KIT_UPDATE_HERDR_BIN="$FAKE/herdr"

fails=0
check() { # $1 = label, $2 = condition result
  if [[ "$2" == 0 ]]; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi
}

# neither tmux nor herdr
out=$(bash "$here/reload-all.sh")
grep -q 'No tmux or herdr server' <<<"$out"; check "no server: says so" $?

# herdr only
agent() { # $1 pane, $2 name or null, $3 cwd, $4 kind, $5 state
  printf '{"pane_id":"%s","name":%s,"cwd":"%s","agent":"%s","agent_status":"%s"}' "$@"
}
{
  printf '{"result":{"agents":['
  agent w1:p1 '"alpha"' /x/alpha claude idle; printf ,
  agent w1:p2 null /x/beta claude done; printf ,
  agent w1:p3 null /x/busy claude working; printf ,
  agent w1:p4 null /x/ask claude blocked; printf ,
  agent w1:p5 null /x/draft claude idle; printf ,
  agent w1:p6 null /x/self claude idle; printf ,
  agent w1:p7 null /x/codex codex idle; printf ,
  agent w1:p8 null /x/odd claude unknown
  printf ']}}\n'
} >"$FAKE/agents"
printf '⏺ done\n❯ \n  ⏵⏵ auto mode on\n' >"$FAKE/hscreen-w1:p1"
printf '❯ Try "how does <filepath> work?"\n' >"$FAKE/hscreen-w1:p2"
printf '❯ \n⏺ answer\n❯ half typed\n' >"$FAKE/hscreen-w1:p5"
printf '❯ \n' >"$FAKE/hscreen-w1:p6"

out=$(HERDR_PANE_ID=w1:p6 bash "$here/reload-all.sh")
prompted=$(cat "$FAKE/prompted" 2>/dev/null)

! grep -q 'No tmux or herdr server' <<<"$out"; check "herdr only: no 'no server' message" $?
grep -qx 'w1:p1 /reload-plugins' <<<"$prompted"; check "herdr idle agent gets /reload-plugins" $?
grep -qx 'w1:p2 /reload-plugins' <<<"$prompted"; check "herdr done agent with a hint counts as idle" $?
for id in w1:p3 w1:p4 w1:p5 w1:p6 w1:p7 w1:p8; do
  ! grep -q "^$id " <<<"$prompted"; check "no prompt sent to $id" $?
done
grep -q 'alpha (herdr w1:p1)' <<<"$out"; check "herdr agent shown by its name" $?
grep -q 'busy (herdr w1:p3) — busy' <<<"$out"; check "herdr working is reported busy" $?
grep -q 'ask (herdr w1:p4) — waiting on a question' <<<"$out"; check "herdr blocked is reported" $?
grep -q 'draft (herdr w1:p5) — prompt not empty' <<<"$out"; check "herdr half-typed prompt is reported" $?
grep -q 'self (herdr w1:p6) — this session' <<<"$out"; check "herdr own pane is reported" $?
grep -q 'odd (herdr w1:p8) — state unknown' <<<"$out"; check "herdr unknown state is reported" $?
! grep -q 'codex' <<<"$out"; check "non-Claude agent is not listed" $?
grep -q 'reloaded: 2 · skipped: 5' <<<"$out"; check "herdr summary counts" $?
rm -f "$FAKE/agents" "$FAKE/prompted"

# tmux only
tab=$'\t'
{
  echo "%1${tab}idle:0.0${tab}2.1.302"
  echo "%2${tab}hint:0.0${tab}claude"
  echo "%3${tab}busy:0.0${tab}2.1.302"
  echo "%4${tab}ask:0.0${tab}2.1.302"
  echo "%5${tab}draft:0.0${tab}2.1.302"
  echo "%6${tab}self:0.0${tab}2.1.302"
  echo "%7${tab}shell:0.0${tab}zsh"
} >"$FAKE/panes"
printf '❯ old prompt\n⏺ done\n❯ \n  ⏵⏵ auto mode on\n' >"$FAKE/screen-%1"
printf '❯ Try "how does <filepath> work?"\n' >"$FAKE/screen-%2"
printf '● Percolating… (30s · ↓ 2.5k tokens)\n❯ \n' >"$FAKE/screen-%3"
printf ' Do you want to proceed?\n ❯ 1. Yes\n   2. No\n Esc to cancel\n' >"$FAKE/screen-%4"
printf '❯ \n⏺ answer\n❯ half typed\n' >"$FAKE/screen-%5"
printf '❯ \n' >"$FAKE/screen-%6"
printf '❯ \n' >"$FAKE/screen-%7"

out=$(TMUX_PANE=%6 bash "$here/reload-all.sh")
sent=$(cat "$FAKE/sent" 2>/dev/null)

grep -q -- '-t %1 -l /reload-plugins' <<<"$sent"; check "idle pane gets /reload-plugins" $?
grep -q -- '-t %1 Enter' <<<"$sent"; check "idle pane gets Enter" $?
grep -q -- '-t %2 -l /reload-plugins' <<<"$sent"; check "empty prompt showing a hint counts as idle" $?
for id in %3 %4 %5 %6 %7; do
  ! grep -q -- "-t $id " <<<"$sent"; check "no keys sent to $id" $?
done
grep -q 'busy:0.0 — busy' <<<"$out"; check "busy is reported" $?
grep -q 'ask:0.0 — waiting on a question' <<<"$out"; check "open question is reported" $?
grep -q 'draft:0.0 — prompt not empty' <<<"$out"; check "half-typed prompt is reported" $?
grep -q 'self:0.0 — this session' <<<"$out"; check "own pane is reported" $?
! grep -q 'shell' <<<"$out"; check "non-Claude pane is not listed" $?
grep -q 'reloaded: 2 · skipped: 4' <<<"$out"; check "summary counts" $?

((fails)) && { echo "$fails failed"; exit 1; }
echo "all passed"
