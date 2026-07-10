#!/bin/sh
# claude-statusline uninstaller. Reverts what install.sh did.
# Usage: sh uninstall.sh   (or: curl -fsSL .../uninstall.sh | sh)
set -e

CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"

echo "-> removing scripts, themes, skills and state"
rm -f "$CLAUDE_DIR/fetch-usage.sh" \
      "$CLAUDE_DIR/statusline-command.sh" \
      "$CLAUDE_DIR/statusline-theme.sh" \
      "$CLAUDE_DIR/statusline-config.sh" \
      "$CLAUDE_DIR/lib.sh" \
      "$CLAUDE_DIR/.statusline-config" \
      "$CLAUDE_DIR/.statusline-theme" \
      /tmp/.claude_usage_cache*
rm -rf "$CLAUDE_DIR/themes" \
       "$CLAUDE_DIR/skills/statusline-theme" \
       "$CLAUDE_DIR/skills/statusline-config"

if [ -f "$SETTINGS" ] && command -v jq >/dev/null 2>&1; then
  echo "-> cleaning settings.json (statusLine + fetch-usage hooks)"
  tmp=$(mktemp)
  # drop our statusLine, strip fetch-usage.sh hooks, then prune empties
  jq 'del(.statusLine)
      | (.hooks.PreToolUse, .hooks.Stop) |=
          (if . == null then . else
             (map(del(.hooks[] | select(.command|test("fetch-usage.sh"))))
              | map(select((.hooks|length) > 0))) end)
      | (if (.hooks.PreToolUse|length)==0 then del(.hooks.PreToolUse) else . end)
      | (if (.hooks.Stop|length)==0      then del(.hooks.Stop)      else . end)
      | (if (.hooks|length)==0           then del(.hooks)           else . end)' \
     "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
else
  echo "-> skipping settings.json cleanup (no file or jq missing) — remove statusLine + fetch-usage hooks manually"
fi

echo "-> done. restart Claude Code."
