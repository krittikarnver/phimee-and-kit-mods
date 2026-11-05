#!/usr/bin/perl
# hc-screen.pl TERMINAL
#
# Print what a herdr-core terminal shows right now, escape codes included (colours, dim text), one row per line
# with \r and NUL dropped, and exit 0. Callers read the codes to tell a dim prompt suggestion from text a person
# typed. NUL goes because the first paint has one inside an OSC 7 (before its ST) and awk cuts a line at a NUL,
# which would leave half an escape sequence that cannot be stripped.
# On any failure (no answer in 5 s, rpc error, hc closes, malformed frame) print nothing and exit 1: a screen that
# is incomplete, late or unreadable is never printed, because guessing what is on it could mean typing into a
# live session.
#
# Why perl: `hc read` strips the codes, and `hc connect` speaks binary frames over a two-way pipe, which bash
# cannot read; perl ships with macOS and Linux, and its core modules are enough.
#
# Env: KIT_UPDATE_HC_BIN = the hc binary (default hc).
#
# Protocol (herdr-core schema/README.md): a frame is channel u32 LE, kind u8 (0 DATA, 1 CREDIT, 2 CLOSE), len u32 LE,
# payload. Channel 0 carries JSON-RPC (after the hello reply, which is a bare line): hc 0.1.18 sends one message per
# frame with no newline, but the schema says JSON lines, so we parse the joined channel-0 bytes incrementally and
# accept any mix: one per frame, several back to back in a frame, one split across frames, newline separated.
# We attach with observe:true, which types nothing and resizes nothing, and the only thing we ever send on the
# attach channel is CLOSE. The first paint is 0x18, the screen, ESC[?9001h or ESC[?9001l, then live bytes. We send
# no CREDIT (its payload format is not documented): the window starts at 256 KiB, so a bigger first paint
# times out, which counts as unreadable.

use strict;
use warnings;
use IPC::Open2;
use JSON::PP ();

use constant { TIMEOUT => 5, MAX_FRAME => 16 * 1024 * 1024, DATA => 0, CLOSE => 2 };

my $term = shift // exit 1;
my $json = JSON::PP->new->canonical;
# shortcut: JSON::PP 4.06's incr_parse spins forever on a message cut off right after a digit; the 5 s alarm turns
# that into exit 1. Replies are single frames of about 1 KB, so a cut like that needs a reply over one 16 KiB frame.
my $chan0 = JSON::PP->new;    # incremental parser for channel 0
my ($from, $to, $pid);
my $in = '';    # bytes read from hc connect, not yet parsed. Always sysread, never <$from>: a PerlIO buffer
                # would hide the bytes after the hello line from sysread.

sub reap {      # also safe when open2 never started
    alarm 0;
    return unless $pid;
    close $to;
    kill 'KILL', $pid;
    waitpid $pid, 0;
    $pid = 0;
}

sub fill { sysread($from, $in, 65536, length $in) or die "eof\n" }

sub send_frame {
    my ($ch, $kind, $payload) = @_;
    defined syswrite($to, pack('VCV', $ch, $kind, length $payload) . $payload) or die "write\n";
}

sub rpc {
    my ($id, $method, $params) = @_;
    my $msg = $json->encode({ jsonrpc => '2.0', id => $id, method => $method, params => $params });
    send_frame(0, DATA, "$msg\n");
}

sub next_frame {
    fill() while length $in < 9;
    my ($ch, $kind, $len) = unpack 'VCV', $in;
    die "frame too big\n" if $len > MAX_FRAME;
    fill() while length $in < 9 + $len;
    my $payload = substr($in, 9, $len);
    substr($in, 0, 9 + $len) = '';
    return ($ch, $kind, $payload);
}

sub read_screen {
    # hello is a bare JSON line, not a frame; whatever follows it is the start of the first frame.
    defined syswrite($to, qq({"jsonrpc":"2.0","id":0,"method":"hello","params":{"framed":true}}\n)) or die "write\n";
    fill() until $in =~ /\n/;
    $in =~ s/^([^\n]*)\n// or die;
    my $hello = $1;
    exists $json->decode($hello)->{result} or die "no hello\n";

    my (%data, $cols, $rows, $chan);
    my $waiting = 1;    # id of the reply we want next: 1 terminal.get, 2 terminal.attach, 0 none
    rpc(1, 'terminal.get', { terminal => $term });
    while (1) {
        my ($ch, $kind, $payload) = next_frame();
        die "closed\n" if $kind == CLOSE;
        next unless $kind == DATA;
        if ($ch) {
            $data{$ch} .= $payload;    # may arrive before the attach reply says which channel is ours
        } else {
            $chan0->incr_parse($payload);
            while (defined(my $msg = $chan0->incr_parse)) {
                next unless ref $msg eq 'HASH' && $waiting && defined $msg->{id} && $msg->{id} eq $waiting;
                die "rpc error\n" if defined $msg->{error};
                if ($waiting == 1) {
                    ($cols, $rows) = @{ $msg->{result} }{qw(cols rows)};
                    die "bad size\n" unless ($cols // '') =~ /^\d+$/ && ($rows // '') =~ /^\d+$/;
                    rpc(2, 'terminal.attach',
                        { terminal => $term, cols => $cols + 0, rows => $rows + 0, observe => JSON::PP::true });
                    $waiting = 2;
                } else {
                    $chan = $msg->{result}{channel};
                    die "bad channel\n" unless ($chan // '') =~ /^[1-9]\d*$/;
                    $waiting = 0;
                }
            }
        }
        # Look for the end mark in the joined bytes: it can be cut between frames.
        next unless defined $chan && ($data{$chan} // '') =~ /\e\[\?9001[hl]/;
        alarm 0;    # the screen is complete: a slow hc from here on must not make us throw it away
        my $head = substr($data{$chan}, 0, $-[0]);
        my $start = index($head, "\x18");
        die "no start\n" if $start < 0;
        syswrite($to, pack('VCV', $chan, CLOSE, 0));    # best effort, we kill hc right after anyway
        return substr($head, $start + 1);
    }
}

$SIG{PIPE} = 'IGNORE';    # an hc that exited early must give exit 1, not death by SIGPIPE
$SIG{ALRM} = sub { reap(); exit 1 };
delete $ENV{HC_TERMINAL_ID};    # hc would wrap what it sends as a message from this terminal
my $screen = eval {
    $pid = open2($from, $to, $ENV{KIT_UPDATE_HC_BIN} || 'hc', 'connect');
    alarm TIMEOUT;
    read_screen();
};
reap();
exit 1 unless defined $screen;
$screen =~ tr/\r\0//d;
$screen .= "\n" if length $screen && substr($screen, -1) ne "\n";
print $screen;
