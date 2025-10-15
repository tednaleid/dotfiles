# ABOUTME: justfile for managing dotfile symlinks from this repo to home directory

# default recipe - show help
default:
    @echo "To set up missing symlinks in your home directory, run: "
    @echo "  just all"
    @echo ""
    @echo "Available recipes:"
    @echo "  just all      - set up all dotfiles"
    @echo "  just git      - set up git config"
    @echo "  just zsh      - set up zsh config"
    @echo "  just ghostty  - set up ghostty terminal config"
    @echo "  just atuin    - set up atuin shell history config"
    @echo "  just claude   - set up claude AI config"

# set up all dotfiles
all: git zsh ghostty atuin claude

# create a symlink if it doesn't exist
_symlink source dest:
    #!/usr/bin/env bash
    if [ -e "{{dest}}" ]; then
        echo "✓ {{dest}} already exists"
        exit 0
    fi
    echo "→ Creating symlink: {{dest}} -> {{source}}"
    ln -sfn "{{source}}" "{{dest}}"

# set up git configuration
git: gitconfig gitignore

gitconfig:
    @just _symlink {{justfile_directory()}}/gitconfig {{home_directory()}}/.gitconfig

gitignore:
    @just _symlink {{justfile_directory()}}/gitignore {{home_directory()}}/.gitignore

# set up zsh configuration
zsh: zshrc zsh-dir

zshrc:
    @just _symlink {{justfile_directory()}}/zshrc {{home_directory()}}/.zshrc

zsh-dir:
    @just _symlink {{justfile_directory()}}/zsh.d {{home_directory()}}/.zsh.d

# set up claude configuration
claude: claude-md claude-commands claude-docs

claude-md:
    @mkdir -p {{home_directory()}}/.claude
    @just _symlink {{justfile_directory()}}/.claude/CLAUDE.md {{home_directory()}}/.claude/CLAUDE.md

claude-commands:
    @mkdir -p {{home_directory()}}/.claude
    @just _symlink {{justfile_directory()}}/.claude/commands {{home_directory()}}/.claude/commands

claude-docs:
    @mkdir -p {{home_directory()}}/.claude
    @just _symlink {{justfile_directory()}}/.claude/docs {{home_directory()}}/.claude/docs

# set up ghostty terminal configuration
ghostty: ghostty-config ghostty-shaders

ghostty-config:
    @mkdir -p {{home_directory()}}/.config/ghostty
    @just _symlink {{justfile_directory()}}/ghostty_config {{home_directory()}}/.config/ghostty/config

ghostty-shaders:
    @mkdir -p {{home_directory()}}/.config/ghostty
    @just _symlink {{justfile_directory()}}/ghostty_shaders {{home_directory()}}/.config/ghostty/shaders

# set up atuin shell history configuration
atuin: atuin-config

atuin-config:
    @mkdir -p {{home_directory()}}/.config/atuin
    @just _symlink {{justfile_directory()}}/atuin_config.toml {{home_directory()}}/.config/atuin/config.toml
