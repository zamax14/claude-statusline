#!/bin/sh
input=$(cat)

# --- theme: load color roles from themes/<flavor>.sh (default: mocha) ---
# Built-in Mocha defaults so the statusline still renders if the theme is missing.
C_MODEL="250;179;135"; C_DIR="137;220;235"; C_BRANCH="203;166;247"
C_SEP="108;112;134"; C_LABEL="127;132;156"
C_GREEN="166;227;161"; C_YELLOW="249;226;175"; C_RED="243;139;168"

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd 2>/dev/null)
THEMES_DIR="${SCRIPT_DIR:-$HOME/.claude}/themes"
CLAUDE_DIR="${CLAUDE_HOME:-$HOME/.claude}"
flavor=$(cat "$CLAUDE_DIR/.statusline-theme" 2>/dev/null || echo mocha)
theme_file="$THEMES_DIR/${flavor}.sh"
[ -f "$theme_file" ] || theme_file="$THEMES_DIR/mocha.sh"
[ -f "$theme_file" ] && . "$theme_file"

# shellcheck source=lib.sh
. "${SCRIPT_DIR:-$HOME/.claude}/lib.sh"
layout=$(read_layout)

# --- model ---
model=$(echo "$input" | jq -r '.model.display_name // ""')

# --- folder ---
dir=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
dir_name=$(basename "$dir")

# --- git branch + working-tree changes ---
branch=""
changes_str=""
if [ -d "${dir}/.git" ] || git -C "$dir" rev-parse --git-dir > /dev/null 2>&1; then
  branch=$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null || git -C "$dir" rev-parse --short HEAD 2>/dev/null)
  porcelain=$(git -C "$dir" status --porcelain 2>/dev/null)
  if [ -n "$porcelain" ]; then
    n_added=$(printf '%s\n' "$porcelain" | grep -c '^??')
    n_deleted=$(printf '%s\n' "$porcelain" | grep -c '^.D\|^D.')
    n_total=$(printf '%s\n' "$porcelain" | grep -c '.')
    n_modified=$(( n_total - n_added - n_deleted ))
    changes_str="+${n_added} ~${n_modified} -${n_deleted}"
  fi
fi

# --- usage stats (5h / 7d) from cache ---
CACHE_FILE="/tmp/.claude_usage_cache"
five_h=""
seven_d=""
five_h_reset=""
seven_d_reset=""

if [ -f "$CACHE_FILE" ]; then
  { read -r five_h; read -r seven_d; read -r five_h_reset; read -r seven_d_reset; } < "$CACHE_FILE"
else
  bash "$CLAUDE_DIR/fetch-usage.sh" > /dev/null 2>&1 &
fi

# --- compute_delta: given a raw ISO timestamp, returns human-readable time until reset ---
compute_delta() {
  clean=$(echo "$1" | sed 's/\.[0-9]*//' | sed 's/[+-][0-9][0-9]:[0-9][0-9]$//' | sed 's/Z$//')
  # Portable epoch parse: GNU/Linux `date -d`, fallback to BSD/macOS `date -j -f`
  reset_epoch=$(TZ=UTC date -d "$clean" "+%s" 2>/dev/null \
    || TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$clean" "+%s" 2>/dev/null)
  if [ -z "$reset_epoch" ]; then return; fi
  now_epoch=$(date -u "+%s")
  diff=$(( reset_epoch - now_epoch ))
  if [ "$diff" -le 0 ]; then echo "now"; return; fi
  days=$(( diff / 86400 ))
  hours=$(( (diff % 86400) / 3600 ))
  minutes=$(( (diff % 3600) / 60 ))
  if [ "$days" -gt 0 ]; then
    echo "${days}d ${hours}h"
  elif [ "$hours" -gt 0 ]; then
    echo "${hours}h ${minutes}m"
  else
    echo "${minutes}m"
  fi
}

# --- context window ---
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
ctx_str=""
ctx_tokens_str=""
if [ -n "$used" ]; then
  used_int=$(printf "%.0f" "$used")
  ctx_str="${used_int}%"
  ctx_used=$(echo "$input" | jq -r '(.context_window.current_usage.cache_read_input_tokens + .context_window.current_usage.cache_creation_input_tokens + .context_window.current_usage.input_tokens + .context_window.current_usage.output_tokens) // empty' 2>/dev/null)
  ctx_total=$(echo "$input" | jq -r '.context_window.context_window_size // empty' 2>/dev/null)
  if [ -n "$ctx_used" ] && [ -n "$ctx_total" ]; then
    ctx_used_k=$(( ctx_used / 1000 ))
    ctx_total_k=$(( ctx_total / 1000 ))
    ctx_tokens_str="${ctx_used_k}k/${ctx_total_k}k"
  fi
fi

# --- usage_color: theme-driven — green < 50, yellow 50-79, red >= 80 ---
usage_color() {
  n=${1:-0}
  if [ "$n" -ge 80 ]; then
    printf '\033[38;2;%sm' "$C_RED"
  elif [ "$n" -ge 50 ]; then
    printf '\033[38;2;%sm' "$C_YELLOW"
  else
    printf '\033[38;2;%sm' "$C_GREEN"
  fi
}

# --- assemble output (colors from the loaded theme) ---
SEP="\033[38;2;${C_SEP}m • \033[0m"
BAR_SEP="\033[38;2;${C_SEP}m | \033[0m"
LABEL="\033[2m\033[38;2;${C_LABEL}m"
DELTA="\033[2m\033[38;2;${C_LABEL}m"
RST="\033[0m"

# render_limit <label> <pct> <reset-iso> -> prints "label ████░░ NN% ↻ delta", returns 1 if no data
render_limit() {
  local label=$1
  local pct=$2
  local reset_iso=$3
  [ -z "$pct" ] && return 1
  local delta=$(compute_delta "$reset_iso")
  local color=$(usage_color "$pct")
  printf "%b%s%b " "$LABEL" "$label" "$RST"
  printf "%b%s %s%%%b" "$color" "$(render_bar "$pct")" "$pct" "$RST"
  [ -n "$delta" ] && printf " %b↻ %s%b" "$DELTA" "$delta" "$RST"
  return 0
}

# render_segment <name> -> prints the segment's text, returns 1 if it has no data to show
render_segment() {
  case "$1" in
    model)
      [ -z "$model" ] && return 1
      printf "\033[1m\033[38;2;%sm%s\033[22m\033[0m" "$C_MODEL" "$model"
      ;;
    dir)
      [ -z "$dir_name" ] && return 1
      printf "\033[1m\033[38;2;%sm%s\033[22m\033[0m" "$C_DIR" "$dir_name"
      ;;
    branch)
      [ -z "$branch" ] && return 1
      printf "\033[1m\033[38;2;%sm%s\033[22m\033[0m" "$C_BRANCH" "$branch"
      ;;
    ctx)
      [ -z "$ctx_str" ] && return 1
      printf "%bctx%b " "$LABEL" "$RST"
      printf "%b%s%b" "$(usage_color "$used_int")" "$ctx_str" "$RST"
      [ -n "$ctx_tokens_str" ] && printf " %b(%s)%b" "$DELTA" "$ctx_tokens_str" "$RST"
      ;;
    session) render_limit session "$five_h" "$five_h_reset" || return 1 ;;
    week) render_limit week "$seven_d" "$seven_d_reset" || return 1 ;;
    changes)
      [ -z "$changes_str" ] && return 1
      printf "\033[38;2;%sm+%s\033[0m \033[38;2;%sm~%s\033[0m \033[38;2;%sm-%s\033[0m" \
        "$C_GREEN" "$n_added" "$C_YELLOW" "$n_modified" "$C_RED" "$n_deleted"
      ;;
    *) return 1 ;;
  esac
  return 0
}

# render_group <comma,separated,segments> -> prints the joined, rendered text for one side of a line
render_group() {
  local list=$1
  local out=""
  local prev=""
  local seg seg_out
  for seg in $(printf '%s' "$list" | tr ',' ' '); do
    seg_out=$(render_segment "$seg") || continue
    if [ -n "$out" ]; then
      if [ "$prev" = "model" ]; then
        out="${out}$(printf "%b" "$BAR_SEP")"
      else
        out="${out}$(printf "%b" "$SEP")"
      fi
    fi
    out="${out}${seg_out}"
    prev=$seg
  done
  printf '%s' "$out"
}

# split the layout into lines on ';' — must run in the main shell (not a
# pipeline/subshell) so the "$@" set here survives into the loop below.
old_ifs=$IFS
IFS=';'
set -f
set -- $layout
set +f
IFS=$old_ifs

term_width=${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}

any_line=0
for group in "$@"; do
  case "$group" in
    *"|"*)
      left_text=$(render_group "${group%|*}")
      right_text=$(render_group "${group##*|}")
      [ -z "$left_text" ] && [ -z "$right_text" ] && continue
      [ "$any_line" -eq 1 ] && printf "\n"
      pad=$(( term_width - $(visible_len "$left_text") - $(visible_len "$right_text") ))
      [ "$pad" -lt 1 ] && pad=1
      printf '%s' "$left_text"
      i=0
      while [ "$i" -lt "$pad" ]; do printf ' '; i=$((i + 1)); done
      printf '%s' "$right_text"
      any_line=1
      ;;
    *)
      line=$(render_group "$group")
      [ -z "$line" ] && continue
      [ "$any_line" -eq 1 ] && printf "\n"
      printf '%s' "$line"
      any_line=1
      ;;
  esac
done
