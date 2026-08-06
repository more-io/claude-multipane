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

# If THIS pane is the one a human is viewing, it has no automatic wake-up: the
# guarded nudge refuses it by design and an idle pane never reaches another Stop.
# So the messages just drained would have been the LAST ones delivered on their
# own — the next reply waits for the human to type. Re-arm the background waiter
# while we are here.
#
# This rides on the drain, which only happens when there WAS mail, so it can
# never turn into a per-turn nag or a stop loop. It stays silent once a waiter
# is running.
extra=""
flags="$(tmux display-message -p -t "$self" '#{pane_active}#{window_active}#{?session_attached,1,0}' 2>/dev/null || true)"
if [ "$flags" = "111" ] && ! pgrep -f "pane-inbox-await" >/dev/null 2>&1; then
  extra=$'\n\n⚠️  No wake-up channel is armed for this pane. You are the pane the human is viewing, so a nudge is refused by design, and an idle pane never runs this hook again — the next reply would sit unread until the human types. Re-arm it as a BACKGROUND task now: pane-inbox-await'
fi

# Block the stop and hand the messages to Claude to handle, then continue.
MSGS="$msgs" EXTRA="$extra" python3 -c '
import json, os
print(json.dumps({
    "decision": "block",
    "reason": "📨 Queued pane-msg inbox message(s) arrived — handle them now, then continue:\n\n"
              + os.environ["MSGS"] + os.environ.get("EXTRA", ""),
}))
'
