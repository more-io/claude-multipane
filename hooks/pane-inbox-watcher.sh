#!/usr/bin/env bash
# launchd entrypoint for the pane-inbox delivery watcher.
#
# A launchd agent (com.claude-multipane.pane-inbox-watcher) watches the mailbox
# trigger file (<mailbox>/.event, bumped by every `pane-msg send`) and runs this
# on each write. launchd's default PATH lacks /opt/homebrew/bin, where tmux and
# python3 live on Apple Silicon — without fixing PATH the sweeper can't reach
# tmux at all. Set a sane PATH, then run one bounded delivery sweep.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
# launchd runs with no LANG (C locale). The guard matches the multibyte "❯"
# prompt marker and strips escape spans — under C locale that byte-handling
# breaks and every pane looks "busy", so force a UTF-8 locale.
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
exec "$HOME/.claude/pane-msg" sweep --window 90 --interval 10
