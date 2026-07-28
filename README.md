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
- **`hooks/pane-inbox-drain.sh`** — a `Stop` hook that delivers queued inter-pane messages: when a pane finishes a turn it drains that pane's inbox and hands any messages to Claude **through the hook channel, without ever typing into the input prompt**. No-op unless a message is waiting. See [Inter-pane messaging](#inter-pane-messaging-pane-inbox).
- **`bin/pane-msg`** — the messaging CLI behind the `pane-inbox` skill: append a message to another pane's inbox file (`send`), drain your own (`read`/`peek`), or check counts (`status`). Payload lives in files, so it never clobbers what the user is typing in the target pane.
- **`bin/setup-panes.sh`** — **builds the workspace**: for a project in `panes.conf` it creates one git worktree per pane (`<repo>_pane1..N` on branches `pane1..N`), opens a tmux session split into those panes, `cd`s each into its worktree, and launches Claude Code in each. Idempotent (skips existing worktrees/session) and supports `DRY_RUN=1`.
- **`panes.conf.example`** — the shared config the tooling reads (project name, main worktree path, main branch, pane count, tmux target). Copy to `~/.claude/panes.conf`.
- **`skills/`** — [Claude Code skills](https://docs.claude.com/en/docs/claude-code/skills) (task-specific instruction files Claude loads on demand) for the orchestrator layout, all config-driven from `panes.conf`:
  - **`orchestrate-panes`** — the full operating protocol for the coordinating pane: dispatch briefs, ping-back rule, independent verification, central merge/close, capacity handover. The distilled lessons from running this daily.
  - **`send-to-pane`** — hand a self-contained task to another pane's Claude ("tell pane2 …") via raw `send-keys`. Kept for interactive one-offs; for real task handoff prefer `pane-inbox`.
  - **`pane-inbox`** — file-based messaging between panes that never clobbers the user's input (see [below](#inter-pane-messaging-pane-inbox)). The preferred channel for task handoff, questions, answers, and status.
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
ln -sf "$PWD/hooks/pane-inbox-drain.sh"    ~/.claude/hooks/pane-inbox-drain.sh
ln -sf "$PWD/bin/pane-msg"                 ~/.claude/pane-msg   # inter-pane messaging CLI
cp panes.conf.example ~/.claude/panes.conf   # then edit
# orchestrator skills (optional):
for s in orchestrate-panes send-to-pane pane-inbox merge-to-develop sync-panes-with-develop focus-worktree; do
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
    ],
    "Stop": [
      { "hooks": [
        { "type": "command", "command": "bash ~/.claude/hooks/pane-inbox-drain.sh", "timeout": 8 }
      ] }
    ]
  }
}
```

The `Stop` entry powers `pane-inbox` (see below) and is a no-op when no message is queued — omit it if you don't use inter-pane messaging. Restart your Claude Code sessions so the hooks register. The status line updates immediately.

## How the `#issue` segment stays current

Two feeders, both local and fast (no per-render network calls):

1. **Automatic** — the `track-current-issue.sh` hook watches the `gh issue` label commands you run and writes/clears the per-worktree state file.
2. **Orchestrator** — the coordinating pane writes a target pane's file when it hands off a task:
   `printf '4711' > /tmp/claude-current-issue-<worktree>.txt` (clear with `rm -f`).

Because the state is keyed by **worktree basename**, every pane reads its own value.

## Inter-pane messaging (`pane-inbox`)

The obvious way to hand work between panes is `tmux send-keys` into the target's
input line (that's `send-to-pane`). It has two problems: it **overwrites whatever
the user is typing** in that pane, and a long brief can stick as an unsubmitted
`[Pasted text]`. `pane-inbox` fixes both by moving the payload off the prompt.

**Model:** `pane-msg send` appends the message (a JSON line) to the recipient's
inbox file under `~/.claude/tmux-state/mailbox/`. Nothing is typed into the
prompt. Delivery happens two ways:

1. **Stop-hook drain (default, promptless).** When the recipient pane finishes
   any turn — including a turn the user themselves triggered — the
   `pane-inbox-drain.sh` `Stop` hook reads its inbox and feeds the messages back
   through the hook channel. The user's typing is never touched.
2. **Guarded nudge (opt-in `--nudge`).** To cold-start a *fully idle* pane (one
   that won't end a turn on its own), `--nudge` sends a tiny `read-inbox` wake via
   `send-keys` — but **only if that pane's input line is empty**, so it still
   can't clobber typing. Otherwise it silently falls back to Stop-hook delivery.

```bash
pane-msg send 4later:1.2 --type task --ref 4711 "Self-contained brief…"   # queue; delivered on its next turn
pane-msg send 4later:1.2 --type task --ref 4711 --nudge "…"               # also wake it now, if its prompt is clear
pane-msg read      # drain your own inbox (auto-detects your pane via $TMUX_PANE)
pane-msg status    # unread counts across all mailboxes
```

`--type` is `task | question | answer | status | note`; `--ref` threads replies
(e.g. an issue number). The orchestrator and worker panes use this as their
default channel — see the `orchestrate-panes` and `send-to-pane` skills.

## Optional companions

- **[claude-tts](https://github.com/more-io/claude-tts)** — enables the `TTS:ON/OFF` segment (reads `~/.claude/tts-enabled`). Without it the segment simply shows `TTS:OFF`.
- **[claude-apple-bridges](https://github.com/more-io/claude-apple-bridges)** — native access to macOS apps (Reminders, Calendar, …) from Claude Code.

## License

MIT — see [LICENSE](LICENSE).
