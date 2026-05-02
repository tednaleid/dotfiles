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
just ssh       # ssh config and per-machine key (see below)
just ghostty   # ghostty terminal config and shaders
just atuin     # atuin shell history config
just claude    # claude AI config (see below)
just veer      # veer global PreToolUse rules (see below)
just formulae  # install homebrew formulae (sumpig, veer)
```

## SSH

The `just ssh` recipe sets up `~/.ssh/config` as a symlink and ensures a per-machine `~/.ssh/id_ed25519` key exists.

The model is **one key per machine**. Private keys never sync between machines — each Mac generates its own on first run and the public key gets registered with the services that need it (GitHub, any servers). When you lose a machine, you revoke just that one key.

On first run on a new Mac, the recipe will:

1. Create `~/.ssh` with `0700` perms
2. Symlink `~/.ssh/config` to `ssh/config` in this repo
3. If no `~/.ssh/id_ed25519` exists, run `ssh-keygen -t ed25519` interactively (pick a strong passphrase and stash it in the macOS Passwords app so it syncs via iCloud)
4. Cache the passphrase in the login keychain via `ssh-add --apple-use-keychain`
5. Copy the public key to the clipboard and print links to register it with GitHub

Subsequent runs are idempotent: if the key already exists, the recipe just prints the public key for reference.

The `ssh/config` here uses `AddKeysToAgent yes` and `UseKeychain yes`, so once the passphrase is cached in the login keychain you won't be re-prompted on subsequent sessions.

## Claude Code

The `just claude` recipe sets up:

* **CLAUDE.md** -- global instructions symlinked to `~/.claude/CLAUDE.md`
* **skills** -- skill definitions copied to `~/.claude/skills/`
* **settings** -- patches `~/.claude/settings.json` with values from `claude-settings-patch.json` (deep-merged via `jq`, preserving any existing keys)
* **plugins** -- installs astral-sh marketplace plugins

The `claude-settings` recipe merges keys from `claude-settings-patch.json` into the live settings file. This is a one-way patch (dotfiles -> live settings), so machine-specific keys in `settings.json` are preserved.

`claude-statusline.sh` is a status line script referenced by the patched settings. It displays the current directory, git branch, model name, and color-coded context token usage. The context indicator uses a smooth truecolor gradient that reads colors from the active Ghostty theme palette.

### Gradient configuration

An optional env var controls the context gradient:

* `CLAUDE_CONTEXT_GRADIENT` -- three comma-separated percentages: where the color stops being green, where it reaches yellow, and where it reaches red. Default `15,40,70`.

## veer

`just veer` symlinks `veer_config.toml` to `~/.config/veer/config.toml` -- the global rules veer applies to every project unless a project's own `.veer/config.toml` overrides them. The veer binary itself is installed by `just formulae` (or comes from a local dev build on PATH).

Because the live config is a symlink into the repo, `veer add --global` and `veer remove --global` write through to `veer_config.toml`. CLI edits land in the dotfiles repo automatically, ready to commit.

On the first machine to adopt this, move the existing real file in before running the recipe (the symlink helper skips if the destination already exists):

```
mv ~/.config/veer/config.toml ./veer_config.toml
just veer
```