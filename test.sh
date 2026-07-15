#!/bin/sh
# Minimal self-check. No framework — plain asserts, exit 1 on first failure.
set -e

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd 2>/dev/null)
. "$SCRIPT_DIR/claude/lib.sh"

assert_eq() {
  if [ "$1" != "$2" ]; then
    echo "FAIL: expected '$2', got '$1' ($3)" >&2
    exit 1
  fi
}

assert_eq "$(render_bar 0 10)" "░░░░░░░░░░" "render_bar 0%"
assert_eq "$(render_bar 100 10)" "██████████" "render_bar 100%"
assert_eq "$(render_bar 50 10)" "█████░░░░░" "render_bar 50%"

segment_enabled model "model,dir,branch" || { echo "FAIL: model should be enabled" >&2; exit 1; }
! segment_enabled week "model,dir,branch" || { echo "FAIL: week should not be enabled" >&2; exit 1; }
! segment_enabled session "sessionx,dir" || { echo "FAIL: session should not match sessionx (substring false positive)" >&2; exit 1; }
segment_enabled sessionx "session,sessionx" || { echo "FAIL: sessionx should be enabled" >&2; exit 1; }

assert_eq "$(flatten_layout "model,dir;ctx;session,week")" "model,dir,ctx,session,week" "flatten_layout multi-line"
assert_eq "$(flatten_layout "model,dir,branch")" "model,dir,branch" "flatten_layout single-line passthrough"

# a segment moved to a different line is still found via the flattened form
layout="branch;model,dir;session,week"
segment_enabled branch "$(flatten_layout "$layout")" || { echo "FAIL: branch should be enabled after moving lines" >&2; exit 1; }
! segment_enabled ctx "$(flatten_layout "$layout")" || { echo "FAIL: ctx should be disabled (left out of layout)" >&2; exit 1; }

assert_eq "$(flatten_layout "model,dir|session,week;ctx")" "model,dir,session,week,ctx" "flatten_layout with right-align pipe"
segment_enabled changes "$ALL_SEGMENTS" || { echo "FAIL: changes should be a known segment" >&2; exit 1; }

assert_eq "$(visible_len "plain text")" "10" "visible_len with no ansi codes"
assert_eq "$(visible_len "$(printf '\033[1m\033[38;2;1;2;3mhi\033[0m')")" "2" "visible_len strips ansi codes"

echo "ok"

# End-to-end provider install/uninstall checks in an isolated HOME.
TEST_HOME=$(mktemp -d "${TMPDIR:-/tmp}/statusline-test.XXXXXX")
trap 'rm -rf "$TEST_HOME"' EXIT HUP INT TERM
export HOME="$TEST_HOME"
export CLAUDE_HOME="$TEST_HOME/.claude"
export CODEX_HOME="$TEST_HOME/.codex"

mkdir -p "$CLAUDE_HOME" "$CODEX_HOME"
cat > "$CLAUDE_HOME/settings.json" <<'EOF'
{
  "customSetting": true,
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{"type": "command", "command": "echo existing"}]
      }
    ]
  }
}
EOF

cat > "$CODEX_HOME/config.toml" <<'EOF'
model = "example-model"

[tui]
status_line = [
  "project-name",
  "context-used",
]
notifications = true

[history]
persistence = "save-all"
EOF

STATUSLINE_RAW_BASE="file://$SCRIPT_DIR" sh "$SCRIPT_DIR/install.sh" all >/dev/null

assert_eq "$(jq -r '.customSetting' "$CLAUDE_HOME/settings.json")" "true" "Claude install preserves unrelated settings"
assert_eq "$(jq '[.hooks.PreToolUse[] | .hooks[] | select(.command == "echo existing")] | length' "$CLAUDE_HOME/settings.json")" "1" "Claude install preserves unrelated hooks"
assert_eq "$(jq '[.hooks.PreToolUse[] | .hooks[] | select(.command | contains("fetch-usage.sh"))] | length' "$CLAUDE_HOME/settings.json")" "1" "Claude install adds one usage hook"

grep -q '^# codex-statusline: managed start$' "$CODEX_HOME/config.toml" || { echo "FAIL: Codex managed block missing" >&2; exit 1; }
grep -q '"five-hour-limit"' "$CODEX_HOME/config.toml" || { echo "FAIL: Codex balanced preset missing" >&2; exit 1; }
grep -q '"weekly-limit"' "$CODEX_HOME/config.toml" || { echo "FAIL: Codex weekly fallback missing" >&2; exit 1; }
grep -q '^notifications = true$' "$CODEX_HOME/config.toml" || { echo "FAIL: Codex install changed unrelated TUI config" >&2; exit 1; }
grep -q '^model = "example-model"$' "$CODEX_HOME/config.toml" || { echo "FAIL: Codex install changed top-level config" >&2; exit 1; }

# Reinstalling is idempotent: hooks/managed blocks are not duplicated and the
# original Codex value remains the one that uninstall will restore.
STATUSLINE_RAW_BASE="file://$SCRIPT_DIR" sh "$SCRIPT_DIR/install.sh" all >/dev/null
assert_eq "$(jq '[.hooks.PreToolUse[] | .hooks[] | select(.command | contains("fetch-usage.sh"))] | length' "$CLAUDE_HOME/settings.json")" "1" "Claude reinstall does not duplicate hooks"
assert_eq "$(grep -c '^# codex-statusline: managed start$' "$CODEX_HOME/config.toml")" "1" "Codex reinstall does not duplicate managed blocks"

"$CODEX_HOME/codex-statusline.sh" enable task-progress >/dev/null
grep -q '"task-progress"' "$CODEX_HOME/config.toml" || { echo "FAIL: Codex enable did not add item" >&2; exit 1; }
"$CODEX_HOME/codex-statusline.sh" enable branch-changes >/dev/null
grep -q '"branch-changes"' "$CODEX_HOME/config.toml" || { echo "FAIL: Codex branch changes item was rejected" >&2; exit 1; }
"$CODEX_HOME/codex-statusline.sh" disable git-branch >/dev/null
if grep '^status_line' "$CODEX_HOME/config.toml" | grep -q '"git-branch"'; then
  echo "FAIL: Codex disable did not remove item" >&2
  exit 1
fi
if "$CODEX_HOME/codex-statusline.sh" order 'model-with-reasoning,unknown-item' >/dev/null 2>&1; then
  echo "FAIL: Codex accepted an unknown item" >&2
  exit 1
fi

printf 'changes\nq\n' | STATUSLINE_TTY=/dev/stdin "$CLAUDE_HOME/statusline-config.sh" menu >/dev/null
grep -q 'changes' "$CLAUDE_HOME/.statusline-config" || { echo "FAIL: Claude interactive menu did not toggle segment" >&2; exit 1; }

sh "$SCRIPT_DIR/install.sh" uninstall all >/dev/null

grep -q '^status_line = \[$' "$CODEX_HOME/config.toml" || { echo "FAIL: Codex previous multiline value was not restored" >&2; exit 1; }
grep -q '"project-name"' "$CODEX_HOME/config.toml" || { echo "FAIL: Codex previous items were not restored" >&2; exit 1; }
if grep -q 'codex-statusline: managed' "$CODEX_HOME/config.toml"; then
  echo "FAIL: Codex managed markers remained after uninstall" >&2
  exit 1
fi
assert_eq "$(jq -r '.customSetting' "$CLAUDE_HOME/settings.json")" "true" "Claude uninstall preserves unrelated settings"
assert_eq "$(jq '[.hooks.PreToolUse[] | .hooks[] | select(.command == "echo existing")] | length' "$CLAUDE_HOME/settings.json")" "1" "Claude uninstall preserves unrelated hooks"
assert_eq "$(jq 'has("statusLine")' "$CLAUDE_HOME/settings.json")" "false" "Claude uninstall removes statusLine"

# The root menu supports the same install/uninstall flow without arguments.
printf '1\n2\n' | STATUSLINE_TTY=/dev/stdin sh "$SCRIPT_DIR/install.sh" >/dev/null
[ -x "$CODEX_HOME/codex-statusline.sh" ] || { echo "FAIL: interactive installer did not install Codex" >&2; exit 1; }
printf '2\n2\n' | STATUSLINE_TTY=/dev/stdin sh "$SCRIPT_DIR/install.sh" >/dev/null
[ ! -e "$CODEX_HOME/codex-statusline.sh" ] || { echo "FAIL: interactive installer did not uninstall Codex" >&2; exit 1; }

# A standalone downloaded installer fetches the new provider paths.
cp "$SCRIPT_DIR/install.sh" "$TEST_HOME/remote-install.sh"
STATUSLINE_RAW_BASE="file://$SCRIPT_DIR" sh "$TEST_HOME/remote-install.sh" install all >/dev/null
[ -x "$CLAUDE_HOME/statusline-command.sh" ] || { echo "FAIL: remote installer did not fetch Claude files" >&2; exit 1; }
[ -x "$CODEX_HOME/codex-statusline.sh" ] || { echo "FAIL: remote installer did not fetch Codex files" >&2; exit 1; }
STATUSLINE_RAW_BASE="file://$SCRIPT_DIR" sh "$TEST_HOME/remote-install.sh" uninstall all >/dev/null

echo "provider integration ok"
