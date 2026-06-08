# Onboarding

Personal macOS dotfiles. A `justfile` maps source config files in this repo to
their home-directory destinations (mostly symlinks, some copies), installs
Homebrew casks/formulae, and wires up Claude Code, veer, bun, and a clipboard
tool. There is no application to build; the repo is the source of truth for one
developer's machine setup.

## Stack
- Languages: zsh (config + prompt), Bash (recipe bodies + hooks), Python (single `uv` script: `pb`)
- Task runner: just (authoritative for all setup)
- Package managers: Homebrew (casks, formulae, bun), bun (global CLIs)
- Target: macOS (Darwin); `zsh.d` fragments are `.Darwin`-suffixed

## Common commands
- Apply everything: `just all`
- Per component: `just git` | `just zsh` | `just ssh` | `just ghostty` | `just atuin` | `just claude` | `just veer` | `just pb`
- Install tools: `just casks` | `just formulae` | `just bun` | `just playwright`
- List recipes: `just --list`

There is no test, lint, format, or typecheck recipe; this repo is config, not an app.

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
- `pb` -- standalone clipboard tool (uv single-file script), installed to `~/.local/bin`
- `.llm/` -- gitignored scratch (benchmarks, throwaway test scripts)

## How to run
`just all` sets up a machine, or `just <component>` for one piece. Requires
`git`, `just`, and `jq`. On a fresh Mac, run `just formulae` before `just veer`
so the veer binary is on PATH.

## Dig deeper
- README.md -- detailed SSH (per-machine key), Claude Code (statusline, gradient env), and veer setup notes
