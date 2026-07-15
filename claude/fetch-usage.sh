#!/bin/sh
# Fetches Claude API usage stats and writes them to /tmp/.claude_usage_cache.
# Line 1: five_hour.utilization (integer %)
# Line 2: seven_day.utilization (integer %)
# Line 3: five_hour.resets_at (raw ISO string, e.g. 2026-02-26T12:59:59.997656+00:00)
# Line 4: seven_day.resets_at (raw ISO string)
# All output is suppressed; meant to be run in background.

CACHE_FILE="/tmp/.claude_usage_cache"
TOKEN_CACHE="/tmp/.claude_token_cache"
TOKEN_TTL=900  # 15 minutes

# --- portable mtime: GNU/Linux `stat -c %Y` first (BSD's `stat -f` succeeds on
#     Linux as --file-system, so it must NOT be tried first), then BSD/macOS ---
file_mtime() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0
}

# --- read the raw credentials JSON: macOS Keychain first, then Linux file ---
read_creds() {
  # macOS: stored in the login Keychain
  creds=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
  if [ -n "$creds" ]; then
    printf '%s' "$creds"
    return
  fi
  # Linux: stored on disk
  claude_dir=${CLAUDE_HOME:-$HOME/.claude}
  if [ -f "$claude_dir/.credentials.json" ]; then
    cat "$claude_dir/.credentials.json" 2>/dev/null
  fi
}

# --- get token (with 15-min cache to avoid repeated credential reads) ---
token=""
if [ -f "$TOKEN_CACHE" ]; then
  cache_age=$(( $(date -u +%s) - $(file_mtime "$TOKEN_CACHE") ))
  if [ "$cache_age" -lt "$TOKEN_TTL" ]; then
    token=$(cat "$TOKEN_CACHE" 2>/dev/null)
  fi
fi

if [ -z "$token" ]; then
  creds_json=$(read_creds)
  if [ -z "$creds_json" ]; then
    exit 0
  fi
  token=$(printf '%s' "$creds_json" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
  if [ -z "$token" ]; then
    exit 0
  fi
  # write the token cache with owner-only permissions (avoid world-readable /tmp)
  (umask 077; printf '%s' "$token" > "$TOKEN_CACHE")
fi

usage_json=$(curl -s -m 3 \
  -H "accept: application/json" \
  -H "anthropic-beta: oauth-2025-04-20" \
  -H "authorization: Bearer $token" \
  -H "user-agent: claude-code/2.1.11" \
  "https://api.anthropic.com/oauth/usage" 2>/dev/null)

if [ -z "$usage_json" ]; then
  exit 0
fi

five_h_raw=$(printf '%s' "$usage_json" | jq -r '.five_hour.utilization // empty' 2>/dev/null)
seven_d_raw=$(printf '%s' "$usage_json" | jq -r '.seven_day.utilization // empty' 2>/dev/null)
five_h_reset=$(printf '%s' "$usage_json" | jq -r '.five_hour.resets_at // ""' 2>/dev/null)
seven_d_reset=$(printf '%s' "$usage_json" | jq -r '.seven_day.resets_at // ""' 2>/dev/null)

if [ -n "$five_h_raw" ] && [ -n "$seven_d_raw" ]; then
  five_h=$(printf "%.0f" "$five_h_raw")
  seven_d=$(printf "%.0f" "$seven_d_raw")
  printf '%s\n%s\n%s\n%s\n' "$five_h" "$seven_d" "$five_h_reset" "$seven_d_reset" > "$CACHE_FILE"
fi
