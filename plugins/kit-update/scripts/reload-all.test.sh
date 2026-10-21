#!/usr/bin/env bash
# Self-check for reload-all.sh against a fake tmux: which panes get keys, which are skipped.
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
chmod +x "$FAKE/tmux"
export FAKE KIT_UPDATE_TMUX_BIN="$FAKE/tmux"

fails=0
check() { # $1 = label, $2 = condition result
  if [[ "$2" == 0 ]]; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi
}

# no tmux server
out=$(bash "$here/reload-all.sh")
grep -q 'No tmux server' <<<"$out"; check "no server: says so" $?

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
