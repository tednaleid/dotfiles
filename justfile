# ABOUTME: justfile for managing dotfile symlinks from this repo to home directory
# ABOUTME: based off of: https://github.com/mrnugget/dotfiles/blob/master/Makefile

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

# set up git configuration
git: gitconfig gitignore

# set up zsh configuration
zsh: zshrc zsh-dir

# set up claude configuration
claude: claude-md claude-commands claude-docs

# set up ghostty terminal configuration
ghostty: ghostty-config ghostty-shaders

# set up atuin shell history configuration
atuin: atuin-config

# individual file/directory symlink recipes
gitconfig:
    @test -e {{home_directory()}}/.gitconfig && exit 0 || true
    ln -sfn {{justfile_directory()}}/gitconfig {{home_directory()}}/.gitconfig

gitignore:
    @test -e {{home_directory()}}/.gitignore && exit 0 || true
    ln -sfn {{justfile_directory()}}/gitignore {{home_directory()}}/.gitignore

zshrc:
    @test -e {{home_directory()}}/.zshrc && exit 0 || true
    ln -sfn {{justfile_directory()}}/zshrc {{home_directory()}}/.zshrc

zsh-dir:
    @test -e {{home_directory()}}/.zsh.d && exit 0 || true
    ln -sfn {{justfile_directory()}}/zsh.d {{home_directory()}}/.zsh.d

claude-md:
    @mkdir -p {{home_directory()}}/.claude
    @test -e {{home_directory()}}/.claude/CLAUDE.md && exit 0 || true
    ln -sfn {{justfile_directory()}}/.claude/CLAUDE.md {{home_directory()}}/.claude/CLAUDE.md

claude-commands:
    @mkdir -p {{home_directory()}}/.claude
    @test -e {{home_directory()}}/.claude/commands && exit 0 || true
    ln -sfn {{justfile_directory()}}/.claude/commands {{home_directory()}}/.claude/commands

claude-docs:
    @mkdir -p {{home_directory()}}/.claude
    @test -e {{home_directory()}}/.claude/docs && exit 0 || true
    ln -sfn {{justfile_directory()}}/.claude/docs {{home_directory()}}/.claude/docs

ghostty-config:
    @mkdir -p {{home_directory()}}/.config/ghostty
    @test -e {{home_directory()}}/.config/ghostty/config && exit 0 || true
    ln -sfn {{justfile_directory()}}/ghostty_config {{home_directory()}}/.config/ghostty/config

ghostty-shaders:
    @mkdir -p {{home_directory()}}/.config/ghostty
    @test -e {{home_directory()}}/.config/ghostty/shaders && exit 0 || true
    ln -sfn {{justfile_directory()}}/ghostty_shaders {{home_directory()}}/.config/ghostty/shaders

atuin-config:
    @mkdir -p {{home_directory()}}/.config/atuin
    @test -e {{home_directory()}}/.config/atuin/config.toml && exit 0 || true
    ln -sfn {{justfile_directory()}}/atuin_config.toml {{home_directory()}}/.config/atuin/config.toml
