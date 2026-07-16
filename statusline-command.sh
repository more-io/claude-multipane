#!/bin/bash
# Claude Code status line - styled after Starship default prompt
# Receives JSON via stdin with session context

input=$(cat)

# Extract fields from JSON
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
model=$(echo "$input" | jq -r '.model.display_name // empty')
session_id=$(echo "$input" | jq -r '.session_id // empty')

# Persistiere das aktive Model pro Session, damit update-claude.sh es vor dem
# Kill auslesen und beim --resume via --model wiederherstellen kann.
# Knackpunkt: das 1M-Kontext-Flag lebt nur im RAM und taucht in .model.id NICHT
# auf — nur der display_name zeigt "(1M context)". Wir rekonstruieren daher die
# CLI-Model-id (z.B. "claude-opus-4-8[1m]", exakt wie in ~/.claude.json).
# Ablage unter ~/.claude/models/ statt /tmp: macOS' Periodic-Cleanup löscht in
# /tmp alles, was 3+ Tage nicht angefasst wurde — dort wäre das Model-Gedächtnis
# nicht verlässlich. update-claude.sh prunt alte Einträge.
MODEL_DIR="$HOME/.claude/models"
if [ -n "$session_id" ]; then
    model_id=$(echo "$input" | jq -r '.model.id // empty')
    if [ -n "$model_id" ]; then
        # 1M-Kontext aus display_name erkennen und [1m]-Suffix anhängen
        case "$model" in
            *"1M"*|*"1m context"*|*"(1M context)"*)
                case "$model_id" in
                    *"[1m]"*) : ;;                      # schon vorhanden
                    *) model_id="${model_id}[1m]" ;;
                esac
                ;;
        esac
        [ -d "$MODEL_DIR" ] || mkdir -p "$MODEL_DIR"
        printf '%s' "$model_id" > "$MODEL_DIR/${session_id}.txt"
    fi
fi
branch=""
worktree_name=$(echo "$input" | jq -r '.worktree.name // empty')
worktree_branch=$(echo "$input" | jq -r '.worktree.branch // empty')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# Shorten the path: replace $HOME with ~
home_dir="$HOME"
if [ -n "$cwd" ]; then
    short_dir="${cwd/#$home_dir/~}"
else
    short_dir="~"
fi

# Get git branch (skip optional locks to avoid stalling)
is_worktree=false
if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    branch=$(git -C "$cwd" -c core.fsmonitor=false symbolic-ref --short HEAD 2>/dev/null)
    # Detect if we're in a non-main worktree by checking worktree list
    main_worktree=$(git -C "$cwd" -c core.fsmonitor=false worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')
    if [ -n "$main_worktree" ] && [ "$(realpath "$cwd" 2>/dev/null || echo "$cwd")" != "$(realpath "$main_worktree" 2>/dev/null || echo "$main_worktree")" ]; then
        is_worktree=true
    fi
fi

# Always use the real git branch from $cwd — the JSON worktree.branch
# can reflect a different worktree than the one this pane is in.

# Build the status line using ANSI colors (dimmed by Claude Code automatically)
# Cyan bold for directory, magenta for branch, grey for model, yellow for context
output=""

# Directory segment (cyan)
output+="$(printf '\033[1;36m%s\033[0m' "$short_dir")"

# Git branch segment (magenta), with worktree indicator if applicable
if [ -n "$branch" ]; then
    if [ "$is_worktree" = true ] || [ -n "$worktree_name" ]; then
        # Show worktree icon (⎇) + branch, with worktree name if available from JSON
        # Show actual worktree directory name
        wt_dir_name=$(basename "$cwd")
        output+=" $(printf '\033[35m\xef\xa0\x9c %s \033[90m[%s]\033[0m' "$branch" "$wt_dir_name")"
    else
        output+=" $(printf '\033[35m\xef\xa0\x9c %s\033[0m' "$branch")"
    fi
fi

# Active context segment — shown only if Claude's recent tool calls touch
# a different git worktree than the session cwd (e.g. session started in
# pane1 but work is happening on develop). Written by the
# track-active-context.sh PostToolUse hook.
if [ -n "$session_id" ]; then
    active_file="/tmp/claude-active-context-${session_id}.txt"
    if [ -f "$active_file" ]; then
        IFS=$'\t' read -r active_wt_name active_branch active_toplevel < "$active_file" || true
        # Only show if it differs from the current session's worktree
        if [ -n "$active_branch" ] && [ "$active_toplevel" != "$(realpath "$cwd" 2>/dev/null || echo "$cwd")" ]; then
            output+=" $(printf '\033[1;33m→\033[0m \033[35m\xef\xa0\x9c %s \033[90m[%s]\033[0m' "$active_branch" "$active_wt_name")"
        fi
    fi
fi

# Current issue segment (orange) — the GitHub issue this worktree/pane is
# working on. Keyed by WORKTREE basename (not session) so pane1 (orchestrator)
# can set each pane's value at dispatch and every pane reads its own; also set
# by track-current-issue.sh from `in progress` label actions run in this pane.
if [ -n "$cwd" ]; then
    issue_file="/tmp/claude-current-issue-$(basename "$cwd").txt"
    if [ -f "$issue_file" ]; then
        cur_issue=$(cat "$issue_file" 2>/dev/null | tr -dc '0-9')
        if [ -n "$cur_issue" ]; then
            output+=" $(printf '\033[38;5;208m#%s\033[0m' "$cur_issue")"
        fi
    fi
fi

# Session ID segment removed - shown in tmux pane border instead

# Model segment (dark grey)
if [ -n "$model" ]; then
    output+=" $(printf '\033[90m[%s]\033[0m' "$model")"
fi

# Context usage segment (yellow when available)
if [ -n "$used_pct" ]; then
    # Round to integer
    pct_int=$(printf "%.0f" "$used_pct" 2>/dev/null || echo "$used_pct")
    output+=" $(printf '\033[33mctx:%s%%\033[0m' "$pct_int")"
fi

# TTS status (green=on, red=off)
if [ -f "$HOME/.claude/tts-enabled" ]; then
    output+=" $(printf '\033[32mTTS:ON\033[0m')"
else
    output+=" $(printf '\033[31mTTS:OFF\033[0m')"
fi

# Speech-to-Text / Dictation status (green=on, red=off) - check by process, not defaults
if pgrep -x DictationIM >/dev/null 2>&1; then
    output+=" $(printf '\033[32mSTT:ON\033[0m')"
else
    output+=" $(printf '\033[31mSTT:OFF\033[0m')"
fi

printf '%s' "$output"
