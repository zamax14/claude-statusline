#!/bin/sh
# Configure Codex's native TUI status line without replacing the rest of config.toml.
set -e

CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
CONFIG="$CODEX_DIR/config.toml"
PREVIOUS="$CODEX_DIR/.codex-statusline-previous"

ALL_ITEMS="model-with-reasoning,reasoning,current-dir,project-name,git-branch,branch-changes,run-state,context-remaining,context-used,five-hour-limit,weekly-limit,codex-version,used-tokens,total-input-tokens,total-output-tokens,thread-id,thread-title,fast-mode,task-progress"
PRESET_MINIMAL="model-with-reasoning,current-dir,git-branch"
PRESET_BALANCED="model-with-reasoning,current-dir,git-branch,context-remaining,five-hour-limit,weekly-limit"
PRESET_FULL="model-with-reasoning,current-dir,git-branch,run-state,context-remaining,five-hour-limit,weekly-limit,task-progress"

known_item() {
  case ",$ALL_ITEMS," in
    *",$1,"*) return 0 ;;
    *) return 1 ;;
  esac
}

validate_items() {
  list=$1
  [ -n "$list" ] || { echo "error: item list cannot be empty" >&2; exit 1; }
  old_ifs=$IFS
  IFS=','
  set -f
  set -- $list
  set +f
  IFS=$old_ifs
  seen=","
  for item in "$@"; do
    [ -n "$item" ] || { echo "error: empty status-line item" >&2; exit 1; }
    known_item "$item" || { echo "error: unknown item '$item'" >&2; echo "known: $ALL_ITEMS" >&2; exit 1; }
    case "$seen" in
      *",$item,"*) echo "error: duplicate item '$item'" >&2; exit 1 ;;
    esac
    seen="${seen}${item},"
  done
}

to_toml_array() {
  list=$1
  old_ifs=$IFS
  IFS=','
  set -f
  set -- $list
  set +f
  IFS=$old_ifs
  out=""
  for item in "$@"; do
    out="${out}${out:+, }\"$item\""
  done
  printf '[%s]' "$out"
}

read_current() {
  [ -f "$CONFIG" ] || return 0
  awk '
    /^\[tui\][[:space:]]*($|#)/ { in_tui=1; next }
    /^\[/ { in_tui=0 }
    in_tui && /^[[:space:]]*status_line[[:space:]]*=/ { collecting=1 }
    collecting {
      text = text " " $0
      opens += gsub(/\[/, "[")
      closes += gsub(/\]/, "]")
      if (opens > 0 && opens <= closes) {
        sub(/^.*status_line[[:space:]]*=[[:space:]]*/, "", text)
        gsub(/[\[\]\"[:space:]]/, "", text)
        print text
        exit
      }
    }
  ' "$CONFIG"
}

write_managed() {
  list=$1
  validate_items "$list"
  value=$(to_toml_array "$list")
  mkdir -p "$CODEX_DIR"
  [ -f "$CONFIG" ] || : > "$CONFIG"
  tmp=$(mktemp "${CONFIG}.tmp.XXXXXX")
  save_previous=0
  if [ ! -e "$PREVIOUS" ]; then
    save_previous=1
    : > "$PREVIOUS"
  fi

  awk -v value="$value" -v previous="$PREVIOUS" -v save_previous="$save_previous" '
    function managed_block() {
      print "# codex-statusline: managed start"
      print "status_line = " value
      print "# codex-statusline: managed end"
    }
    function count_char(text, char, copy) {
      copy=text
      return gsub(char, "", copy)
    }
    /^# codex-statusline: managed start[[:space:]]*$/ {
      if (!inserted) { managed_block(); inserted=1 }
      skip_managed=1
      next
    }
    skip_managed {
      if ($0 ~ /^# codex-statusline: managed end[[:space:]]*$/) skip_managed=0
      next
    }
    /^\[/ {
      if (in_tui && !inserted) { managed_block(); inserted=1 }
      in_tui = ($0 ~ /^\[tui\][[:space:]]*($|#)/)
      saw_tui = saw_tui || in_tui
    }
    in_tui && !skip_status && /^[[:space:]]*status_line[[:space:]]*=/ {
      skip_status=1
      depth=count_char($0, "\\[") - count_char($0, "\\]")
      if (save_previous) print $0 >> previous
      if (depth <= 0) skip_status=0
      if (!inserted) { managed_block(); inserted=1 }
      next
    }
    skip_status {
      depth += count_char($0, "\\[") - count_char($0, "\\]")
      if (save_previous) print $0 >> previous
      if (depth <= 0) skip_status=0
      next
    }
    { print }
    END {
      if (!saw_tui) {
        if (NR > 0) print ""
        print "[tui]"
      }
      if (!inserted) managed_block()
    }
  ' "$CONFIG" > "$tmp"
  mv "$tmp" "$CONFIG"
}

restore_previous() {
  [ -f "$CONFIG" ] || { rm -f "$PREVIOUS"; return 0; }
  tmp=$(mktemp "${CONFIG}.tmp.XXXXXX")
  awk -v previous="$PREVIOUS" '
    /^# codex-statusline: managed start[[:space:]]*$/ {
      while ((getline line < previous) > 0) print line
      close(previous)
      skipping=1
      next
    }
    skipping {
      if ($0 ~ /^# codex-statusline: managed end[[:space:]]*$/) skipping=0
      next
    }
    { print }
  ' "$CONFIG" > "$tmp"
  mv "$tmp" "$CONFIG"
  rm -f "$PREVIOUS"
}

print_status() {
  current=$(read_current)
  echo "provider: codex"
  echo "config: $CONFIG"
  if [ -n "$current" ]; then
    echo "current items: $current"
  else
    echo "current items: (Codex default)"
  fi
  echo "presets: minimal, balanced, full"
  echo "known items: $ALL_ITEMS"
  echo "note: limit items are hidden when Codex receives no data for that window"
  echo
  echo "usage: codex-statusline.sh preset <minimal|balanced|full>"
  echo "       codex-statusline.sh order <comma,separated,items>"
  echo "       codex-statusline.sh enable|disable <item>"
  echo "       codex-statusline.sh reset"
}

case "${1:-}" in
  ""|show)
    print_status
    ;;
  preset)
    case "${2:-}" in
      minimal) list=$PRESET_MINIMAL ;;
      balanced) list=$PRESET_BALANCED ;;
      full) list=$PRESET_FULL ;;
      *) echo "error: unknown preset '${2:-}' (known: minimal, balanced, full)" >&2; exit 1 ;;
    esac
    write_managed "$list"
    echo "Codex status line set to '$2'"
    ;;
  order)
    [ -n "${2:-}" ] || { echo "error: provide a comma-separated item list" >&2; exit 1; }
    write_managed "$2"
    echo "Codex status line order updated"
    ;;
  enable)
    item=${2:-}
    known_item "$item" || { echo "error: unknown item '$item'" >&2; exit 1; }
    current=$(read_current)
    [ -n "$current" ] || current=$PRESET_BALANCED
    case ",$current," in
      *",$item,"*) echo "'$item' already enabled" ;;
      *) write_managed "$current,$item"; echo "enabled '$item'" ;;
    esac
    ;;
  disable)
    item=${2:-}
    known_item "$item" || { echo "error: unknown item '$item'" >&2; exit 1; }
    current=$(read_current)
    [ -n "$current" ] || current=$PRESET_BALANCED
    filtered=""
    old_ifs=$IFS
    IFS=','
    set -f
    set -- $current
    set +f
    IFS=$old_ifs
    for candidate in "$@"; do
      [ "$candidate" = "$item" ] || filtered="${filtered}${filtered:+,}$candidate"
    done
    [ -n "$filtered" ] || { echo "error: cannot disable the last item; use 'reset' to restore Codex defaults" >&2; exit 1; }
    if [ "$filtered" = "$current" ]; then
      echo "'$item' already disabled"
    else
      write_managed "$filtered"
      echo "disabled '$item'"
    fi
    ;;
  reset)
    restore_previous
    echo "Codex status line restored"
    ;;
  *)
    echo "error: unknown command '$1'" >&2
    print_status >&2
    exit 1
    ;;
esac
