#!/bin/bash
# PostToolUse (Bash): track the GitHub issue currently being worked on in this
# session, derived from the `in progress` label actions that already bracket
# issue work. Writes the number (no '#') to /tmp/claude-current-issue-<session>.txt;
# the statusline reads it and shows an orange "#N".
#
#   set   on:  gh issue edit <N> ... --add-label ... "in progress"
#   clear on:  gh issue close <N>   OR   gh issue edit <N> --remove-label "in progress"
#
# Fast path: bail immediately unless the command even mentions `gh issue`.

input=$(cat)
printf '%s' "$input" | grep -q 'gh issue' || exit 0

tool=$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null)
[ "$tool" = "Bash" ] || exit 0
cwd=$(printf '%s' "$input" | jq -r '.cwd // .workspace.current_dir // ""' 2>/dev/null)
[ -n "$cwd" ] || exit 0
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null)
# Keyed by WORKTREE basename so every pane reads its own state.
f="/tmp/claude-current-issue-$(basename "$cwd").txt"

# START: add the `in progress` label -> that issue becomes the current one.
if printf '%s' "$cmd" | grep -qE 'gh +issue +edit +[0-9]+' \
   && printf '%s' "$cmd" | grep -q -- '--add-label' \
   && printf '%s' "$cmd" | grep -qi 'in progress'; then
    n=$(printf '%s' "$cmd" | grep -oE 'gh +issue +edit +[0-9]+' | grep -oE '[0-9]+' | head -1)
    [ -n "$n" ] && printf '%s' "$n" > "$f"
    exit 0
fi

# STOP: close it, or strip its `in progress` label -> clear if it's the current one.
cur=$(cat "$f" 2>/dev/null)
[ -n "$cur" ] || exit 0
if printf '%s' "$cmd" | grep -qE "gh +issue +close +${cur}([^0-9]|$)"; then
    rm -f "$f"; exit 0
fi
if printf '%s' "$cmd" | grep -qE "gh +issue +edit +${cur}([^0-9]|$)" \
   && printf '%s' "$cmd" | grep -q -- '--remove-label' \
   && printf '%s' "$cmd" | grep -qi 'in progress'; then
    rm -f "$f"; exit 0
fi
exit 0
