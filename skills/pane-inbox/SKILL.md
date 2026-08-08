---
name: pane-inbox
description: FALLBACK messaging channel between Claude Code panes. FIRST CHOICE is Claude Code's NATIVE cross-session messaging — the built-in SendMessage/ListAgents tools (v2.1.224+, macOS/Linux) deliver between sessions and WAKE idle panes by starting a new turn, with no hook or watcher. Use THIS skill's file-based pane-msg only when native messaging is unavailable (no SendMessage tool, /list-agents unknown, provider without the feature) or when the JSONL audit trail is explicitly wanted. Triggered by (1) a "📨 Queued pane-msg inbox message(s)" note or "📨 pane-msg" nudge in your prompt → handle the messages; (2) a request to message a pane when native messaging is not available. Only fall back to send-to-pane for raw interactive keystrokes (e.g. typing "yes" into a confirmation prompt).
---

# Pane Inbox — file-based inter-pane messaging (never clobbers user input)

> **⚠️ Superseded for most uses by native cross-session messaging.** Since
> Claude Code v2.1.224 (macOS/Linux), sessions can message each other directly
> via the built-in `SendMessage` tool, discovered with `ListAgents` /
> `/list-agents`: delivery lands between tool calls in a busy session and
> **starts a new turn in an idle one** — the exact wake-a-sleeping-pane problem
> this skill's nudge/watcher machinery works around. Prefer native messaging
> whenever the tools exist. First-contact quirk: the bare session name may not
> resolve until you have listed it — send once with the `name [ref]` from
> `ListAgents` (a failed send names the right ref). Docs:
> https://code.claude.com/docs/en/cross-session-messaging.md
> Everything below remains the FALLBACK: older Claude Code, providers without
> the feature, or when the mailbox JSONL audit trail is wanted.

The payload of an inter-pane message is appended to the recipient's **inbox
file**; it is NEVER typed into the recipient's input prompt. Two things deliver
it to the recipient's Claude:

1. **Guarded nudge (the default).** `pane-msg send` checks the target: if it's
   **idle with an empty input line**, it sends a tiny `📨 read-inbox` nudge via
   `send-keys` so the pane wakes and reads the message right away. If the target
   is **busy** or **the user is typing there**, it sends **no** nudge — so it can
   never clobber in-progress input — and falls back to (2).
2. **Stop-hook drain (the fallback, fully promptless).** When a pane finishes any
   turn, a `Stop` hook (`~/.claude/hooks/pane-inbox-drain.sh`) reads its inbox and
   feeds queued messages back through the hook channel, never touching the input
   line. This catches anything the guarded nudge deliberately skipped.

Net effect: an idle empty pane reads immediately (no user action needed); a busy
pane reads when its turn ends; and a pane where the user has half-typed text
waits — correctly — until the user submits or clears it, so their input is safe.
Only edge case that truly waits for the user: an idle pane that already has
unsubmitted text sitting in its prompt.

Tool: `~/.claude/pane-msg`. Mailboxes: `~/.claude/tmux-state/mailbox/`.

## When you receive messages

Either the Stop-hook injects `📨 Queued pane-msg inbox message(s) … :` followed
by the message bodies (already consumed for you — just act on them), or you see
a `📨 pane-msg: run pane-msg read …` nudge in your prompt, in which case run:

```bash
~/.claude/pane-msg read      # auto-detects your pane, prints unread, marks consumed
```

Each message shows `type`, `from`, optional `ref`, timestamp, and a
self-contained body. Act on it as if `from` had asked you directly. To reply:

```bash
~/.claude/pane-msg send <from-target> --type answer --ref <ref> "your answer"
```

## Sending to another pane

```bash
# hand off a task — guarded nudge by default: wakes it now if idle+empty,
# otherwise the Stop-hook delivers on its next turn. Never clobbers input.
~/.claude/pane-msg send 4later:1.2 --type task --ref 4711 "Self-contained brief with file paths + context."

# question / status / note (same guarded-nudge default)
~/.claude/pane-msg send 4later:1.1 --type question "Which API version should the client target?"
~/.claude/pane-msg send 4later:1.1 --type status --ref 4711 "Done — committed <sha>, pushed branch."

# --silent: never nudge, always wait for the Stop-hook (low-priority drops)
~/.claude/pane-msg send 4later:1.2 --type note --silent "FYI, no rush."
```

- `<target>` is a tmux target `session:window.pane` (e.g. `4later:1.2`). Resolve
  from `~/.claude/panes.conf` like send-to-pane; pane **N** → `<prefix>.N`.
- `--type`: `task | question | answer | status | note` (default `note`).
- `--ref`: free-form (e.g. issue number) — keep it on replies so threads line up.
- `--from` auto-fills with your own pane; override only if needed.
- **Nudge control:**
  - **default (guarded nudge):** wakes the target if it's idle with an empty
    prompt, otherwise stays silent and lets the Stop-hook deliver. Never clobbers
    input. This is what you want almost always — just `send`.
  - `--silent`: never nudge; always wait for the Stop-hook. For low-priority
    drops you don't want waking an idle pane at all.
  - `--nudge`: explicit form of the default (guarded wake); kept for clarity.
  - `--force-nudge`: send-keys regardless — legacy/interactive only. **Avoid**;
    it can clobber the user's in-progress input.

## Why this over raw send-keys (send-to-pane)

- **Never clobbers the user's input** — the payload never goes to the prompt, and
  the optional nudge is suppressed whenever the user is typing.
- **No stuck paste** — long/multi-line/quoted bodies live in the file.
- **Audit trail** — one JSON line per message in `mailbox/<key>.inbox.jsonl`;
  `pane-msg status` shows unread counts.
- **Structured** — `type`/`ref` route answers back to the right thread.

Use raw **send-to-pane** only for genuinely interactive one-offs (e.g. typing
`yes` into a pane waiting on a confirmation). Use **pane-inbox** for task
handoff, questions, and status.

## Housekeeping

- `pane-msg status` — unread counts across all mailboxes.
- `pane-msg peek [<target>]` — show unread WITHOUT consuming.
- `pane-msg whoami` — your own tmux target (via `$TMUX_PANE`).
- Inbox files are append-only JSONL; `<key>.offset` tracks what's read. Delete
  the offset to re-show; delete the `.inbox.jsonl` to clear history.
