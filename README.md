# claude-multipane

A status line and workflow toolkit for running **[Claude Code](https://claude.com/claude-code) across several tmux panes** — one pane per git worktree — with an **orchestrator** pane that dispatches work to the others and sees, at a glance, **which pane is working on which GitHub issue**.

```
~/Documents/xyz_pane2   pane2 [xyz_pane2] #4711 [Opus 4.8] ctx:38% TTS:ON
                                          ^^^^^ ← the issue this pane is on
```

The status line is the visible part; the point is the workflow: you keep N Claude Code sessions open (one per worktree/pane), hand each a task, and the status line tells you who's on what.

## What's in here

- **`statusline-command.sh`** — the status line. Per pane it shows: working directory, git branch + worktree name, the **active GitHub issue** (orange `#N`), a cross-worktree "→" indicator when a pane's work has moved to another worktree, the model, context usage, and optional TTS/STT status.
- **`hooks/track-current-issue.sh`** — a `PostToolUse` hook that derives the current issue **per worktree** from the `in progress` label actions you already run: it sets the issue on `gh issue edit <N> --add-label "in progress"` and clears it on `gh issue close <N>` / `--remove-label "in progress"`. State lives in `/tmp/claude-current-issue-<worktree>.txt`; the orchestrator pane can also write that file directly when it dispatches a task.
- **`hooks/track-active-context.sh`** — a `PostToolUse` hook that records when Claude's recent commands touch a *different* worktree than the pane's own (e.g. you started in `pane1` but ran a merge in `develop`), which the status line renders as a "→ branch" hint.
- **`panes.conf.example`** — the shared config the orchestrator scripts/skills read (project name, worktree root, main branch, pane count). Copy to `~/.claude/panes.conf`.

_Coming (config-driven, from `panes.conf`): `setup-panes.sh` to open/restore N panes for any project, plus the orchestrator skills (dispatch-to-pane, sync-worktrees, focus-worktree, merge-to-main)._

## Requirements

- macOS + [Claude Code](https://claude.com/claude-code), [tmux](https://github.com/tmux/tmux)
- `jq`, `git`, and (for the issue segment) the [GitHub CLI `gh`](https://cli.github.com/)

## Install

Clone anywhere, then symlink the scripts into `~/.claude/` so the files you run are exactly these (no second copy to drift):

```bash
git clone https://github.com/more-io/claude-multipane.git
cd claude-multipane
mkdir -p ~/.claude/hooks
ln -sf "$PWD/statusline-command.sh"       ~/.claude/statusline-command.sh
ln -sf "$PWD/hooks/track-current-issue.sh" ~/.claude/hooks/track-current-issue.sh
ln -sf "$PWD/hooks/track-active-context.sh" ~/.claude/hooks/track-active-context.sh
cp panes.conf.example ~/.claude/panes.conf   # then edit
```

Then register them in `~/.claude/settings.json`:

```json
{
  "statusLine": { "type": "command", "command": "bash ~/.claude/statusline-command.sh" },
  "hooks": {
    "PostToolUse": [
      { "matcher": "Bash|Edit|Write|NotebookEdit", "hooks": [
        { "type": "command", "command": "bash ~/.claude/hooks/track-active-context.sh", "timeout": 3 },
        { "type": "command", "command": "bash ~/.claude/hooks/track-current-issue.sh", "timeout": 3 }
      ] }
    ]
  }
}
```

Restart your Claude Code sessions so the hooks register. The status line updates immediately.

## How the `#issue` segment stays current

Two feeders, both local and fast (no per-render network calls):

1. **Automatic** — the `track-current-issue.sh` hook watches the `gh issue` label commands you run and writes/clears the per-worktree state file.
2. **Orchestrator** — the coordinating pane writes a target pane's file when it hands off a task:
   `printf '4711' > /tmp/claude-current-issue-<worktree>.txt` (clear with `rm -f`).

Because the state is keyed by **worktree basename**, every pane reads its own value.

## Optional companions

- **[claude-tts](https://github.com/more-io/claude-tts)** — enables the `TTS:ON/OFF` segment (reads `~/.claude/tts-enabled`). Without it the segment simply shows `TTS:OFF`.
- **[claude-apple-bridges](https://github.com/more-io/claude-apple-bridges)** — native access to macOS apps (Reminders, Calendar, …) from Claude Code.

## License

MIT — see [LICENSE](LICENSE).
