#!/bin/sh
# Toggle/reorder statusline segments and lines by writing to
# ~/.claude/.statusline-config. The statusline picks it up on the next render.
set -e

CLAUDE_DIR="${CLAUDE_HOME:-$HOME/.claude}"
STATE="$CLAUDE_DIR/.statusline-config"
TTY="${STATUSLINE_TTY:-/dev/tty}"

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd 2>/dev/null)
. "${SCRIPT_DIR:-$CLAUDE_DIR}/lib.sh"

current=$(read_layout)
flat=$(flatten_layout "$current")

print_status() {
  echo "current layout: $current"
  echo "lines:"
  old_ifs=$IFS
  IFS=';'
  set -f
  set -- $current
  set +f
  IFS=$old_ifs
  n=1
  for group in "$@"; do
    echo "  line $n: $group"
    n=$((n + 1))
  done
  echo "segments:"
  for seg in $(printf '%s' "$ALL_SEGMENTS" | tr ',' ' '); do
    if segment_enabled "$seg" "$flat"; then
      echo "  [x] $seg"
    else
      echo "  [ ] $seg"
    fi
  done
  echo
  echo "usage: statusline-config.sh menu"
  echo "       statusline-config.sh enable|disable <segment>"
  echo "       statusline-config.sh order '<line1,segs>;<line2,segs>;...'"
  echo "       (';' separates lines, ',' separates segments on the same line,"
  echo "        '|' once per line right-aligns everything after it to the terminal edge"
  echo "        — quote the argument, ';' and '|' are shell operators)"
}

interactive_menu() {
  [ -r "$TTY" ] || { echo "error: interactive input unavailable" >&2; exit 1; }
  exec 3< "$TTY"
  while :; do
    echo
    "$0" show
    echo "Type a segment name to toggle it, or: order, theme, q"
    printf "Choice: "
    IFS= read -r choice <&3 || break
    case "$choice" in
      q|quit|exit) break ;;
      order)
        printf "Layout: "
        IFS= read -r value <&3
        "$0" order "$value"
        ;;
      theme)
        "$SCRIPT_DIR/statusline-theme.sh"
        printf "Theme: "
        IFS= read -r value <&3
        "$SCRIPT_DIR/statusline-theme.sh" "$value"
        ;;
      *)
        if ! segment_enabled "$choice" "$ALL_SEGMENTS"; then
          echo "error: unknown choice '$choice'" >&2
        elif segment_enabled "$choice" "$(flatten_layout "$(read_layout)")"; then
          "$0" disable "$choice"
        else
          "$0" enable "$choice"
        fi
        ;;
    esac
  done
  exec 3<&-
}

case "${1:-}" in
  ""|show)
    print_status
    ;;
  menu)
    interactive_menu
    ;;
  enable)
    seg=$2
    if ! segment_enabled "$seg" "$ALL_SEGMENTS"; then
      echo "error: unknown segment '$seg' (known: $ALL_SEGMENTS)" >&2
      exit 1
    fi
    if segment_enabled "$seg" "$flat"; then
      echo "'$seg' already enabled"
    else
      # append to the last line of the current layout (into its right group, if it has one)
      case "$current" in
        *";"*) prefix="${current%;*}"; last="${current##*;}" ;;
        *) prefix=""; last="$current" ;;
      esac
      case "$last" in
        *"|"*)
          left="${last%|*}"
          right="${last##*|}"
          new_last="${left}|${right:+$right,}$seg"
          ;;
        *) new_last="${last:+$last,}$seg" ;;
      esac
      new="${prefix:+$prefix;}$new_last"
      printf '%s\n' "$new" > "$STATE"
      echo "enabled '$seg'"
    fi
    ;;
  disable)
    seg=$2
    if ! segment_enabled "$seg" "$flat"; then
      echo "'$seg' already disabled"
    else
      old_ifs=$IFS
      IFS=';'
      set -f
      set -- $current
      set +f
      IFS=$old_ifs
      new=""
      for group in "$@"; do
        case "$group" in
          *"|"*)
            gleft=$(printf '%s' "${group%|*}" | tr ',' '\n' | grep -v "^${seg}\$" | tr '\n' ',' | sed 's/,$//')
            gright=$(printf '%s' "${group##*|}" | tr ',' '\n' | grep -v "^${seg}\$" | tr '\n' ',' | sed 's/,$//')
            [ -z "$gleft" ] && [ -z "$gright" ] && continue
            filtered="${gleft}|${gright}"
            ;;
          *)
            filtered=$(printf '%s' "$group" | tr ',' '\n' | grep -v "^${seg}\$" | tr '\n' ',' | sed 's/,$//')
            [ -z "$filtered" ] && continue
            ;;
        esac
        new="${new:+$new;}$filtered"
      done
      printf '%s\n' "$new" > "$STATE"
      echo "disabled '$seg'"
    fi
    ;;
  order)
    list=$2
    if [ -z "$list" ]; then
      echo "error: provide a layout string, e.g. 'model,dir;ctx;session,week'" >&2
      exit 1
    fi
    for seg in $(flatten_layout "$list" | tr ',' ' '); do
      if ! segment_enabled "$seg" "$ALL_SEGMENTS"; then
        echo "error: unknown segment '$seg' (known: $ALL_SEGMENTS)" >&2
        exit 1
      fi
    done
    printf '%s\n' "$list" > "$STATE"
    echo "layout set to '$list'"
    ;;
  *)
    echo "error: unknown command '$1'" >&2
    print_status >&2
    exit 1
    ;;
esac
