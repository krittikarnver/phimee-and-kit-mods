#!/usr/bin/env bash
# Self-check for hc-screen.pl against a fake `hc connect` that speaks herdr-core's framed protocol: what it asks for,
# what it prints, and that it prints nothing and exits 1 whenever the screen is not complete.
# Run: bash plugins/kit-update/scripts/hc-screen.test.sh (~6 s, the time-out case waits out the 5 s alarm)

set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
FAKE=$(mktemp -d "${TMPDIR:-/tmp}/kit-hc-screen-test.XXXXXX")
trap 'rm -rf "$FAKE"' EXIT
unset HC_TERMINAL_ID TMUX TMUX_PANE

# The real hc must never run: the reader gets the fake through KIT_UPDATE_HC_BIN, and this one only records a stray call.
mkdir "$FAKE/guard"
printf '#!/usr/bin/env bash\necho "$*" >>"$FAKE/real-hc-called"\nexit 1\n' >"$FAKE/guard/hc"
chmod +x "$FAKE/guard/hc"
export PATH="$FAKE/guard:$PATH"

cat >"$FAKE/hc" <<'EOF'
#!/usr/bin/perl
# fake `hc connect`: scenario from $FAKE/scenario, screen from $FAKE/paint (or paint-big). Logs to $FAKE/log: the env,
# each JSON-RPC line it receives, other frames as "<KIND> <channel>", and "eof" when its stdin closes. After its
# scripted output it hangs, as a real hc would; a forked logger keeps reading so the log still gets what the reader
# sends just before it kills us (the reader does not wait for hc to answer its CLOSE).
use strict; use warnings;
exit 2 unless ($ARGV[0] // '') eq 'connect';
my $F = $ENV{FAKE};
open my $log, '>>', "$F/log" or die; select((select($log), $| = 1)[0]);
sub slurp { open my $h, '<', $_[0] or die; binmode $h; local $/; <$h> }
my $sc = slurp("$F/scenario"); chomp $sc;
print $log 'env HC_TERMINAL_ID=', $ENV{HC_TERMINAL_ID} // 'unset', "\n";
exit 0 if $sc eq 'exitnow';

sub frame { my ($ch, $kind, $p) = @_; pack('VCV', $ch, $kind, length $p) . $p }
sub out { syswrite(STDOUT, join '', @_) }
my $in = '';
sub fill { sysread(STDIN, $in, 65536, length $in) or do { print $log "eof\n"; exit 0 } }
sub next_line { fill() until $in =~ /\n/; $in =~ s/^([^\n]*)\n//; $1 }
sub next_frame {
  fill() while length $in < 9;
  my ($ch, $kind, $len) = unpack 'VCV', $in;
  fill() while length $in < 9 + $len;
  my $p = substr($in, 9, $len);
  substr($in, 0, 9 + $len) = '';
  ($ch, $kind, $p);
}
sub log_frame { my ($ch, $kind) = @_; my $name = (qw(DATA CREDIT CLOSE))[$kind] // "KIND$kind"; print $log "$name $ch\n" }
sub hang {
  if (fork == 0) { while (1) { my ($ch, $kind) = next_frame(); log_frame($ch, $kind) } }
  sleep 20;
  exit 0;
}

my $note = '{"jsonrpc":"2.0","method":"server.heartbeat","params":{}}' . "\n";
my $hello = '{"jsonrpc":"2.0","id":0,"result":{"framed":true}}' . "\n";
my $get = '{"jsonrpc":"2.0","id":1,"result":{"cols":123,"rows":45}}' . "\n";
my $attach = '{"jsonrpc":"2.0","id":2,"result":{"channel":5}}' . "\n";
my $tail = "\e[?9001l\e]7501;1;1\a" . 'live bytes';
my $paint = slurp($sc eq 'split' ? "$F/paint-big" : "$F/paint");

print $log next_line(), "\n";
close STDIN if $sc eq 'gone';   # hc quits right after the hello reply: the reader's next write has nobody to read it
out($hello, $sc eq 'split' ? frame(0, 0, $note) : ());   # one write: the reader must keep the bytes after the hello line
exit 0 if $sc eq 'gone';
while (1) {
  my ($ch, $kind, $p) = next_frame();
  unless ($kind == 0 && $ch == 0) { log_frame($ch, $kind); next }
  for my $line (split /\n/, $p) {
    print $log "$line\n";
    if ($line =~ /terminal\.get/) {
      if ($sc eq 'rpcerror') {
        out(frame(0, 0, '{"jsonrpc":"2.0","id":1,"error":{"code":-32004,"message":"not_found"}}' . "\n"));
        hang();
      }
      out(frame(0, 3, "\0" x 8), frame(0, 0, $note)) if $sc eq 'split';   # RESIZE and a notification before the reply
      if ($sc eq 'split') { out(frame(0, 0, substr($get, 0, 20))); out(frame(0, 0, substr($get, 20))) }
      else { out(frame(0, 0, $get)) }
    } elsif ($line =~ /terminal\.attach/) {
      if ($sc eq 'early') {
        out(frame(7, 0, "\x18DECOY\e[?9001l"), frame(5, 0, $paint . $tail), frame(0, 0, $attach));
      } elsif ($sc eq 'split') {
        out(frame(0, 0, $note . $attach));
        out(frame(5, 0, substr($paint, 0, 16384, ''))) while length $paint > 16384;
        out(frame(5, 0, $paint . "\e[?9001h" . 'live bytes'));
      } elsif ($sc eq 'splitmark') {
        out(frame(0, 0, $attach), frame(5, 0, $paint . "\e[?90"), frame(5, 0, '01l' . 'live bytes'));
      } elsif ($sc eq 'oversized') {
        out(frame(0, 0, $attach), pack('VCV', 5, 0, 16777217));
      } elsif ($sc eq 'closebefore') {
        out(frame(0, 0, $attach), frame(5, 0, "\x18partial"), frame(5, 2, ''));
      } elsif ($sc eq 'timeout') {
        out(frame(0, 0, $attach), frame(5, 0, $paint));   # a screen but no end mark
      } else {
        out(frame(0, 0, $attach), frame(5, 0, $paint . $tail));
      }
      hang();
    }
  }
}
EOF
chmod +x "$FAKE/hc"
export FAKE KIT_UPDATE_HC_BIN="$FAKE/hc"

# sample screens: \x18, then rows ending in \r\n (the reader's own end mark and live bytes are added by the fake)
printf '\x18\e[?1l\e>\e(B\e[H\e[2J\e[9G\eH\e[17G\eH⏺ done\r\n\r\n❯\xc2\xa0\e[0m\e[2mคำรหัสของ session นี้คืออะไร\e[0m\r\n' >"$FAKE/paint"
/usr/bin/perl -e 'print "\x18"; print "\e[3", $_ % 8, "mrow$_ ", "x" x 200, "\e[0m\r\n" for 1 .. 200' >"$FAKE/paint-big"
tail -c +2 "$FAKE/paint" | LC_ALL=C tr -d '\r' >"$FAKE/expected"
tail -c +2 "$FAKE/paint-big" | LC_ALL=C tr -d '\r' >"$FAKE/expected-big"

fails=0
check() { # $1 = label, $2 = condition result
  if [[ "$2" == 0 ]]; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi
}

rc=0
run() { # $1 = scenario; leaves the exit code in $rc, stdout in $FAKE/out, the fake's log in $FAKE/log
  echo "$1" >"$FAKE/scenario"
  : >"$FAKE/log"
  HC_TERMINAL_ID=t9 perl "$here/hc-screen.pl" t1 >"$FAKE/out"
  rc=$?
  [[ "$1" == exitnow || "$1" == gone ]] && return
  local i # the fake logs "eof" once the reader has closed its stdin
  for i in $(seq 50); do grep -qx eof "$FAKE/log" && return; sleep 0.1; done
}
printed() { [[ $rc == 0 ]] && cmp -s "$FAKE/$1" "$FAKE/out" && ! grep -q 'live bytes' "$FAKE/out"; }
nothing() { [[ $rc == 1 && ! -s "$FAKE/out" ]]; }

run normal
printed expected; check "ok: prints the screen without \\r" $?
att=$(grep 'terminal\.attach' "$FAKE/log")
grep -q '"observe":true' <<<"$att" && grep -q '"cols":123' <<<"$att" && grep -q '"rows":45' <<<"$att" && grep -q '"terminal":"t1"' <<<"$att"
check "attach asks observe true with the size from terminal.get" $?
grep -qx 'env HC_TERMINAL_ID=unset' "$FAKE/log"; check "connect runs without HC_TERMINAL_ID" $?
grep -qx 'CLOSE 5' "$FAKE/log" && ! grep -qE '^(DATA|CREDIT) 5$' "$FAKE/log"
check "closes its channel when done, sends nothing else on it" $?

run split
printed expected-big; check "screen split over frames, live bytes after the mark" $?
run splitmark
printed expected; check "end mark split across frames" $?
run early
printed expected; check "screen arrives before the attach reply" $?
run rpcerror
nothing; check "rpc error: exit 1, no output" $?
run oversized
nothing; check "oversized frame header: exit 1, no output" $?
run closebefore
nothing; check "CLOSE before the mark: exit 1, no output" $?
run exitnow
nothing; check "connect exits at once: exit 1, no output" $?
run gone
nothing; check "connect exits after hello: exit 1 (not SIGPIPE), no output" $?

start=$SECONDS
run timeout
elapsed=$((SECONDS - start))
for i in 1 2 3 4 5; do pgrep -f "$FAKE/hc" >/dev/null || break; sleep 0.2; done
nothing && ((elapsed <= 8)) && ! pgrep -f "$FAKE/hc" >/dev/null
check "no end mark within 5 s: exit 1, no output, fake killed" $?

[[ ! -e "$FAKE/real-hc-called" ]]; check "the real hc was never called" $?

((fails)) && { echo "$fails failed"; exit 1; }
echo "all passed"
