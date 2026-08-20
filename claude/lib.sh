# Shared helpers for statusline-command.sh and statusline-config.sh.
#
# Layout format: ';' separates lines, ',' separates segments within a line,
# '|' (optional, once per line) splits that line into a left group and a
# right group pushed to the terminal edge, e.g.
# "model,dir,branch;ctx;session,week|changes" is the 3-line default with a
# git-changes segment right-aligned on line 3. A layout with no ';' puts
# every segment on one line.

ALL_SEGMENTS="model,dir,branch,ctx,session,week,changes"
DEFAULT_LAYOUT="model,dir,branch;ctx;session,week"
ESC=$(printf '\033')

# render_bar <percent> [width] -> "●●●○○○○○○○○○○○○○○○○○"
# ~/.claude/.statusline-bar overrides the look: "<filled> <empty> [width] [half]".
# ponytail: dots and 20 cells are the default because plenty of terminal fonts
# ship no block elements (U+2588/U+2591, rendered as blank space) and a 10-cell
# bar only resolves 10% steps; the knobs stay for block glyphs, other widths,
# or a half-filled glyph.
render_bar() {
  local pct=${1:-0}
  local width=$2
  local cfg=$(cat "${CLAUDE_HOME:-$HOME/.claude}/.statusline-bar" 2>/dev/null)
  # positional params are safe to clobber here: both args are already captured
  set -f
  set -- $cfg
  set +f
  local fill=${1:-●}
  local void=${2:-○}
  local half=${4:-}
  width=${width:-${3:-20}}
  # count in half-cells so a half glyph can resolve the odd one
  local halves=$(( pct * width * 2 / 100 ))
  [ "$halves" -lt 0 ] && halves=0
  [ "$halves" -gt $(( width * 2 )) ] && halves=$(( width * 2 ))
  local filled=$(( halves / 2 ))
  local mid=$(( halves % 2 ))
  [ -z "$half" ] && mid=0
  local empty=$(( width - filled - mid ))
  local bar=""
  local i=0
  while [ "$i" -lt "$filled" ]; do bar="${bar}${fill}"; i=$((i + 1)); done
  [ "$mid" -eq 1 ] && bar="${bar}${half}"
  i=0
  while [ "$i" -lt "$empty" ]; do bar="${bar}${void}"; i=$((i + 1)); done
  printf '%s' "$bar"
}

# segment_enabled <name> <comma,separated,list> -> 0 if present, 1 if not
segment_enabled() {
  local name=$1
  local list=$2
  case ",$list," in
    *",$name,"*) return 0 ;;
    *) return 1 ;;
  esac
}

# read_layout -> current layout string from ~/.claude/.statusline-config, or the default
read_layout() {
  local claude_dir=${CLAUDE_HOME:-$HOME/.claude}
  local val=$(cat "$claude_dir/.statusline-config" 2>/dev/null)
  printf '%s' "${val:-$DEFAULT_LAYOUT}"
}

# flatten_layout <layout> -> flat comma list of every segment in the layout (line/align markers removed)
flatten_layout() {
  printf '%s' "$1" | tr ';|' ',,'
}

# visible_len <string> -> character count with ANSI "\033[...m" color/style codes stripped
visible_len() {
  printf '%s' "$1" | sed "s/${ESC}\[[0-9;]*m//g" | wc -m | tr -d ' '
}
