# AI statusline

Status-line tools for **Claude Code** and **Codex CLI**, kept separate because each client exposes a different extension model.

![statusline](assets/statusline.svg)

| Client | Implementation | Configuration |
| --- | --- | --- |
| Claude Code | Custom shell renderer fed by Claude's `statusLine.command` JSON | `~/.claude/statusline-config.sh` |
| Codex CLI | Codex's native TUI footer | `tui.status_line` in `~/.codex/config.toml` |

## Repository layout

```text
claude/     renderer, usage fetcher, themes and Claude skills
codex/      native Codex status-line configurator and skill
install.sh  global interactive installer and uninstaller
test.sh     isolated provider smoke test
```

## Global installer

Run the menu directly from GitHub:

```sh
curl -fsSL https://raw.githubusercontent.com/JoseVelazcoH/claude-statusline/main/install.sh | sh
```

It asks whether to install or uninstall, then whether to act on Claude Code, Codex, or both.

For automation:

```sh
sh install.sh install claude
sh install.sh install codex
sh install.sh install all
sh install.sh uninstall claude
sh install.sh uninstall codex
sh install.sh uninstall all
```

The old `sh install.sh codex` shorthand and `uninstall.sh` wrapper remain available.

## Claude Code

Open the interactive configurator from a terminal:

```sh
~/.claude/statusline-config.sh menu
```

The menu toggles `model`, `dir`, `branch`, `ctx`, `session`, `week`, and `changes`; it can also change the complete layout or Catppuccin theme. Non-interactive commands remain available:

```sh
~/.claude/statusline-config.sh show
~/.claude/statusline-config.sh enable changes
~/.claude/statusline-config.sh disable branch
~/.claude/statusline-config.sh order 'model,dir,branch;ctx;session,week'
~/.claude/statusline-theme.sh latte
```

The usage bars read `~/.claude/.statusline-bar`, format `<filled> <empty> [width] [half]`, defaulting to `● ○ 20` — dots because they exist in every terminal font (`█`/`░` render as blank space in fonts without block elements), 20 cells because that resolves 5% steps:

```sh
printf '█ ░ 10\n'    > ~/.claude/.statusline-bar   # block bar, 10 cells -> 10% steps
printf '● ○ 10 ◐\n'  > ~/.claude/.statusline-bar   # 5% steps without widening the line
```

`session` and `week` also have a compact style that drops the bar and keeps only the reset time:

```sh
~/.claude/statusline-config.sh style compact   # "reset ↻ 3h 54m • ↻ 1d 21h"
~/.claude/statusline-config.sh style full      # "session ●●○○○○○○○○○○○○○○○○○○ 13% ↻ 3h 54m" (default)
```

| Segment   | Shows                                                        |
| --------- | ------------------------------------------------------------ |
| `model`   | Model display name                                           |
| `dir`     | Current folder                                               |
| `branch`  | Git branch                                                   |
| `ctx`     | Context-window usage                                         |
| `session` | 5h usage limit                                               |
| `week`    | 7d usage limit                                               |
| `changes` | Git working tree (`+2 ~3 -1`), hidden when the tree is clean |

Inside Claude Code, use `/statusline-config` with `show`, `enable`, `disable`, or `order`. Claude also provides its own `/statusline` command, which generates or edits a status-line script from natural-language instructions.

Claude's documented extension point executes a command, sends session JSON through stdin, and renders stdout. It does not expose a third-party native configuration panel, so this project's menu runs in the terminal rather than inside Claude's TUI. See [Anthropic's status-line documentation](https://code.claude.com/docs/en/statusline).

## Codex CLI

Codex renders the footer natively. This project only manages its ordered fields and preserves the previous `status_line` value for uninstall:

```sh
~/.codex/codex-statusline.sh show
~/.codex/codex-statusline.sh preset minimal
~/.codex/codex-statusline.sh preset balanced
~/.codex/codex-statusline.sh preset full
~/.codex/codex-statusline.sh enable weekly-limit
~/.codex/codex-statusline.sh order 'model-with-reasoning,current-dir,git-branch,context-remaining'
~/.codex/codex-statusline.sh reset
```

The `balanced` and `full` presets include both `five-hour-limit` and `weekly-limit`. Codex hides a limit field when the active account/session does not provide data for that time window. For example, if Codex reports only a weekly window, `five-hour-limit` stays blank and `weekly-limit` is the visible fallback.

Codex also has the native `/statusline` menu. The ordered identifiers are stored in [`tui.status_line`](https://learn.chatgpt.com/docs/config-file/config-reference#configtoml).

## Dependencies

- Remote setup: `curl`.
- Claude Code: `jq`; `git` is optional for repository information.
- Codex: POSIX shell tools and Codex CLI.

## Test

```sh
sh test.sh
```
