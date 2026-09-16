# Onboarding

Personal macOS dotfiles. A `justfile` maps source config files in this repo to
their home-directory destinations (mostly symlinks, some copies), installs
Homebrew casks/formulae, and wires up Claude Code, veer, bun, and a clipboard
tool. There is no application to build; the repo is the source of truth for one
developer's machine setup.

## Stack
- Languages: zsh (config + prompt), Bash (recipe bodies + hooks), Python (standalone `uv` scripts: `csess`, `standup-digest`, `glab-comment`)
- Task runner: just (authoritative for all setup)
- Package managers: Homebrew (casks, formulae, bun), bun (global CLIs)
- Target: macOS (Darwin); `zsh.d` fragments are `.Darwin`-suffixed

## Common commands
- Apply everything: `just all`
- Per component: `just git` | `just zsh` | `just ssh` | `just ghostty` | `just atuin` | `just claude` | `just veer`
- Install tools: `just casks` | `just formulae` | `just bun` | `just playwright`
- List recipes: `just --list`

- Run tests: `just test` (pytest over `tests/`, covering the pure logic in the standalone scripts)
- Lint: `just lint` (zsh syntax, shellcheck on the hook scripts, ruff on the python scripts, ghostty config validation)
- Format: `just fmt` (ruff fix + format on the python scripts)
- Everything: `just check` (lint then test); `just install-hooks` wires it into a pre-commit hook, and `just all` includes that

## Architecture
Two install primitives drive everything: `_symlink` (idempotent, skips if the
destination exists) links a repo file into `$HOME`; `_copy_dir` copies a tree
file-by-file (used for `~/.claude/skills`, which must be real files). Homebrew
sets come from the `_casks` and `_formulae` variables at the top of the
justfile. Claude Code integration symlinks `CLAUDE.md`, copies skills,
deep-merges `claude-settings-patch.json` into the live `settings.json` via jq,
and installs marketplace plugins. veer's global config is symlinked so its CLI
writes back into the repo.

## Key paths
- `justfile` -- source of truth for all setup; start here
- `zshrc`, `zsh.d/` -- shell config; `zsh.d` holds OS/host-scoped sourced fragments
- `gitconfig`, `gitignore` -- git config and global ignore
- `ssh/config` -- ssh config (per-machine key is generated, never stored)
- `ghostty_config`, `ghostty_shaders/` -- terminal config and shaders
- `atuin_config.toml` -- shell history config
- `.claude/CLAUDE.md` -- global Claude instructions, symlinked to `~/.claude/CLAUDE.md`
- `.claude/skills/` -- skills copied to `~/.claude/skills/`
- `claude-settings-patch.json` -- deep-merged into `~/.claude/settings.json`
- `claude-statusline.sh`, `claude-prompt-submit-hook.sh` -- Claude Code statusline + UserPromptSubmit hook
- `veer_config.toml` -- global veer rules (symlinked; `veer add/remove --global` writes through)
- `csess` -- Claude Code session browser (uv single-file script), installed to `~/.local/bin`; indexes `~/.claude/projects` and resumes a session via fzf
- `tests/` -- pytest suite for the standalone scripts, run by `just test`
- `.llm/` -- gitignored scratch (benchmarks, throwaway test scripts)

## How to run
`just all` sets up a machine, or `just <component>` for one piece. Requires
`git`, `just`, and `jq`. On a fresh Mac, run `just formulae` before `just veer`
so the veer binary is on PATH. `just claude` installs the Claude Code CLI via
`install.sh` when it is not already on PATH.

## Dig deeper
- README.md -- detailed SSH (per-machine key), Claude Code (statusline, gradient env), and veer setup notes
