#!/usr/bin/env bash
# setup-panes.sh — build a multi-pane Claude Code workspace for a project defined
# in ~/.claude/panes.conf: create one git worktree per pane, open a tmux session
# split into those panes, and launch Claude Code in each.
#
# Usage:
#   setup-panes.sh [project-name]     # default: first project in the config
#   DRY_RUN=1 setup-panes.sh [name]   # print what would happen, do nothing
#   PANES_CONF=/path/to/conf setup-panes.sh
#
# Config line format (panes.conf):
#   <name>  <main-worktree-path>  <main-branch>  <pane-count>  <tmux-target-prefix>
#   e.g.    xyz  /Users/you/dev/xyz  main  4  xyz:1
#
# Pane worktrees are derived as <main-worktree>_pane1 .. _paneN on branches
# pane1 .. paneN (created off <main-branch> if they don't exist yet). tmux panes
# live in <session>:<window> where <tmux-target-prefix> = "<session>:<window>".
set -euo pipefail

CONF="${PANES_CONF:-$HOME/.claude/panes.conf}"
PROJECT="${1:-}"
DRY_RUN="${DRY_RUN:-0}"
run() { if [ "$DRY_RUN" = "1" ]; then printf 'DRY_RUN: %s\n' "$*"; else eval "$@"; fi; }

[ -f "$CONF" ] || { echo "config not found: $CONF (copy panes.conf.example there)"; exit 1; }

# Pick the requested project line, or the first non-comment line.
line=$(grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$CONF" | \
       if [ -n "$PROJECT" ]; then awk -v p="$PROJECT" '$1==p{print; exit}'; else head -1; fi)
[ -n "$line" ] || { echo "no project '${PROJECT:-<first>}' in $CONF"; exit 1; }

read -r name main branch panes prefix <<<"$line"
session="${prefix%%:*}"
window="${prefix#*:}"
echo "Project '$name': main=$main  branch=$branch  panes=$panes  tmux=$session:$window"

[ -d "$main/.git" ] || [ -f "$main/.git" ] || { echo "main worktree is not a git repo: $main"; exit 1; }

# 1) Ensure a git worktree per pane: <main>_paneN on branch paneN.
for n in $(seq 1 "$panes"); do
  wt="${main}_pane${n}"; br="pane${n}"
  if [ -d "$wt" ]; then
    echo "  worktree exists: $wt"
  elif git -C "$main" show-ref --verify --quiet "refs/heads/$br"; then
    run "git -C '$main' worktree add '$wt' '$br'"
  else
    run "git -C '$main' worktree add -b '$br' '$wt' '$branch'"
  fi
done

# 2) Create the tmux session + window, split into N panes (one worktree each).
if tmux has-session -t "$session" 2>/dev/null; then
  echo "tmux session '$session' already exists — not recreating (attach: tmux attach -t $session)"
  exit 0
fi
run "tmux new-session -d -s '$session' -n 'w$window' -c '${main}_pane1'"
for n in $(seq 2 "$panes"); do
  run "tmux split-window -t '$session:$window' -c '${main}_pane${n}'"
  run "tmux select-layout -t '$session:$window' tiled"
done
run "tmux select-layout -t '$session:$window' tiled"

# 3) In each pane: raise the fd limit and launch Claude Code; title it <session>:paneN.
# Iterate the ACTUAL pane indices (respects tmux pane-base-index).
if [ "$DRY_RUN" = "1" ]; then
  idxs=$(seq 1 "$panes")
else
  idxs=$(tmux list-panes -t "$session:$window" -F '#{pane_index}' | sort -n)
fi
n=1
for idx in $idxs; do
  run "tmux send-keys -t '$session:$window.$idx' 'ulimit -n 65536 && claude' Enter"
  run "tmux select-pane -t '$session:$window.$idx' -T '$session:pane${n}'"
  n=$((n+1))
done

echo "Done. Attach with:  tmux attach -t $session"
