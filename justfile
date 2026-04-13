# ABOUTME: justfile for managing dotfile symlinks from this repo to home directory
# ABOUTME: also installs homebrew casks and shared clipboard tool

# homebrew casks to install/upgrade (use full tap path for custom taps)
_casks := "tednaleid/montty/montty tednaleid/limn/limn tednaleid/grounded/grounded"

# default recipe - show help
default:
    @echo "To set up missing symlinks in your home directory, run: "
    @echo "  just all"
    @echo ""
    @echo "Available recipes:"
    @echo "  just all       - set up all dotfiles and install casks"
    @echo "  just git       - set up git config"
    @echo "  just zsh       - set up zsh config"
    @echo "  just ssh       - set up ssh config and per-machine key"
    @echo "  just ghostty   - set up ghostty terminal config"
    @echo "  just atuin     - set up atuin shell history config"
    @echo "  just claude    - set up claude AI config"
    @echo "  just casks     - install/upgrade homebrew casks"
    @echo "  just pb        - set up pb shared clipboard tool"
    @echo "  just dock-spacer - add a spacer tile to the macOS dock"

# set up all dotfiles
all: git zsh ssh ghostty atuin claude casks pb

# copy every file under source dir into dest dir, preserving subdirectory structure
_copy_dir source dest:
    #!/usr/bin/env bash
    set -e
    if [ ! -d "{{source}}" ]; then
        echo "⚠ {{source}} does not exist, skipping"
        exit 0
    fi
    cd "{{source}}"
    find . -type f | while read -r rel; do
        rel="${rel#./}"
        destfile="{{dest}}/$rel"
        mkdir -p "$(dirname "$destfile")"
        rm -f "$destfile"
        cp "{{source}}/$rel" "$destfile"
        echo "✓ Copied $rel"
    done

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

# set up ssh config and ensure a per-machine ed25519 key exists
ssh: ssh-dir ssh-config ssh-key

ssh-dir:
    @mkdir -p {{home_directory()}}/.ssh
    @chmod 700 {{home_directory()}}/.ssh

ssh-config:
    @just _symlink {{justfile_directory()}}/ssh/config {{home_directory()}}/.ssh/config

# generate a per-machine ed25519 key if one doesn't already exist
ssh-key:
    #!/usr/bin/env bash
    set -e
    key={{home_directory()}}/.ssh/id_ed25519
    if [ -f "$key" ]; then
        echo "✓ $key already exists"
        echo ""
        echo "public key:"
        cat "$key.pub"
        exit 0
    fi
    echo "→ Generating new ed25519 key for $USER@$(hostname -s)"
    echo "  (you will be prompted for a passphrase — pick a strong one and stash it in the Passwords app)"
    ssh-keygen -t ed25519 -C "$USER@$(hostname -s)" -f "$key"
    ssh-add --apple-use-keychain "$key"
    pbcopy < "$key.pub"
    echo ""
    echo "✓ key generated, passphrase stored in login keychain, public key copied to clipboard"
    echo ""
    echo "public key:"
    cat "$key.pub"
    echo ""
    echo "add this key to:"
    echo "  github auth:    https://github.com/settings/ssh/new"
    echo "  github signing: https://github.com/settings/ssh/new?type=signing  (if you sign commits)"
    echo "  any servers you ssh into (append to their ~/.ssh/authorized_keys)"

# set up claude configuration
claude: claude-md claude-skills claude-settings claude-install-plugins

claude-md:
    @mkdir -p {{home_directory()}}/.claude
    @just _symlink {{justfile_directory()}}/.claude/CLAUDE.md {{home_directory()}}/.claude/CLAUDE.md

claude-skills:
    @just _copy_dir {{justfile_directory()}}/.claude/skills {{home_directory()}}/.claude/skills

# patch claude settings.json with values from this repo
claude-settings:
    #!/usr/bin/env bash
    settings={{home_directory()}}/.claude/settings.json
    patch={{justfile_directory()}}/claude-settings-patch.json
    mkdir -p {{home_directory()}}/.claude
    if [ ! -f "$settings" ]; then
        echo "{}" > "$settings"
    else
        backup=$(mktemp /tmp/claude-settings.XXXXXX)
        cp "$settings" "$backup"
        echo "backed up ${settings} -> ${backup}"
    fi
    # substitute dotfiles dir placeholder then deep-merge into live settings
    resolved=$(sed "s|__DOTFILES_DIR__|{{justfile_directory()}}|g" "$patch")
    merged=$(jq -s '.[0] * .[1]' "$settings" <(echo "$resolved"))
    echo "$merged" > "$settings"
    echo "✓ Patched $settings"

# install claude marketplace plugins and skills
claude-install-plugins:
    #!/usr/bin/env bash
    if claude plugin marketplace list 2>&1 | grep -q 'astral-sh/claude-code-plugins'; then
        echo "✓ astral-sh marketplace already installed"
    else
        echo "→ Adding astral-sh marketplace"
        claude plugin marketplace add astral-sh/claude-code-plugins
    fi
    claude plugin install astral@astral-sh

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

# install or upgrade homebrew casks
casks:
    #!/usr/bin/env bash
    set -e
    for cask in {{_casks}}; do
        name="${cask##*/}"
        if brew list --cask "$name" &>/dev/null; then
            output=$(brew upgrade --cask "$cask" 2>&1) || true
            if echo "$output" | grep -q "already installed"; then
                echo "✓ $name is up to date"
            else
                echo "↑ $name upgraded"
                echo "$output"
            fi
        else
            echo "→ Installing $name"
            brew install --cask "$cask"
        fi
    done

# add a spacer tile to the macOS dock (run once per spacer you want)
dock-spacer:
    defaults write com.apple.dock persistent-apps -array-add '{tile-data={}; tile-type="spacer-tile";}'
    sleep 1
    killall Dock

# set up pb shared clipboard tool
pb:
    @mkdir -p {{home_directory()}}/.local/bin
    @mkdir -p {{home_directory()}}/code/pb
    @just _symlink {{justfile_directory()}}/pb {{home_directory()}}/.local/bin/pb
    @just _symlink {{justfile_directory()}}/pb-preview {{home_directory()}}/.local/bin/pb-preview
