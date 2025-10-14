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
    ln -sfn {{justfile_directory()}}/gitconfig {{home_directory()}}/.gitconfig
    ln -sfn {{justfile_directory()}}/gitignore {{home_directory()}}/.gitignore

# set up zsh configuration
zsh: zshrc zsh-dir
    ln -sfn {{justfile_directory()}}/zshrc {{home_directory()}}/.zshrc
    ln -sfn {{justfile_directory()}}/zsh.d {{home_directory()}}/.zsh.d

# set up claude configuration
claude: claude-md claude-commands claude-docs
    mkdir -p {{home_directory()}}/.claude
    ln -sfn {{justfile_directory()}}/.claude/CLAUDE.md {{home_directory()}}/.claude/CLAUDE.md
    ln -sfn {{justfile_directory()}}/.claude/commands {{home_directory()}}/.claude/commands
    ln -sfn {{justfile_directory()}}/.claude/docs {{home_directory()}}/.claude/docs

# set up ghostty terminal configuration
ghostty: ghostty-config ghostty-shaders
    mkdir -p {{home_directory()}}/.config/ghostty
    ln -sfn {{justfile_directory()}}/ghostty_config {{home_directory()}}/.config/ghostty/config
    ln -sfn {{justfile_directory()}}/ghostty_shaders {{home_directory()}}/.config/ghostty/shaders

# set up atuin shell history configuration
atuin: atuin-config
    mkdir -p {{home_directory()}}/.config/atuin
    ln -sfn {{justfile_directory()}}/atuin_config.toml {{home_directory()}}/.config/atuin/config.toml

# verify source files exist (dependencies)
gitconfig:
    @test -f {{justfile_directory()}}/gitconfig || (echo "gitconfig not found" && exit 1)

gitignore:
    @test -f {{justfile_directory()}}/gitignore || (echo "gitignore not found" && exit 1)

zshrc:
    @test -f {{justfile_directory()}}/zshrc || (echo "zshrc not found" && exit 1)

zsh-dir:
    @test -d {{justfile_directory()}}/zsh.d || (echo "zsh.d directory not found" && exit 1)

claude-md:
    @test -f {{justfile_directory()}}/.claude/CLAUDE.md || (echo ".claude/CLAUDE.md not found" && exit 1)

claude-commands:
    @test -d {{justfile_directory()}}/.claude/commands || (echo ".claude/commands directory not found" && exit 1)

claude-docs:
    @test -d {{justfile_directory()}}/.claude/docs || (echo ".claude/docs directory not found" && exit 1)

ghostty-config:
    @test -f {{justfile_directory()}}/ghostty_config || (echo "ghostty_config not found" && exit 1)

ghostty-shaders:
    @test -d {{justfile_directory()}}/ghostty_shaders || (echo "ghostty_shaders directory not found" && exit 1)

atuin-config:
    @test -f {{justfile_directory()}}/atuin_config.toml || (echo "atuin_config.toml not found" && exit 1)
