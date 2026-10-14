#!/usr/bin/env zsh
# End-to-end test: drives a real interactive zsh inside a pseudo-terminal,
# types into it, and asserts that the plugin shows and accepts suggestions.
#
# Requires TYPESAFE_API_KEY in the environment (it is inherited by the child
# shell, never printed). Run with:  zsh test/e2e.zsh
#
# Set JEV_E2E_KEEP=1 to keep the temp files for inspection.

emulate -L zsh
zmodload zsh/zpty || { print -u2 "zsh/zpty module required"; exit 1 }

if [[ -z $TYPESAFE_API_KEY ]]; then
  print -u2 "TYPESAFE_API_KEY is not set"
  exit 2
fi

local root=${0:A:h:h}
local tmp=$(mktemp -d)
local histfile=$tmp/history
local debuglog=$tmp/debug.log
local failures=0

cleanup() {
  zpty -d sh 2>/dev/null
  if [[ -n $JEV_E2E_KEEP ]]; then
    print "temp files kept in $tmp"
  else
    rm -rf -- "$tmp"
  fi
}
trap cleanup EXIT

# Harmless history: only echo/true commands so accepting a suggestion is safe.
# Newest entries last, exactly as zsh writes them.
cat > "$histfile" <<'EOF'
: 1700000001:0;echo blackbox one
: 1700000002:0;true
: 1700000003:0;echo blackbox two --verbose
: 1700000004:0;echo hello from the moon
: 1700000005:0;echo blackbox three
EOF

# ---------------------------------------------------------------------------
# pty helpers
# ---------------------------------------------------------------------------
typeset -g out=''

drain() {
  local chunk
  while zpty -rt sh chunk 2>/dev/null; do
    out+=$chunk
  done
}

# wait_for PATTERN [TIMEOUT_S]  -- polls the pty until $out matches *PATTERN*
wait_for() {
  local pat=$1 timeout=${2:-15}
  local -F deadline=$((EPOCHREALTIME + timeout))
  while (( EPOCHREALTIME < deadline )); do
    drain
    [[ $out == *${~pat}* ]] && return 0
    sleep 0.1
  done
  return 1
}

# settle SECONDS -- keep draining for a fixed time (used to assert absence)
settle() {
  local -F deadline=$((EPOCHREALTIME + $1))
  while (( EPOCHREALTIME < deadline )); do
    drain
    sleep 0.1
  done
}

type_keys() { zpty -w -n sh "$1" }
press_enter() { zpty -w -n sh $'\r' }
clear_line() { type_keys $'\x15' }   # ^U kill-whole-line

pass() { print "  ok   $1" }
fail() { print "  FAIL $1"; (( failures++ )) }

# strip ANSI/terminal escapes so we can look at the visible text
visible() { print -r -- "${1//$'\e'\[[0-9;?]#[a-zA-Z]/}" }

# ---------------------------------------------------------------------------
# start the shell
# ---------------------------------------------------------------------------
zmodload zsh/datetime
export JEV_DEBUG_LOG=$debuglog
export JEV_SHOW_SCORE=1
export JEV_HIGHLIGHT=''      # no colour codes: easier to assert on
export TERM=xterm

zpty -b sh zsh -f -i
# bindkey -e: the keymap would otherwise depend on the inherited $EDITOR.
zpty -w sh "PS1='%% '; HISTFILE=$histfile; bindkey -e; source $root/zsh/jev-shell-history.plugin.zsh; print READY"
wait_for 'READY' 5 || { print -u2 "shell did not start:"; visible "$out"; exit 1 }
out=''

print "1. prefix mode: 'echo bl' should suggest one of the echo blackbox commands"
type_keys 'echo bl'
if wait_for 'ackbox*\[0.' 20; then
  pass "suggestion with score appeared"
else
  fail "no suggestion appeared"; visible "$out"
fi

print "2. typing along the suggestion keeps it (no new request needed)"
local before=$(grep -c 'jev-shell-history: response' $debuglog 2>/dev/null)
type_keys 'ackbox'
sleep 1.5; drain
local after=$(grep -c 'jev-shell-history: response' $debuglog 2>/dev/null)
if (( after == before )); then
  pass "no extra request while typing along the prefix"
else
  fail "expected no extra request, got $((after - before))"
fi

print "3. accept with right-arrow at end of line and run it"
out=''
type_keys $'\e[C'
sleep 0.3
press_enter
if wait_for $'\nblackbox *' 5 || wait_for $'blackbox (one|two --verbose|three)\r' 5; then
  pass "accepted command executed and printed its output"
else
  fail "command did not run"; visible "$out"
fi

print "4. replace mode: 'moon' (no prefix match) should show ⇢ echo hello from the moon"
out=''
wait_for '%% ' 5
# Switch to vi mode with ^E bound to end-of-line (a common vi-mode setup) so
# that the accept-wrapping is exercised in the viins keymap too.
type_keys "bindkey -v; bindkey '^E' end-of-line"; press_enter
wait_for '%% ' 5; out=''
type_keys 'moon'
if wait_for '⇢ echo hello from the moon' 20; then
  pass "replace-mode suggestion shown"
else
  fail "no replace-mode suggestion"; visible "$out"
fi

print "5. accept replace-mode suggestion with ^E (vi mode, bound to end-of-line) and run it"
out=''
type_keys $'\x05'
sleep 0.3
press_enter
if wait_for $'hello from the moon\r' 5; then
  pass "replace-mode acceptance executed the command"
else
  fail "replace-mode acceptance failed"; visible "$out"
fi

print "6. nonsense input shows nothing"
out=''
wait_for '%% ' 5
type_keys 'xyzzy --frobnicate'
settle 4
if [[ $out != *'⇢'* && $out != *'[0.'* ]]; then
  pass "no suggestion for nonsense"
else
  fail "unexpected suggestion"; visible "$out"
fi
clear_line

print "7. buffer changed while a request is in flight: stale result is discarded"
out=''
type_keys 'echo bl'
sleep 0.15
clear_line
type_keys 'tr'
settle 3
if [[ $out != *'ackbox'* ]]; then
  pass "stale 'echo bl' suggestion never displayed"
else
  fail "stale suggestion leaked"; visible "$out"
fi
clear_line

print "8. zj intent trigger accepts and executes with Enter alone"
out=''
type_keys 'zj print hello from the moon'
if wait_for '⇢ echo hello from the moon' 20; then
  pass "zj intent suggestion shown"
else
  fail "no zj intent suggestion"; visible "$out"
fi
out=''
press_enter
if wait_for $'hello from the moon\r' 5; then
  pass "zj trigger replaced and accepted command executed"
else
  fail "zj acceptance failed"; visible "$out"
fi

print "9. Enter without a zj suggestion keeps the input"
out=''
type_keys 'zj'
press_enter
if wait_for 'zj: wait for a suggestion before pressing Enter' 5; then
  pass "bare zj did not execute"
else
  fail "missing wait message"; visible "$out"
fi
clear_line

zpty -w sh 'exit'
sleep 0.2

if grep -qi 'error\|command not found\|bad option\|no such' $debuglog 2>/dev/null; then
  fail "debug log contains errors:"; cat $debuglog
fi

print
if (( failures == 0 )); then
  print "all e2e checks passed"
else
  print "$failures e2e check(s) failed"
  print -- "--- debug log ---"; cat $debuglog 2>/dev/null
  exit 1
fi
