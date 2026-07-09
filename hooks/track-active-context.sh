#!/bin/bash
# Claude Code PostToolUse hook: tracks which git worktree Claude is currently
# working in, so the statusline can show it next to the session cwd.
#
# Reads the tool invocation JSON via stdin, extracts a filesystem path from
# the relevant argument (command / file_path), walks up to the git toplevel,
# and writes "<worktree-name>\t<branch>" to /tmp/claude-active-context-<session>.txt.
#
# Silent: any failure leaves the previous context file untouched.

set -e

input=$(cat)

session_id=$(echo "$input" | jq -r '.session_id // empty')
tool_name=$(echo "$input" | jq -r '.tool_name // empty')

if [ -z "$session_id" ] || [ -z "$tool_name" ]; then
    exit 0
fi

state_file="/tmp/claude-active-context-${session_id}.txt"

candidate_path=""

case "$tool_name" in
    Bash)
        command=$(echo "$input" | jq -r '.tool_input.command // empty')
        # Look for `git -C <path>` — the explicit working-directory override.
        # Handles both quoted and unquoted paths.
        git_c_path=$(printf '%s' "$command" | grep -oE 'git -C ("[^"]+"|'"'"'[^'"'"']+'"'"'|[^ ]+)' | head -1 | sed -E 's/^git -C //; s/^["'"'"']//; s/["'"'"']$//')
        if [ -n "$git_c_path" ]; then
            candidate_path="$git_c_path"
        else
            # Fallback: `cd <path> && …` — nimm den ersten cd-Pfad
            cd_path=$(printf '%s' "$command" | grep -oE '^cd ("[^"]+"|'"'"'[^'"'"']+'"'"'|[^ &|;]+)' | head -1 | sed -E 's/^cd //; s/^["'"'"']//; s/["'"'"']$//')
            if [ -n "$cd_path" ]; then
                candidate_path="$cd_path"
            fi
        fi
        ;;
    Edit|Write|NotebookEdit)
        file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')
        if [ -n "$file_path" ]; then
            candidate_path=$(dirname "$file_path")
        fi
        ;;
esac

if [ -z "$candidate_path" ]; then
    exit 0
fi

# Resolve tilde
candidate_path="${candidate_path/#\~/$HOME}"

# Must exist and be a directory or file
if [ ! -e "$candidate_path" ]; then
    exit 0
fi

if [ -f "$candidate_path" ]; then
    candidate_path=$(dirname "$candidate_path")
fi

# Must be inside a git repo
toplevel=$(git -C "$candidate_path" -c core.fsmonitor=false rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$toplevel" ]; then
    exit 0
fi

branch=$(git -C "$toplevel" -c core.fsmonitor=false symbolic-ref --short HEAD 2>/dev/null || true)
if [ -z "$branch" ]; then
    exit 0
fi

worktree_name=$(basename "$toplevel")

printf '%s\t%s\t%s\n' "$worktree_name" "$branch" "$toplevel" > "$state_file"
