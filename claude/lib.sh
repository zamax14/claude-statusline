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

# render_bar <percent> [width=10] -> "████░░░░░░"
render_bar() {
  local pct=${1:-0}
  local width=${2:-10}
  local filled=$(( pct * width / 100 ))
  [ "$filled" -gt "$width" ] && filled=$width
  [ "$filled" -lt 0 ] && filled=0
  local empty=$(( width - filled ))
  local bar=""
  local i=0
  while [ "$i" -lt "$filled" ]; do bar="${bar}█"; i=$((i + 1)); done
  i=0
  while [ "$i" -lt "$empty" ]; do bar="${bar}░"; i=$((i + 1)); done
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
