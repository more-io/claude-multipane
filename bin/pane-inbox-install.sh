#!/usr/bin/env bash
# Install / re-sync the pane-inbox tooling from this repo into ~/.claude and
# (re)load the launchd delivery watcher. Idempotent — re-run after editing
# pane-msg or the watcher wrapper in the repo.
#
# NOTE: this does NOT edit ~/.claude/settings.json. The Stop-hook that delivers
# messages on a pane's own turn must be registered there once by hand (see
# README → Inter-pane messaging).
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CL="$HOME/.claude"
LA="$HOME/Library/LaunchAgents"
MB="$CL/tmux-state/mailbox"
mkdir -p "$CL/hooks" "$CL/skills/pane-inbox" "$LA" "$MB"

# The skill and the Stop-hook run *inside* Claude Code, which has the user's TCC
# grants — symlinks into the repo (even under ~/Documents) are fine and keep
# edits instantly live.
ln -sf "$REPO/skills/pane-inbox/SKILL.md" "$CL/skills/pane-inbox/SKILL.md"
ln -sf "$REPO/hooks/pane-inbox-drain.sh"  "$CL/hooks/pane-inbox-drain.sh"

# pane-msg and the watcher wrapper are executed by *launchd*, which has NO access
# to ~/Documents (TCC) and errors ("Operation not permitted") on a symlink that
# resolves there. Install REAL COPIES outside ~/Documents. Re-run this script
# after editing either file in the repo to re-sync.
cp "$REPO/bin/pane-msg"                "$CL/pane-msg";                       chmod +x "$CL/pane-msg"
cp "$REPO/hooks/pane-inbox-watcher.sh" "$CL/hooks/pane-inbox-watcher.sh";    chmod +x "$CL/hooks/pane-inbox-watcher.sh"

# WatchPaths needs the trigger file to exist before load.
touch "$MB/.event"

# Generate the concrete plist (launchd expands neither ~ nor $HOME) and reload.
PLIST="$LA/com.claude-multipane.pane-inbox-watcher.plist"
sed "s|__HOME__|$HOME|g" "$REPO/launchagents/com.claude-multipane.pane-inbox-watcher.plist" > "$PLIST"
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"

echo "pane-inbox installed / re-synced."
if launchctl list | grep -q pane-inbox; then
  echo "watcher agent loaded: com.claude-multipane.pane-inbox-watcher"
else
  echo "WARN: watcher agent not listed — check $PLIST and /tmp/pane-inbox-watcher.err.log" >&2
fi
