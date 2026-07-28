#!/usr/bin/env bash
# Stop hook: when this Claude pane finishes a turn, drain its pane-msg inbox and
# feed any queued messages back to Claude via the hook channel — WITHOUT ever
# typing into the input prompt (so the user's own typing is never clobbered).
#
# Delivery model: messages sit in the pane's inbox file; this hook picks them up
# at the next turn boundary. It consumes them (advances the read offset), so the
# next Stop sees an empty inbox and allows the stop → no loop.
set -euo pipefail

LOG="${PANE_INBOX_DRAIN_LOG:-/tmp/pane-inbox-drain.log}"
log() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*" >> "$LOG" 2>/dev/null || true; }

PANE_MSG="$HOME/.claude/pane-msg"
[ -x "$PANE_MSG" ] || { log "no pane-msg at $PANE_MSG"; exit 0; }

# Consume the hook's stdin JSON (unused, but keep the pipe happy).
cat >/dev/null 2>&1 || true

# Identify this pane STRICTLY from $TMUX_PANE — the unique id of the pane this
# process runs in. Never fall back to the client's *active* pane, which would
# drain the wrong mailbox.
self=""
if [ -n "${TMUX_PANE:-}" ]; then
  self="$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null || true)"
fi
log "TMUX_PANE=${TMUX_PANE:-UNSET} self=${self:-EMPTY}"
[ -n "$self" ] || exit 0

# Read + consume unread messages for this pane.
msgs="$("$PANE_MSG" read "$self" 2>/dev/null)" || { log "$self read failed"; exit 0; }
case "$msgs" in
  ""|"(no new messages)"|"(inbox empty)") log "$self nothing to drain"; exit 0 ;;
esac
log "$self DRAINED $(printf '%s' "$msgs" | grep -c '^── ') message(s)"

# Block the stop and hand the messages to Claude to handle, then continue.
MSGS="$msgs" python3 -c '
import json, os
print(json.dumps({
    "decision": "block",
    "reason": "📨 Queued pane-msg inbox message(s) arrived — handle them now, then continue:\n\n" + os.environ["MSGS"],
}))
'
