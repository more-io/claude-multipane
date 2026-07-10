---
name: orchestrate-panes
description: Use this skill when acting as the ORCHESTRATOR pane in a multi-pane Claude Code setup — dispatching issues/tasks to worker panes, collecting their results, verifying and merging their work centrally. Triggered by phrases like "verteilen", "dispatch to panes", "orchestrate", "orchestrator mode", when the user asks to hand several issues to the worker panes, or when a worker pane reports back ("[paneN] ... fertig/blocked"). Complements send-to-pane (the messaging primitive) with the full operating protocol.
---

# Orchestrate Worker Panes

The operating protocol for the **orchestrator pane** in a claude-multipane
workspace: one coordinating Claude Code session (typically pane 1) plans and
dispatches work to N worker panes, answers their questions, independently
verifies their results, and is the ONLY pane that merges, pushes, closes
issues, and deploys. Worker panes build; the orchestrator integrates.

## Project layout (from config)

Read the current project from `~/.claude/panes.conf` — fields:
`<name> <main-worktree> <main-branch> <pane-count> <tmux-target-prefix>`.
- Worker worktrees: `<main-worktree>_pane2..N` (the orchestrator usually sits
  in `_pane1`), tmux targets `<prefix>.2..N`, orchestrator at `<prefix>.1`.
- Integration branch `<main-branch>` lives in `<main-worktree>` — merges run
  there via `git -C`, never by `cd`-ing into it.

## Core rules (learned the hard way)

1. **The orchestrator does not build features in parallel.** Coordinate,
   review, verify, merge. Taking on your own implementation work while
   orchestrating makes the state untrackable for the user. (Exception: when
   all workers are busy/capped and the user assigns you one explicitly.)
2. **Cut work DISJOINTLY.** One issue per pane, no two panes in the same
   files. When two tasks touch the same chokepoint (e.g. the same function),
   sequence them: merge the first, then have the second pane merge the
   integration branch and re-verify on top before it finishes.
3. **Workers must ping back — there is no automatic notification.** A worker
   pane finishing does NOT wake the orchestrator. Every dispatch must include
   the standing instruction: "when done, blocked, or needing a decision, ping
   the orchestrator via `tmux send-keys -t <prefix>.1 -l '<status incl.
   issue#>'` followed by a separate Enter keypress — never wait silently."
4. **Only the orchestrator merges / pushes / closes / deploys.** Workers
   commit on their own branch and stop. This serializes integration and
   avoids merge races.
5. **Re-check pane state before acting on it.** The user may interact with
   worker panes directly (answering their questions, giving test feedback,
   even cancelling their task). Never act on a stale model — capture the
   pane (`tmux capture-pane -t <target> -p | tail`) or check `git log` in its
   worktree before merging or re-dispatching.
6. **Close the loop after taking over.** When the orchestrator merges,
   deploys, or closes a worker's issue, TELL that pane — otherwise it keeps a
   stale model and later reports/acts on outdated state. A short ack ("merged
   as <sha>, issue closed, you're done — feel free to /clear") also frees its
   context.
7. **Escalate user decisions.** Workers' questions that need a human call
   (scope, product behavior, deploy-go) are relayed to the user by the
   orchestrator — or the user answers directly in the worker pane (see rule 5).

## Dispatching a task

1. Pick the target pane (idle? check with `tmux capture-pane`) and note its
   context usage from its status line — if high, tell it to `/clear` first.
2. Write the per-worktree issue marker so the status line shows who works on
   what: `printf '<issue#>' > /tmp/claude-current-issue-<worktree-basename>.txt`
   (clear with `rm -f` on completion — the tracking hook usually clears it
   when the pane itself closes the issue).
3. Send a SELF-CONTAINED brief via the send-to-pane skill (two-step
   send-keys). The worker has none of your context. Include:
   - issue number + one-line summary + any decisions already made
   - "plan first (use an agent) BEFORE implementing" for non-trivial work
   - "merge <main-branch> into your branch before starting" (state the
     current head sha so drift is detectable)
   - your project's workflow conventions (labels, reminders, release notes,
     localization, testing and review requirements — whatever your project's
     CLAUDE.md mandates)
   - "commit on your branch, do NOT push/merge — the orchestrator integrates"
   - the ping-back rule (see core rule 3)
4. After sending, verify the pane actually accepted the prompt (capture-pane
   shows activity / the issue marker in its status line) — a first Enter can
   land in a permission dialog.

## When a worker reports "done"

1. **Verify independently — don't take the report at face value.** Look at
   the commit (`git -C <worktree> show <sha> --stat`), skim the diff of the
   core change, and RE-RUN the tests yourself from the worker's worktree
   (match the test framework — a 0-tests-matched run that exits 0 is NOT
   green). For risky changes add your own adversarial review pass.
5. **Sequence-check:** does this change overlap with another pane's pending
   work? If yes, merge in dependency order and make the later pane rebase +
   re-verify (see core rule 2).
2. Get the user's go where your conventions require it (merging, pushing,
   closing), then: `git -C <main-worktree> merge <pane-branch> --no-ff`,
   push after approval, close the issue with a substantive comment, complete
   trackers/reminders, clear the issue marker.
3. Ack the worker pane (core rule 6).

## Capacity & handover

- Workers may hit usage caps mid-task. Standing instruction for that case:
  "commit your WIP state and ping the orchestrator — it takes over on its own
  worktree." Cherry-pick their commits rather than re-doing work.
- When a worker's question stalls (user away), park the task explicitly and
  note the pane is idle — don't leave "in progress" markers pointing at idle
  panes.

## Anti-patterns

- Dispatching two panes into the same file "because they're careful".
- Merging on a worker's own claim of green tests without re-running them.
- Deploying from a worker worktree (deploys run from the integration
  worktree only — a partial worktree can clobber newer artifacts).
- Fire-and-forget dispatch: no ping-back rule in the brief = a finished pane
  silently idling for hours.
- Leaving the user's decisions implicit: every merge/push/deploy that your
  project treats as gated needs an explicit go.
