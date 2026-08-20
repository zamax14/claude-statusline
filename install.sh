#!/bin/sh
# Global installer for the Claude Code and Codex status lines.
# Interactive: sh install.sh
# Automated:  sh install.sh <install|uninstall> <claude|codex|all>
set -e

RAW="${STATUSLINE_RAW_BASE:-https://raw.githubusercontent.com/zamax14/claude-statusline/main}"
CLAUDE_DIR="${CLAUDE_HOME:-$HOME/.claude}"
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
TTY="${STATUSLINE_TTY:-/dev/tty}"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd 2>/dev/null)
LOCAL_DIR=
[ -f "$0" ] && LOCAL_DIR=$SCRIPT_DIR

install_file() {
  relative=$1
  destination=$2
  if [ -n "$LOCAL_DIR" ] && [ -f "$LOCAL_DIR/$relative" ]; then
    cp "$LOCAL_DIR/$relative" "$destination"
  else
    command -v curl >/dev/null 2>&1 || { echo "error: curl is required for remote installation" >&2; exit 1; }
    curl -fsSL "$RAW/$relative" -o "$destination"
  fi
}

read_source_file() {
  relative=$1
  if [ -n "$LOCAL_DIR" ] && [ -f "$LOCAL_DIR/$relative" ]; then
    cat "$LOCAL_DIR/$relative"
  else
    command -v curl >/dev/null 2>&1 || { echo "error: curl is required for remote installation" >&2; exit 1; }
    curl -fsSL "$RAW/$relative"
  fi
}

install_claude() {
  command -v jq >/dev/null 2>&1 || { echo "error: jq is required for Claude Code" >&2; exit 1; }
  settings="$CLAUDE_DIR/settings.json"
  mkdir -p "$CLAUDE_DIR/themes" "$CLAUDE_DIR/skills/statusline-theme" "$CLAUDE_DIR/skills/statusline-config"

  echo "-> [claude] installing renderer and configurators"
  for file in fetch-usage.sh statusline-command.sh statusline-theme.sh statusline-config.sh lib.sh; do
    install_file "claude/$file" "$CLAUDE_DIR/$file"
  done
  chmod +x "$CLAUDE_DIR/fetch-usage.sh" "$CLAUDE_DIR/statusline-command.sh" \
    "$CLAUDE_DIR/statusline-theme.sh" "$CLAUDE_DIR/statusline-config.sh"

  for theme in mocha macchiato frappe latte; do
    install_file "claude/themes/$theme.sh" "$CLAUDE_DIR/themes/$theme.sh"
  done
  for skill in statusline-theme statusline-config; do
    install_file "claude/skills/$skill/SKILL.md" "$CLAUDE_DIR/skills/$skill/SKILL.md"
  done

  echo "-> [claude] configuring settings.json"
  new_settings=$(read_source_file claude/settings.json)
  if [ -f "$settings" ]; then
    merged=$(jq -s '
      def without_statusline_hook:
        map(.hooks = ((.hooks // []) | map(select(((.command // "") | contains("fetch-usage.sh")) | not))))
        | map(select((.hooks | length) > 0));
      .[0] as $old | .[1] as $new
      | ($old * $new)
      | .hooks.PreToolUse = ((($old.hooks.PreToolUse // []) | without_statusline_hook) + ($new.hooks.PreToolUse // []))
      | .hooks.Stop = ((($old.hooks.Stop // []) | without_statusline_hook) + ($new.hooks.Stop // []))
    ' "$settings" - <<EOF
$new_settings
EOF
)
    printf '%s\n' "$merged" > "$settings"
  else
    printf '%s\n' "$new_settings" > "$settings"
  fi
  echo "-> [claude] installed. Configure with: $CLAUDE_DIR/statusline-config.sh menu"
}

uninstall_claude() {
  settings="$CLAUDE_DIR/settings.json"
  echo "-> [claude] removing renderer, themes, skills and state"
  rm -f "$CLAUDE_DIR/fetch-usage.sh" \
        "$CLAUDE_DIR/statusline-command.sh" \
        "$CLAUDE_DIR/statusline-theme.sh" \
        "$CLAUDE_DIR/statusline-config.sh" \
        "$CLAUDE_DIR/lib.sh" \
        "$CLAUDE_DIR/.statusline-config" \
        "$CLAUDE_DIR/.statusline-theme" \
        /tmp/.claude_usage_cache* \
        /tmp/.claude_token_cache*
  rm -rf "$CLAUDE_DIR/themes" "$CLAUDE_DIR/skills/statusline-theme" "$CLAUDE_DIR/skills/statusline-config"

  if [ -f "$settings" ] && command -v jq >/dev/null 2>&1; then
    tmp=$(mktemp)
    jq 'del(.statusLine)
        | (.hooks.PreToolUse, .hooks.Stop) |=
            (if . == null then . else
               (map(.hooks = ((.hooks // []) | map(select(((.command // "") | contains("fetch-usage.sh")) | not))))
                | map(select((.hooks | length) > 0))) end)
        | (if ((.hooks.PreToolUse // []) | length) == 0 then del(.hooks.PreToolUse) else . end)
        | (if ((.hooks.Stop // []) | length) == 0 then del(.hooks.Stop) else . end)
        | (if ((.hooks // {}) | length) == 0 then del(.hooks) else . end)' \
       "$settings" > "$tmp" && mv "$tmp" "$settings"
  fi
}

install_codex() {
  echo "-> [codex] installing native status-line configurator"
  mkdir -p "$CODEX_DIR/skills/codex-statusline"
  install_file codex/statusline.sh "$CODEX_DIR/codex-statusline.sh"
  install_file codex/skills/codex-statusline/SKILL.md "$CODEX_DIR/skills/codex-statusline/SKILL.md"
  chmod +x "$CODEX_DIR/codex-statusline.sh"
  "$CODEX_DIR/codex-statusline.sh" preset balanced
  echo "-> [codex] installed. Codex shows only limits reported by the current account/session."
}

uninstall_codex() {
  echo "-> [codex] restoring previous native status line"
  if [ -f "$CODEX_DIR/codex-statusline.sh" ]; then
    sh "$CODEX_DIR/codex-statusline.sh" reset
  fi
  rm -f "$CODEX_DIR/codex-statusline.sh" "$CODEX_DIR/.codex-statusline-previous"
  rm -rf "$CODEX_DIR/skills/codex-statusline"
}

prompt_choices() {
  [ -r "$TTY" ] || { echo "error: interactive input unavailable; use: sh install.sh <install|uninstall> <claude|codex|all>" >&2; exit 1; }
  exec 3< "$TTY"
  echo "AI statusline setup"
  echo "  1) Install"
  echo "  2) Uninstall"
  printf "Action [1-2]: "
  IFS= read -r choice <&3
  case "$choice" in
    1|install) ACTION=install ;;
    2|uninstall) ACTION=uninstall ;;
    *) echo "error: invalid action" >&2; exit 1 ;;
  esac

  echo "  1) Claude Code"
  echo "  2) Codex"
  echo "  3) Both"
  printf "Provider [1-3]: "
  IFS= read -r choice <&3
  case "$choice" in
    1|claude) PROVIDER=claude ;;
    2|codex) PROVIDER=codex ;;
    3|all) PROVIDER=all ;;
    *) echo "error: invalid provider" >&2; exit 1 ;;
  esac
  exec 3<&-
}

case "${1:-}" in
  claude|codex|all) ACTION=install; PROVIDER=$1 ;; # backwards-compatible shorthand
  install|uninstall) ACTION=$1; PROVIDER=${2:-} ;;
  "") prompt_choices ;;
  *) echo "error: usage: sh install.sh [install|uninstall] [claude|codex|all]" >&2; exit 1 ;;
esac

[ -n "${PROVIDER:-}" ] || { echo "error: choose claude, codex, or all" >&2; exit 1; }
case "$ACTION:$PROVIDER" in
  install:claude) install_claude ;;
  install:codex) install_codex ;;
  install:all) install_claude; install_codex ;;
  uninstall:claude) uninstall_claude ;;
  uninstall:codex) uninstall_codex ;;
  uninstall:all) uninstall_claude; uninstall_codex ;;
  *) echo "error: choose claude, codex, or all" >&2; exit 1 ;;
esac

echo "-> done. Restart the affected client."
