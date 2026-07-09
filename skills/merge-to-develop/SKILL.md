---
name: merge-to-develop
description: Use this skill when the user asks to merge the current worktree's branch into the project's integration branch checked out in the main worktree — phrases like "merge to develop", "merge into main", "local in develop übernehmen", "in develop mergen", "nach develop mergen", or similar. The integration branch and its worktree are read from panes.conf, so this works whether your integration branch is `develop`, `main`, or anything else.
---

# Merge Current Branch → Integration Worktree

Merges the current worktree's branch into the project's **integration branch**, which is checked out in a *different* worktree. Because git won't let two worktrees have the same branch checked out, the merge must run in the integration worktree (via `git -C`), not the current one.

## Project layout (from config)

Read the current project from `~/.claude/panes.conf` — fields: `<name> <main-worktree> <main-branch> <pane-count> <tmux-target-prefix>`. Pick the line whose `<main-worktree>` is a prefix of the session cwd (or the only line).
- **Integration worktree** = `<main-worktree>`
- **Integration branch** = `<main-branch>` (e.g. `develop` or `main`)

## Steps

1. **Check the current branch is clean** — `git status --porcelain`. If there are uncommitted changes, either commit them first or stop and ask; never merge a dirty tree.
2. **Get the current branch name** — `git branch --show-current`.
3. **Merge into the integration branch** — run it in the integration worktree:
   `git -C <main-worktree> merge <current-branch> --no-ff`
4. **Handle conflicts** — if the merge reports conflicts, STOP and report them; do NOT auto-resolve. Leave the merge in progress so the user can resolve it in their IDE.
5. **Report the result** — merge summary (commits merged, or "already up to date").

## Important notes

- The integration branch is checked out in `<main-worktree>`, NOT the current directory — you cannot `git checkout <main-branch>` here. Always operate with `git -C <main-worktree>`.
- Never `cd` into the integration worktree — use `git -C` so Claude's own working directory doesn't change.
- Always use `--no-ff` so the merge commit is visible (unless a clean fast-forward is explicitly wanted).
- **Do NOT push after merging** — pushing is a separate, explicit user action. Ask first.
- After the merge, the status line may show a `→ <main-branch>` cross-worktree hint; the `focus-worktree` skill resets it.
