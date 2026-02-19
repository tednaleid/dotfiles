# dotfiles

## Requirements

* git
* just (`brew install just`)
* jq (`brew install jq`) — used by `claude-settings` and `claude-statusline.sh`

## Install

To set up all of the files as symlinks in your home directory:

```
just all
```

Or set up individual components:

```
just git       # git config and global gitignore
just zsh       # zshrc and zsh.d
just ghostty   # ghostty terminal config and shaders
just atuin     # atuin shell history config
just claude    # claude AI config (see below)
```

## Claude Code

The `just claude` recipe sets up:

* **CLAUDE.md** — global instructions symlinked to `~/.claude/CLAUDE.md`
* **commands** — slash command definitions symlinked to `~/.claude/commands/`
* **docs** — reference docs symlinked to `~/.claude/docs/`
* **settings** — patches `~/.claude/settings.json` with values from `claude-settings-patch.json` (deep-merged via `jq`, preserving any existing keys)
* **plugins** — installs marketplace plugins

The `claude-settings` recipe merges keys from `claude-settings-patch.json` into the live settings file. This is a one-way patch (dotfiles → live settings), so machine-specific keys in `settings.json` are preserved.

`claude-statusline.sh` is a status line script referenced by the patched settings. It displays the current directory, git branch, model name, and color-coded context token usage.