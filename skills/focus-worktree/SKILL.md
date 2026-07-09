---
name: focus-worktree
description: Use this skill when the user says "fokus zurück", "context zurück", "focus pane4" (or any other pane name), "zurück in den branch", "context auf <worktree>", or similar phrases about resetting Claude's tracked active-context (shown in the status bar as "→ branch [worktree]") back to the current session's worktree. Triggered after running cross-worktree commands (e.g. merging into the main worktree, deploying) that made the status bar display a different branch than where the user actually wants to work.
---

# Focus Worktree — Reset Tracked Active Context

The Claude Code status bar (from the `claude-multipane` toolkit) includes an active-context indicator (`→ branch [worktree]`) set by the PostToolUse hook `~/.claude/hooks/track-active-context.sh` whenever Claude runs `cd <path>` or `git -C <path>` against a path outside the session cwd. After cross-worktree work the indicator may keep pointing at the other worktree even though the user is done there.

This skill resets it by running an innocuous `git -C <target> status --short`, which retriggers the hook with the intended worktree and clears the arrow.

## Project layout (from config)

Read the current project from `~/.claude/panes.conf` — fields: `<name> <main-worktree> <main-branch> <pane-count> <tmux-target-prefix>`. Pick the line whose `<main-worktree>` is a prefix of the session cwd (or the only line). Then:
- **pane N** → `<main-worktree>_pane<N>`
- the **main/integration worktree** (user says the main-branch name, e.g. `develop` or `main`) → `<main-worktree>`

## Steps

1. **Determine the target worktree** — default is the current session's cwd (`pwd`). If the user names a pane (`pane1`, `pane2`, …), use `<main-worktree>_pane<N>`. If they name the main branch, use `<main-worktree>`.
2. **Run `git -C <target> status --short`** — benign; triggers `track-active-context.sh` and updates `/tmp/claude-active-context-<session>.txt`.
3. **Confirm briefly** — report the branch name and worktree directory. One line, no fluff.

## Notes

- The skill must invoke the bash command itself — the hook only fires on `git -C <path>` / `cd <path>` patterns.
- Never `cd` into the target — that would change Claude's own working directory. `git -C <path>` is non-destructive and only needs to be parsed by the hook.
- If already focused on the right context, still run the command — cheap no-op.
