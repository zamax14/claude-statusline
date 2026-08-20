#!/bin/sh
# Switch the statusline color theme by writing the selected flavor to
# ~/.claude/.statusline-theme. The statusline picks it up on the next render.
set -e

CLAUDE_DIR="${CLAUDE_HOME:-$HOME/.claude}"
THEMES_DIR="$CLAUDE_DIR/themes"
STATE="$CLAUDE_DIR/.statusline-theme"

current=$(cat "$STATE" 2>/dev/null || echo mocha)

list_themes() {
  for f in "$THEMES_DIR"/*.sh; do
    [ -e "$f" ] || continue
    name=$(basename "$f" .sh)
    if [ "$name" = "$current" ]; then
      echo "  * $name"
    else
      echo "    $name"
    fi
  done
}

if [ -z "$1" ]; then
  echo "current theme: $current"
  echo "available themes:"
  list_themes
  echo
  echo "usage: statusline-theme <name>"
  exit 0
fi

if [ ! -f "$THEMES_DIR/$1.sh" ]; then
  echo "error: theme '$1' not found in $THEMES_DIR" >&2
  echo "available: $(list_themes | tr -s ' *' ' ' | tr '\n' ' ')" >&2
  exit 1
fi

printf '%s\n' "$1" > "$STATE"
echo "theme set to '$1'"
