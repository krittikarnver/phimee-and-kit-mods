#!/usr/bin/env bash
# Self-check for reload-all.sh against a fake tmux and a fake hc: which panes and terminals get keys, which are skipped;
# and for pane-lib.sh's prompt_empty on single input lines and esc on escape codes.
# Run: bash plugins/kit-update/scripts/reload-all.test.sh

set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
FAKE=$(mktemp -d "${TMPDIR:-/tmp}/kit-reload-test.XXXXXX")
trap 'rm -rf "$FAKE"' EXIT
# the herdr-core terminal this runs in must not leak into the runs below
unset HC_TERMINAL_ID TMUX TMUX_PANE

cat >"$FAKE/tmux" <<'EOF'
#!/usr/bin/env bash
# fake tmux: panes from $FAKE/panes, screens from $FAKE/screen-<id> (escape codes only with -e, as tmux), keys logged to $FAKE/sent
case "$1" in
  list-panes) [[ -f "$FAKE/panes" ]] && cat "$FAKE/panes" ;;
  capture-pane) # capture-pane -p [-e] -t ID
    if [[ " $* " == *" -e "* ]]; then cat "$FAKE/screen-${!#}"; else sed $'s/\e\\[[0-9;:]*m//g' "$FAKE/screen-${!#}"; fi ;;
  send-keys) shift; echo "$*" >>"$FAKE/sent" ;;
esac
EOF
cat >"$FAKE/hc" <<'EOF'
#!/usr/bin/env bash
# fake hc: ls --json prints $FAKE/terms (no file = exit 1), get T --json prints $FAKE/hget-T (else a Claude in front;
# exit 1 with $FAKE/getfail-T), send T TEXT logs "T TEXT" to $FAKE/sent-hc (exit 1 with $FAKE/sendfail-T), connect
# (the default screen reader) leaves $FAKE/connected and exits 1; every call logs HC_TERMINAL_ID to $FAKE/hc-env
echo "${HC_TERMINAL_ID-unset}" >>"$FAKE/hc-env"
case "$1" in
  ls) [[ -f "$FAKE/terms" ]] && cat "$FAKE/terms" ;;
  get)
    [[ -f "$FAKE/getfail-$2" ]] && exit 1
    if [[ -f "$FAKE/hget-$2" ]]; then cat "$FAKE/hget-$2"; else echo '{"state":"live","foreground":{"name":"2.1.309","pid":1}}'; fi ;;
  send) [[ -f "$FAKE/sendfail-$2" ]] && exit 1; echo "$2 $3" >>"$FAKE/sent-hc" ;;
  connect) touch "$FAKE/connected"; exit 1 ;;
esac
EOF
cat >"$FAKE/pgrep" <<'EOF'
#!/usr/bin/env bash
# fake pgrep for herdr-core: exit 2 with $FAKE/pgrep-broken, 0 with $FAKE/core-up, else 1
[[ -f "$FAKE/pgrep-broken" ]] && exit 2
[[ -f "$FAKE/core-up" ]]
EOF
cat >"$FAKE/screen" <<'EOF'
#!/usr/bin/env bash
# fake hc-screen.pl: what the reader prints for terminal $1, from $FAKE/hscreen-<t> (no file = unreadable)
cat "$FAKE/hscreen-$1"
EOF
# a hc on PATH is the real one: nothing here may reach it
mkdir "$FAKE/guard"
printf '#!/usr/bin/env bash\necho "$*" >>"$FAKE/real-hc-called"\nexit 1\n' >"$FAKE/guard/hc"
chmod +x "$FAKE/tmux" "$FAKE/hc" "$FAKE/pgrep" "$FAKE/screen" "$FAKE/guard/hc"
export FAKE PATH="$FAKE/guard:$PATH" KIT_UPDATE_TMUX_BIN="$FAKE/tmux" KIT_UPDATE_HC_BIN="$FAKE/hc" \
  KIT_UPDATE_PGREP_BIN="$FAKE/pgrep" KIT_UPDATE_SCREEN_BIN="$FAKE/screen"
touch "$FAKE/core-up"

fails=0
check() { # $1 = label, $2 = condition result
  if [[ "$2" == 0 ]]; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi
}

# pane-lib: prompt_empty, in this locale and in C (a tmux server started without LANG has no UTF-8 locale).
# Claude Code 2.1.309's input line: tmux 3.8 capture-pane -e writes ESC[39m ❯ NBSP <typed>, a herdr-core first paint
# ❯ NBSP ESC[0m ESC[2m <suggestion> ESC[0m \r. The tmux suggestion is built the same way (none captured yet).
source "$here/pane-lib.sh"
pe() { # LABEL empty|draft LINE
  local loc r
  for loc in '' C; do
    (if [[ -n "$loc" ]]; then export LC_ALL=$loc; fi; prompt_empty "$3"); r=$?
    [[ ("$2" == empty && $r == 0) || ("$2" == draft && $r == 1) ]]; check "prompt_empty${loc:+ (LC_ALL=$loc)}: $1" $?
  done
}
e=$'\e' nb=$'\xc2\xa0' sg='คำรหัสของ session นี้คืออะไร'
pe "tmux empty line behind its colour code" empty "$e[39m❯$nb"
pe "tmux typed line behind its colour code" draft "$e[39m❯${nb}abc"
pe "tmux suggestion" empty "$e[39m❯$nb$e[2m$sg$e[0m"
pe "hc suggestion" empty "❯$nb$e[0m$e[2m$sg$e[0m"$'\r'
pe "dim set by a combined 0;2" empty "$e[39m❯$nb$e[0;2m$sg$e[0m"
pe "typed after 22 ends the dim" draft "$e[39m❯$nb$e[2m$sg$e[22mabc"
pe "typed after a dim run" draft "$e[39m❯$nb$e[2m$sg$e[0m abc"

# esc: two-character escapes (the reset a first paint starts with) go too, while CSI and OSC stay with their own rules
for loc in '' C; do
  got=$(if [[ -n "$loc" ]]; then export LC_ALL=$loc; fi; screen_awk '{ print esc($0) }' <<<$'\e[?1l\e>\e(B\e[9G\eH\e[17G\eHtext\e7\e8')
  [[ "$got" == text ]]; check "esc drops two-character escapes${loc:+ (LC_ALL=$loc)}" $?
done
got=$(screen_awk '{ print esc($0) }' <<<$'\e[!p\e[=0;1u\e[3g\e]7;file://h/x\e\\text\e]2;t\a\e[1m')
[[ "$got" == text ]]; check "esc still drops CSI and ST- or BEL-terminated OSC" $?

# neither tmux nor herdr-core
out=$(bash "$here/reload-all.sh")
grep -q 'No tmux or herdr-core server' <<<"$out"; check "no server: says so" $?

# herdr-core only
live='"agent":"claude-code","state":"live"'
jq -sc '{terminals: .}' >"$FAKE/terms" <<EOF
{"address":"t1",$live,"status":"idle","name":"alpha","cwd":"/x/alpha"}
{"address":"t2",$live,"status":"done","where":"beta / 1","cwd":"/x/beta"}
{"address":"t3",$live,"status":"working","cwd":"/x/busy"}
{"address":"t4",$live,"status":"blocked","cwd":"/x/ask"}
{"address":"t5",$live,"status":"idle","cwd":"/x/draft"}
{"address":"t6",$live,"status":"idle","cwd":"/x/self"}
{"address":"t7","agent":"zsh","state":"live","cwd":"/x/shell"}
{"address":"t8",$live,"status":"error","cwd":"/x/err"}
{"address":"t9",$live,"status":"idle","cwd":"/x/paint"}
{"address":"t10",$live,"cwd":"/x/spin"}
{"address":"t11",$live,"status":"idle","cwd":"/x/typed"}
{"address":"t12",$live,"status":"idle","cwd":"/x/nofile"}
{"address":"t13","agent":"claude-code","state":"finished","status":"done","cwd":"/x/gone"}
{"address":"m1/t3",$live,"status":"idle","cwd":"/x/slash"}
{"address":"t14",$live,"status":"idle","where":"","cwd":"/x/gamma"}
{"address":"t15",$live,"status":"idle","cwd":"/x/sendfail"}
{"address":"t16",$live,"status":"idle","cwd":"/x/blank"}
{"address":"t17",$live,"status":"idle","cwd":"/x/pad"}
{"address":"t18",$live,"status":"done","cwd":"/x/front"}
EOF
printf '⏺ done\n❯ \n  ⏵⏵ auto mode on\n' >"$FAKE/hscreen-t1"
printf '❯ Try "how does <filepath> work?"\n' >"$FAKE/hscreen-t2"
printf '❯ \n⏺ answer\n❯ half typed\n' >"$FAKE/hscreen-t5"
for t in t6 t8 t14 t15 t18; do printf '❯ \n' >"$FAKE/hscreen-$t"; done
# a first paint as hc-screen.pl prints it: the reset codes stick to the first row, the suggestion is dim, no \r
printf '\e[?1l\e>\e(B\e[H\e[2J\e[9G\eH\e[17G\eH⏺ done\n\n❯\xc2\xa0\e[0m\e[2mคำรหัสของ session นี้คืออะไร\e[0m\n' >"$FAKE/hscreen-t9"
printf '✻ Percolating… (esc to interrupt)\n❯ \n' >"$FAKE/hscreen-t10"
printf '❯\xc2\xa0\e[38;5;2mhalf typed\e[39m\n' >"$FAKE/hscreen-t11" # colour 2 (green) is not dim
: >"$FAKE/hscreen-t16" # read fine, nothing on it
{ printf '❯\xc2\xa0\n'; for i in {1..20}; do printf '\e[0m\xc2\xa0\n'; done; } >"$FAKE/hscreen-t17" # blank lines
touch "$FAKE/sendfail-t15"
printf '{"state":"live","foreground":{"name":"tmux","pid":2}}\n' >"$FAKE/hget-t18"

out=$(HC_TERMINAL_ID=t6 bash "$here/reload-all.sh")
sent=$(cat "$FAKE/sent-hc" 2>/dev/null)

! grep -q 'No tmux or herdr-core server' <<<"$out"; check "hc only: no 'no server' message" $?
for t in t1 t2 t8 t9 t14 t17; do
  grep -qx "$t /reload-plugins" <<<"$sent"; check "hc $t gets /reload-plugins" $?
done
for t in t3 t4 t5 t6 t7 t10 t11 t12 t13 m1/t3 t15 t16 t18; do
  ! grep -q "^$t " <<<"$sent"; check "no text sent to hc $t" $?
done
grep -q 'alpha (hc t1)' <<<"$out"; check "hc terminal shown by its name" $?
grep -q 'beta / 1 (hc t2)' <<<"$out"; check "hc terminal shown by where without a name" $?
grep -q 'gamma (hc t14)' <<<"$out"; check "hc empty where counts as none: shown by its folder" $?
grep -q 'busy (hc t3) — busy' <<<"$out"; check "hc working is reported busy" $?
grep -q 'ask (hc t4) — waiting on a question' <<<"$out"; check "hc blocked is reported" $?
grep -q 'draft (hc t5) — prompt not empty or not found' <<<"$out"; check "hc half-typed prompt is reported" $?
grep -q 'self (hc t6) — this session' <<<"$out"; check "hc own terminal is reported" $?
grep -q 'spin (hc t10) — busy' <<<"$out"; check "hc without a status: the screen says busy" $?
grep -q 'typed (hc t11) — prompt not empty' <<<"$out"; check "hc typed (not dim) text is a draft" $?
grep -q 'nofile (hc t12) — screen unreadable' <<<"$out"; check "hc unreadable screen is reported" $?
grep -q 'sendfail (hc t15) — hc send failed' <<<"$out"; check "hc send failure is reported" $?
grep -q 'blank (hc t16) — prompt not empty or not found' <<<"$out"; check "hc screen that reads but holds nothing is not idle" $?
grep -q 'front (hc t18) — Claude Code is not in front (tmux)' <<<"$out"; check "hc terminal with tmux in front is reported" $?
! grep -qE 'shell|gone|slash' <<<"$out"; check "hc non-Claude, finished and nested terminals are not listed" $?
grep -q 'reloaded: 6 · skipped: 10' <<<"$out"; check "hc summary counts" $?
[[ -s "$FAKE/hc-env" ]] && ! grep -qvx unset "$FAKE/hc-env"; check "hc never sees HC_TERMINAL_ID" $?
rm -f "$FAKE/sent-hc" "$FAKE/hc-env"

# when hc may be called at all (pgrep finds herdr-core or not); the terminals above are still listed
rm "$FAKE/core-up"
out=$(bash "$here/reload-all.sh")
grep -q 'No tmux or herdr-core server' <<<"$out"; check "no core: says so" $?
! test -e "$FAKE/hc-env"; check "no core: hc never called" $?
out=$(HC_TERMINAL_ID=t6 bash "$here/reload-all.sh")
! test -e "$FAKE/hc-env"; check "core down, HC_TERMINAL_ID set outside tmux: hc never called" $?
out=$(HC_TERMINAL_ID=t6 TMUX=/x/tmux,1,0 bash "$here/reload-all.sh")
! test -e "$FAKE/hc-env"; check "stale HC_TERMINAL_ID inside tmux: hc never called" $?
touch "$FAKE/pgrep-broken"
out=$(HC_TERMINAL_ID=t6 bash "$here/reload-all.sh")
grep -q 'self (hc t6) — this session' <<<"$out" && grep -q 'reloaded: 6 · skipped: 10' <<<"$out"; check "pgrep unusable, HC_TERMINAL_ID set: still lists" $?
out=$(HC_TERMINAL_ID=t6 KIT_UPDATE_PGREP_BIN="$FAKE/no-such-pgrep" bash "$here/reload-all.sh")
grep -q 'self (hc t6) — this session' <<<"$out" && grep -q 'reloaded: 6 · skipped: 10' <<<"$out"; check "no pgrep, HC_TERMINAL_ID set: still lists" $?
rm -f "$FAKE/hc-env"
out=$(bash "$here/reload-all.sh")
! test -e "$FAKE/hc-env"; check "pgrep unusable, no HC_TERMINAL_ID: hc never called" $?
rm -f "$FAKE/pgrep-broken" "$FAKE/sent-hc"
touch "$FAKE/core-up"
out=$(HC_TERMINAL_ID=t6 TMUX=/x/tmux,1,0 bash "$here/reload-all.sh")
! grep -q 'this session' <<<"$out"; check "HC_TERMINAL_ID inside tmux, core up: t6 is not this session" $?
grep -qx 't6 /reload-plugins' "$FAKE/sent-hc"; check "HC_TERMINAL_ID inside tmux, core up: t6 is reloaded" $?

# hc get fails
printf '{"terminals":[{"address":"t1",%s,"status":"idle","cwd":"/x/alpha"}]}\n' "$live" >"$FAKE/terms"
rm -f "$FAKE/sent-hc"
touch "$FAKE/getfail-t1"
out=$(bash "$here/reload-all.sh")
grep -q 'alpha (hc t1) — herdr-core does not answer' <<<"$out"; check "hc get failure is reported" $?
! test -e "$FAKE/sent-hc"; check "hc get failure: nothing sent" $?
rm -f "$FAKE/getfail-t1"

# the default reader (hc-screen.pl) runs against the fake hc; its failure is an unreadable screen
rm -f "$FAKE/hc-env"
out=$(env -u KIT_UPDATE_SCREEN_BIN bash "$here/reload-all.sh")
test -e "$FAKE/connected"; check "default reader: runs hc-screen.pl against KIT_UPDATE_HC_BIN" $?
grep -q 'alpha (hc t1) — screen unreadable' <<<"$out"; check "default reader: its failure is unreadable" $?
rm -f "$FAKE/terms" "$FAKE/sent-hc" "$FAKE/hc-env"

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
  echo "%8${tab}sugg:0.0${tab}2.1.309"
  echo "%9${tab}typed:0.0${tab}2.1.309"
  echo "%10${tab}spin:0.0${tab}2.1.309"
} >"$FAKE/panes"
printf '❯ old prompt\n⏺ done\n❯ \n  ⏵⏵ auto mode on\n' >"$FAKE/screen-%1"
printf '❯ Try "how does <filepath> work?"\n' >"$FAKE/screen-%2"
printf '● Percolating… (30s · ↓ 2.5k tokens)\n❯ \n' >"$FAKE/screen-%3"
printf ' Do you want to proceed?\n ❯ 1. Yes\n   2. No\n Esc to cancel\n' >"$FAKE/screen-%4"
printf '❯ \n⏺ answer\n❯ half typed\n' >"$FAKE/screen-%5"
printf '❯ \n' >"$FAKE/screen-%6"
printf '❯ \n' >"$FAKE/screen-%7"
# tmux -e bytes of the input line: ESC[39m ❯ NBSP, then a suggested prompt (dim) or typed text
printf '⏺ done\n\e[39m❯\xc2\xa0\e[2mคำรหัสของ session นี้คืออะไร\e[0m\n' >"$FAKE/screen-%8"
printf '\e[39m❯\xc2\xa0\e[38;2;2;90;200mhalf typed\e[39m\n' >"$FAKE/screen-%9" # red 2 of a true colour is not dim
printf '✻ Percolating… \e[2m(esc to \e[1minterrupt)\e[0m\n\e[39m❯\xc2\xa0\e[2mคำรหัส\e[0m\n' >"$FAKE/screen-%10" # dim busy line

out=$(TMUX_PANE=%6 LC_ALL=C bash "$here/reload-all.sh") # C: as in a tmux server started without LANG
sent=$(cat "$FAKE/sent" 2>/dev/null)

grep -q -- '-t %1 -l /reload-plugins' <<<"$sent"; check "idle pane gets /reload-plugins" $?
grep -q -- '-t %1 Enter' <<<"$sent"; check "idle pane gets Enter" $?
grep -q -- '-t %2 -l /reload-plugins' <<<"$sent"; check "empty prompt showing a hint counts as idle" $?
grep -q -- '-t %8 -l /reload-plugins' <<<"$sent"; check "dim suggestion in the prompt counts as idle" $?
for id in %3 %4 %5 %6 %7 %9 %10; do
  ! grep -q -- "-t $id " <<<"$sent"; check "no keys sent to $id" $?
done
grep -q 'busy:0.0 — busy' <<<"$out"; check "busy is reported" $?
grep -q 'ask:0.0 — waiting on a question' <<<"$out"; check "open question is reported" $?
grep -q 'draft:0.0 — prompt not empty' <<<"$out"; check "half-typed prompt is reported" $?
grep -q 'self:0.0 — this session' <<<"$out"; check "own pane is reported" $?
grep -q 'typed:0.0 — prompt not empty' <<<"$out"; check "typed (not dim) text is a draft" $?
grep -q 'spin:0.0 — busy' <<<"$out"; check "dim 'esc to interrupt' still reads busy" $?
! grep -q 'shell' <<<"$out"; check "non-Claude pane is not listed" $?
grep -q 'reloaded: 3 · skipped: 6' <<<"$out"; check "summary counts" $?

! test -e "$FAKE/real-hc-called"; check "the real hc is never called" $?

((fails)) && { echo "$fails failed"; exit 1; }
echo "all passed"
