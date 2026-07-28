#!/usr/bin/env bash
# Stop hook: when this Claude pane finishes a turn, drain its pane-msg inbox and
# feed any queued messages back to Claude via the hook channel — WITHOUT ever
# typing into the input prompt (so the user's own typing is never clobbered).
#
# Delivery model: messages sit in the pane's inbox file; this hook picks them up
# at the next turn boundary. It consumes them (advances the read offset), so the
# next Stop sees an empty inbox and allows the stop → no loop.
set -euo pipefail

PANE_MSG="$HOME/.claude/pane-msg"
[ -x "$PANE_MSG" ] || exit 0

# Consume the hook's stdin JSON (unused, but keep the pipe happy).
cat >/dev/null 2>&1 || true

# Identify this pane (uses $TMUX_PANE inside pane-msg).
self="$("$PANE_MSG" whoami 2>/dev/null)" || exit 0
[ -n "$self" ] || exit 0

# Read + consume unread messages for this pane.
msgs="$("$PANE_MSG" read "$self" 2>/dev/null)" || exit 0
case "$msgs" in
  ""|"(no new messages)"|"(inbox empty)") exit 0 ;;
esac

# Block the stop and hand the messages to Claude to handle, then continue.
MSGS="$msgs" python3 -c '
import json, os
print(json.dumps({
    "decision": "block",
    "reason": "📨 Queued pane-msg inbox message(s) arrived — handle them now, then continue:\n\n" + os.environ["MSGS"],
}))
'
