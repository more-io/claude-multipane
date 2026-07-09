---
name: sync-panes-with-develop
description: Use this skill when the user asks to bring the pane worktrees up to date with the integration branch — phrases like "sync panes", "panes mit develop syncen", "alle panes aktualisieren", "sync worktrees with main". Reads the project layout (integration branch, pane count, worktree paths) from panes.conf, so it works for any integration branch (develop/main).
---

# Sync Pane Worktrees with the Integration Branch

Brings each pane worktree up to date with the latest integration branch. Reports per-pane status and merges the integration branch into clean panes.

## Project layout (from config)

Read the current project from `~/.claude/panes.conf` — fields: `<name> <main-worktree> <main-branch> <pane-count> <tmux-target-prefix>`. Pick the line whose `<main-worktree>` is a prefix of the session cwd (or the only line). Then:
- **Integration worktree** = `<main-worktree>` (branch `<main-branch>`, the source of truth)
- **Pane worktrees** = `<main-worktree>_pane1` .. `_pane<pane-count>` (branches `pane1` .. `pane<N>`)

Below, `M` = `<main-branch>`, `WT` = `<main-worktree>`, `N` iterates `1..<pane-count>`.

## Steps

1. **Fetch + fast-forward the integration worktree**
   ```bash
   git -C "$WT" fetch origin && git -C "$WT" pull origin "$M" --ff-only
   ```

2. **For each pane** — run these checks in parallel (one Bash call per pane):
   - Working-tree status: `git -C "${WT}_paneN" status --porcelain`
   - Commits behind: `git -C "${WT}_paneN" rev-list --count paneN..$M`
   - Commits ahead (local work): `git -C "${WT}_paneN" rev-list --count $M..paneN`

3. **Decide per pane**:
   - **Dirty (uncommitted changes)** → SKIP, report "dirty, skipped"
   - **Behind > 0, clean** → merge the integration branch with `--no-ff`
   - **Up to date** → report "up to date"
   - **Ahead > 0, clean** → still merge the integration branch with `--no-ff` (catches the pane up while keeping its own commits)

4. **Merge the integration branch into each eligible pane**:
   ```bash
   git -C "${WT}_paneN" merge "$M" --no-ff -m "Merge $M into paneN"
   ```

5. **Handle conflicts** — if a merge reports conflicts, STOP for that pane and report them. Do NOT auto-resolve; leave the merge in progress.

6. **Report a final summary** per pane: up to date / merged N commits / dirty (skipped) / conflict (manual fix needed).

## Important rules

- **NEVER push** after merging — that's a separate, explicit user action.
- **NEVER `git checkout` / `git restore`** on dirty worktrees — uncommitted work could be lost.
- **Always use `--no-ff`** so the merge commit is visible.
- **Run pane checks in parallel** (one Bash call per pane in a single message) for speed.
- Use `git -C <path>` throughout — never `cd` into a worktree.
- **Be precise about which pane is dirty** — name the modified files so the user can decide.

## When to abort

- Conflict during a merge → STOP, report the pane + conflict markers, leave the merge in progress.
- The integration worktree itself has uncommitted changes → STOP, ask the user.
- Network failure during fetch → retry once, otherwise report.
