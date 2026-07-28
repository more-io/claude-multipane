---
name: send-to-pane
description: Low-level primitive for typing raw keystrokes into another tmux pane's prompt via `tmux send-keys`. Use ONLY for genuinely interactive one-offs — e.g. typing "yes"/Enter into a pane waiting on a confirmation dialog, or driving a pane's TUI directly. DO NOT use it to hand off a task, question, answer, or status to a pane ("send to pane2", "tell pane4", "schick an pane4", "pane1 soll", delegate/dispatch): those go through the **pane-inbox** skill, which writes to the pane's inbox file and never clobbers what the user is typing. send-keys overwrites in-progress input, so reach for this only when pane-inbox genuinely can't do the job.
---

# Send a Prompt to Another tmux Pane

Sends a text prompt to another Claude Code instance running in a parallel tmux pane — the coordination primitive for the orchestrator layout.

> **Prefer the `pane-inbox` skill for task handoff, questions, and status.**
> This skill types straight into the target's input line via `send-keys`, which
> **clobbers whatever the user is currently typing there** and can get stuck as a
> `[Pasted text]`. `pane-inbox` (`~/.claude/pane-msg`) writes the payload to the
> target's inbox file and lets its Stop-hook deliver it without touching the
> prompt. Use raw `send-keys` below only for genuinely interactive one-offs —
> e.g. typing `yes` into a pane waiting on a confirmation, or an explicit
> `pane-msg send … --nudge` to cold-start an idle pane.

## Target (from config)

Read the current project from `~/.claude/panes.conf` — fields: `<name> <main-worktree> <main-branch> <pane-count> <tmux-target-prefix>`. The `<tmux-target-prefix>` is `<session>:<window>` (e.g. `xyz:1`). Pane **N** is then `<session>:<window>.N`, i.e. `xyz:1.2` for pane 2.

Verify the live layout first:
```bash
tmux list-panes -t <session>:<window> -F "#{session_name}:#{window_index}.#{pane_index} #{pane_current_path}"
```

If the user names a session or pane that isn't the one in `panes.conf` (e.g. a second tmux session you keep for other work), don't guess — discover all live panes and target the one they mean:
```bash
tmux list-panes -a -F "#{session_name}:#{window_index}.#{pane_index} #{pane_current_path}"
```

## How to send

Use `tmux send-keys` **twice**: first the message with `Enter`, then a **bare `Enter`** as a follow-up. The first `Enter` sometimes lands while the target pane is still in a permission/approval/IME state and stays in the input buffer; the second bare `Enter` ensures the prompt is actually submitted.

```bash
tmux send-keys -t <session>:<window>.2 'Your prompt or instruction here' Enter
tmux send-keys -t <session>:<window>.2 '' Enter
```

## Important rules

- **Long messages often stay stuck as an unsubmitted paste** — with bracketed paste, the first Enter frequently lands inside the paste instead of submitting it (observed repeatedly with multi-sentence briefs). After sending, ALWAYS capture the pane and check for a `[Pasted text #N]` marker at the prompt; if present, send one more bare Enter (`tmux send-keys -t <target> C-m`) and verify again. Never assume delivery without seeing the pane actually working.
- **Always single-quote** the message to prevent shell expansion; **escape inner single quotes** as `'\''`.
- **Always send the follow-up bare `Enter`** — the first Enter doesn't always submit mid-approval.
- **Check the target pane first**: `tmux capture-pane -t <session>:<window>.2 -p | tail -25` — is it idle or busy?
- **Don't send to yourself** — identify your own pane with `tmux display-message -p '#{session_name}:#{window_index}.#{pane_index}'`.
- **Keep prompts self-contained** — the other instance has none of this conversation's context. Include file paths, issue numbers, and enough background.
- **Optionally set the target's issue segment** at dispatch so the status line shows who's on what:
  `printf '4711' > /tmp/claude-current-issue-$(basename "${main-worktree}_pane2").txt` (clear with `rm -f`).

## Reading a pane's status

```bash
tmux capture-pane -t <session>:<window>.2 -p | tail -25   # most reliable
```

## Coordination

- After sending, continue your own work — don't block waiting.
- Check status later with another `capture-pane`.
- For multi-step coordination, send one step at a time.
- When a pane reports "waiting for confirmation" or similar, send it: `tmux send-keys -t <session>:<window>.2 'yes' Enter` then a bare `Enter`.
