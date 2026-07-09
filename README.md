# claude-multipane

> ⚠️ **0.1.0-beta · work in progress.** The status line, hooks, `setup-panes.sh`, and the orchestrator skills all work today, driven by one `panes.conf`. Expect rough edges.

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
- **`bin/setup-panes.sh`** — **builds the workspace**: for a project in `panes.conf` it creates one git worktree per pane (`<repo>_pane1..N` on branches `pane1..N`), opens a tmux session split into those panes, `cd`s each into its worktree, and launches Claude Code in each. Idempotent (skips existing worktrees/session) and supports `DRY_RUN=1`.
- **`panes.conf.example`** — the shared config the tooling reads (project name, main worktree path, main branch, pane count, tmux target). Copy to `~/.claude/panes.conf`.
- **`skills/`** — [Claude Code skills](https://docs.claude.com/en/docs/claude-code/skills) (task-specific instruction files Claude loads on demand) for the orchestrator layout, all config-driven from `panes.conf`:
  - **`send-to-pane`** — hand a self-contained task to another pane's Claude ("tell pane2 …").
  - **`merge-to-develop`** — merge the current worktree's branch into the integration branch (in its own worktree, via `git -C`).
  - **`sync-panes-with-develop`** — bring every pane worktree up to date with the integration branch, reporting per-pane status.
  - **`focus-worktree`** — reset the status line's cross-worktree "→" hint back to the pane you actually want to work in.

## Create the panes

Configure your project in `~/.claude/panes.conf` (one line — see `panes.conf.example`), then:

```bash
DRY_RUN=1 ~/path/to/claude-multipane/bin/setup-panes.sh xyz   # preview
~/path/to/claude-multipane/bin/setup-panes.sh xyz             # do it
tmux attach -t xyz
```

You get N panes, each in its own git worktree, each running Claude Code — one "orchestrator" pane plus workers, the layout this toolkit is built around.

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
# orchestrator skills (optional):
for s in send-to-pane merge-to-develop sync-panes-with-develop focus-worktree; do
  mkdir -p ~/.claude/skills/"$s"
  ln -sf "$PWD/skills/$s/SKILL.md" ~/.claude/skills/"$s"/SKILL.md
done
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
