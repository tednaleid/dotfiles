# ABOUTME: justfile for managing dotfile symlinks from this repo to home directory
# ABOUTME: also installs homebrew casks and sets up syncthing ignore patterns

# homebrew casks to install/upgrade (use full tap path for custom taps)
_casks := "tednaleid/montty/montty tednaleid/limn/limn syncthing-app"

# default recipe - show help
default:
    @echo "To set up missing symlinks in your home directory, run: "
    @echo "  just all"
    @echo ""
    @echo "Available recipes:"
    @echo "  just all       - set up all dotfiles and install casks"
    @echo "  just git       - set up git config"
    @echo "  just zsh       - set up zsh config"
    @echo "  just ghostty   - set up ghostty terminal config"
    @echo "  just atuin     - set up atuin shell history config"
    @echo "  just claude    - set up claude AI config"
    @echo "  just casks     - install/upgrade homebrew casks"
    @echo "  just syncthing - set up syncthing ignore patterns for ~/code"

# set up all dotfiles
all: git zsh ghostty atuin claude casks syncthing

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

# set up syncthing ignore patterns for ~/code
syncthing: syncthing-ignore syncthing-spotlight syncthing-instructions

syncthing-ignore:
    #!/usr/bin/env bash
    src="{{justfile_directory()}}/stglobalignore"
    dest="{{home_directory()}}/code/.stglobalignore"
    ignore="{{home_directory()}}/code/.stignore"
    if [ -f "$dest" ] && cmp -s "$src" "$dest"; then
        echo "✓ $dest is up to date"
    else
        cp "$src" "$dest"
        echo "→ Copied stglobalignore to $dest"
    fi
    if [ -f "$ignore" ]; then
        echo "✓ $ignore already exists"
    else
        echo '#include .stglobalignore' > "$ignore"
        echo "→ Created $ignore"
    fi

syncthing-spotlight:
    #!/usr/bin/env bash
    marker="{{home_directory()}}/code/.metadata_never_index"
    if [ -f "$marker" ]; then
        echo "✓ $marker already exists"
    else
        touch "$marker"
        echo "→ Created $marker (Spotlight exclusion)"
    fi

syncthing-instructions:
    @echo ""
    @echo "=== Syncthing Setup ==="
    @echo ""
    @echo "Initial pairing (one-time):"
    @echo "  1. Open Syncthing web UI on both machines: http://127.0.0.1:8384"
    @echo "  2. Actions > Show ID on one machine, copy the Device ID"
    @echo "  3. Add Remote Device on the other machine, paste the ID"
    @echo "  4. Accept the device on the first machine"
    @echo "  5. Add ~/code as a shared folder, share it with the paired device"
    @echo ""
    @echo "Performance tuning (web UI):"
    @echo "  - Edit Folder > Advanced: Rescan Interval = 86400, Case Sensitive FS = No"
    @echo "  - Edit Device > Advanced: Number of Connections = 8 (for LAN)"
    @echo "  - Actions > Advanced > Options:"
    @echo "      Limit Bandwidth in LAN = No"
    @echo "      Set Low Priority = No"
    @echo "      Database Tuning = Large"
    @echo "  - System Settings > Spotlight > Privacy: add ~/code"
    @echo ""
    @echo "Verify sync with: sumpig fingerprint ~/code"
    @echo "Compare devices:  sumpig compare ~/code/.sumpig-fingerprints/*.txt"
