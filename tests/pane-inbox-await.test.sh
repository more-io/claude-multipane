#!/usr/bin/env bash
# Tests for bin/pane-inbox-await: target validation, the single-instance lock,
# mail detection and the quiet timeout.
#
# Runs against a LIVE tmux server (it needs real pane targets to accept and
# reject) but never touches the real mailbox or lock dir: PANE_MSG_HOME and
# PANE_INBOX_AWAIT_STATE point into a temp dir. It picks a live pane that has
# NO watcher running on it, so an orchestrator's real watcher is never counted
# or killed.
#
#   tests/pane-inbox-await.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
AWAIT="$HERE/../bin/pane-inbox-await"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export PANE_MSG_HOME="$TMP/mailbox"
export PANE_INBOX_AWAIT_STATE="$TMP/state"
export PANE_INBOX_AWAIT_SESSIONS="$TMP/sessions"
export PANE_INBOX_AWAIT_PANES_CONF="$TMP/panes.conf"
mkdir -p "$PANE_MSG_HOME" "$PANE_INBOX_AWAIT_SESSIONS"

pass=0; fail=0
ok()   { pass=$((pass+1)); echo "  ok   $*"; }
bad()  { fail=$((fail+1)); echo "  FAIL $*"; }
check() { # check <description> <condition...>
  local d="$1"; shift
  if "$@"; then ok "$d"; else bad "$d"; fi
}

tmux list-panes -a >/dev/null 2>&1 || { echo "no tmux server — cannot test"; exit 1; }

# A live pane with no watcher on it (real or legacy), so the lock tests start
# from a clean slate and never disturb a real watcher.
target=""
while read -r t; do
  pgrep -f "pane-inbox-await.* ${t//./\\.}\$" >/dev/null 2>&1 || { target="$t"; break; }
done < <(tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}')
[ -n "$target" ] || { echo "every live pane already has a watcher — cannot test"; exit 1; }
session="${target%%:*}"
key="$(printf '%s' "$target" | tr ':.' '__')"
pidfile="$PANE_INBOX_AWAIT_STATE/pane-inbox-await.$key.pid"
echo "using live target $target"

# --- target validation ------------------------------------------------------
echo "validation"
out="$("$AWAIT" "$session:paneX" 2>&1)"; rc=$?
check "session-name form is rejected (rc=2)" [ "$rc" -eq 2 ]
check "rejection names the live panes" grep -q "$target" <<<"$out"
check "no pid file written on rejection" [ ! -e "$PANE_INBOX_AWAIT_STATE/pane-inbox-await.${session}_paneX.pid" ]

out="$("$AWAIT" "$session" 2>&1)"; rc=$?
check "bare session name is rejected (tmux would resolve it to the caller)" [ "$rc" -eq 2 ]

out="$("$AWAIT" "${target}x" 2>&1)"; rc=$?
check "near-miss '${target}x' is rejected (tmux resolves it to the caller)" [ "$rc" -eq 2 ]

# A registry entry mapping a session name to the target's pane id → suggestion.
pane_id="$(tmux display-message -p -t "$target" '#{pane_id}')"
window_id="$(tmux display-message -p -t "$target" '#{window_id}')"
cat > "$PANE_INBOX_AWAIT_SESSIONS/$$.json" <<EOF
{"pid": $$, "kind": "interactive", "name": "proj:pane9", "tmux": "$session:$window_id.$pane_id"}
EOF
out="$("$AWAIT" "proj:pane9" 2>&1)"; rc=$?
check "registry name is rejected" [ "$rc" -eq 2 ]
check "registry name maps to its tmux target" grep -q "Did you mean: $target" <<<"$out"

# A paneN shorthand resolved through panes.conf.
prefix="${target%.*}"; n="${target##*.}"
printf '%s\n' "# comment" "proj /tmp/x main 6 $prefix" > "$PANE_INBOX_AWAIT_PANES_CONF"
out="$("$AWAIT" "pane$n" 2>&1)"; rc=$?
check "paneN shorthand is rejected" [ "$rc" -eq 2 ]
check "paneN shorthand maps through panes.conf" grep -q "Did you mean: $target" <<<"$out"

# --- lock -------------------------------------------------------------------
echo "lock"
"$AWAIT" --timeout 30 --interval 1 "$target" > "$TMP/first.out" 2>&1 &
first=$!
sleep 1
check "first watcher writes its pid file" [ "$(cat "$pidfile" 2>/dev/null)" = "$first" ]
out="$("$AWAIT" --timeout 30 "$target" 2>&1)"; rc=$?
check "second start exits 0" [ "$rc" -eq 0 ]
check "second start reports the lock" grep -q "already armed for $target (pid $first)" <<<"$out"
check "first watcher still runs" kill -0 "$first"
kill -TERM "$first"; wait "$first" 2>/dev/null
check "pid file removed after TERM" [ ! -e "$pidfile" ]

printf '%s\n' "999999" > "$pidfile"
"$AWAIT" --timeout 30 --interval 1 "$target" > "$TMP/stale.out" 2>&1 &
second=$!
sleep 1
check "stale pid file (dead owner) is taken over" [ "$(cat "$pidfile" 2>/dev/null)" = "$second" ]
kill -TERM "$second"; wait "$second" 2>/dev/null

# --- mail and timeout -------------------------------------------------------
echo "mail / timeout"
"$AWAIT" --timeout 30 --interval 1 "$target" > "$TMP/mail.out" 2>&1 &
third=$!
sleep 1
printf '%s\n' '{"from":"test","to":"'"$target"'","type":"note","ts":"2026-01-01T00:00:00Z","body":"hi"}' >> "$PANE_MSG_HOME/$key.inbox.jsonl"
wait "$third"; rc=$?
check "exits 0 when mail lands" [ "$rc" -eq 0 ]
check "reports the unread count" grep -q "1 unread message(s) waiting for $target" "$TMP/mail.out"
check "pid file removed after mail" [ ! -e "$pidfile" ]

printf '%s' "1" > "$PANE_MSG_HOME/$key.offset"
out="$("$AWAIT" --timeout 1 --interval 1 "$target" 2>&1)"; rc=$?
check "timeout exits 0" [ "$rc" -eq 0 ]
check "timeout prints exactly one line" [ "$(wc -l <<<"$out" | tr -d ' ')" -eq 1 ]
check "timeout line is the quiet form" grep -q "^pane-inbox-await: no mail for $target within 1s\.$" <<<"$out"
check "pid file removed after timeout" [ ! -e "$pidfile" ]

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
