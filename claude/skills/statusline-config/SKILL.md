---
name: statusline-config
description: Show, interactively configure, toggle, reorder, or right-align Claude status-line segments
argument-hint: "[show|menu|enable|disable|order] [segment-or-layout]"
allowed-tools: Bash(~/.claude/statusline-config.sh *)
disable-model-invocation: true
---

!`~/.claude/statusline-config.sh $ARGUMENTS`

Show the output above to the user exactly as printed, no extra commentary.
