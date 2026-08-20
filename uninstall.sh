#!/bin/sh
# Compatibility wrapper. New installs use install.sh for both actions.
set -e

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd 2>/dev/null)
if [ -f "$0" ] && [ -f "$SCRIPT_DIR/install.sh" ]; then
  exec sh "$SCRIPT_DIR/install.sh" uninstall "${1:-all}"
fi

RAW="${STATUSLINE_RAW_BASE:-https://raw.githubusercontent.com/zamax14/claude-statusline/main}"
command -v curl >/dev/null 2>&1 || { echo "error: curl is required" >&2; exit 1; }
curl -fsSL "$RAW/install.sh" | sh -s -- uninstall "${1:-all}"
