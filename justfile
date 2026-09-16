# ABOUTME: justfile for managing dotfile symlinks from this repo to home directory
# ABOUTME: also installs homebrew casks, formulae, and standalone tools

# homebrew casks to install/upgrade (use full tap path for custom taps)
_casks := "tednaleid/montty/montty tednaleid/limn/limn tednaleid/grounded/grounded"

# homebrew formulae to install/upgrade (use full tap path for custom taps)
_formulae := "git-lfs ruff shellcheck tednaleid/sumpig/sumpig tednaleid/veer/veer"

# standalone python scripts (uv single-file), linted and formatted by ruff
_scripts := "csess standup-digest glab-comment"

# claude plugin marketplaces to add/update (github owner/repo)
_claude_marketplaces := "astral-sh/claude-code-plugins anthropics/claude-plugins-official obra/superpowers-marketplace tednaleid/claude-plugins"

# claude plugins to install/update (plugin@marketplace)
_claude_plugins := "astral@astral-sh superpowers@superpowers-marketplace context-relay@tednaleid just-bootstrap@tednaleid onboard-codebase@tednaleid review-branch@tednaleid worktree@tednaleid"

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
    @echo "  just veer      - set up veer global rules"
    @echo "  just casks     - install/upgrade homebrew casks"
    @echo "  just formulae  - install/upgrade homebrew formulae"
    @echo "  just bun       - install/upgrade bun via homebrew"
    @echo "  just playwright - install playwright-cli (via bun) and its skill"
    @echo "  just csess     - set up the Claude Code session browser"
    @echo "  just standup-digest - set up the daily standup gatherer"
    @echo "  just glab-comment - set up the GitLab MR comment poster"
    @echo "  just test      - run the python unit tests"
    @echo "  just lint      - syntax-check zsh, shellcheck hooks, ruff the scripts, validate ghostty config"
    @echo "  just fmt       - ruff-fix and format the python scripts"
    @echo "  just check     - lint then test"
    @echo "  just install-hooks - install the pre-commit hook that runs just check"
    @echo "  just dock-spacer - add a spacer tile to the macOS dock"

# set up all dotfiles
all: git zsh ssh ghostty atuin claude casks formulae bun playwright csess standup-digest glab-comment veer install-hooks

# copy every file under source dir into dest dir, preserving subdirectory structure
# skips files whose dest dir is a symlink pointing outside dest, so a symlinked
# skill (e.g. ~/.claude/skills/commit -> another repo) isn't silently overwritten
_copy_dir source dest:
    #!/usr/bin/env bash
    set -e
    if [ ! -d "{{source}}" ]; then
        echo "⚠ {{source}} does not exist, skipping"
        exit 0
    fi
    mkdir -p "{{dest}}"
    destroot=$(cd "{{dest}}" && pwd -P)
    cd "{{source}}"
    find . -type f | while read -r rel; do
        rel="${rel#./}"
        destfile="{{dest}}/$rel"
        mkdir -p "$(dirname "$destfile")"
        destdir=$(cd "$(dirname "$destfile")" && pwd -P)
        case "$destdir/" in
            "$destroot"/) ;;
            "$destroot"/*) ;;
            *)
                echo "⚠ Skipped $rel: dest resolves outside {{dest}} -> $destdir"
                continue
                ;;
        esac
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
claude: claude-cli claude-md claude-skills claude-settings claude-install-plugins

# install the claude code CLI if it isn't already on PATH (it self-updates after that)
claude-cli:
    #!/usr/bin/env bash
    set -euo pipefail
    export PATH="{{home_directory()}}/.local/bin:$PATH"
    if command -v claude &>/dev/null; then
        echo "✓ claude $(claude --version) already installed"
        exit 0
    fi
    echo "→ Installing claude code"
    curl -fsSL https://claude.ai/install.sh | bash
    echo "✓ claude $(claude --version) installed"

[unix]
claude-md:
    @mkdir -p {{home_directory()}}/.claude
    @just _symlink {{justfile_directory()}}/.claude/CLAUDE.md {{home_directory()}}/.claude/CLAUDE.md

# windows has no reliable user symlink, so copy instead (re-run after editing the repo copy)
[windows]
claude-md:
    #!/usr/bin/env bash
    set -euo pipefail
    home=$(cygpath -u '{{home_directory()}}')
    src=$(cygpath -u '{{justfile_directory()}}')/.claude/CLAUDE.md
    mkdir -p "$home/.claude"
    cp "$src" "$home/.claude/CLAUDE.md"
    echo "✓ Copied CLAUDE.md -> $home/.claude/CLAUDE.md"

[unix]
claude-skills:
    @just _copy_dir {{justfile_directory()}}/.claude/skills {{home_directory()}}/.claude/skills

[windows]
claude-skills:
    #!/usr/bin/env bash
    set -euo pipefail
    home=$(cygpath -u '{{home_directory()}}')
    src=$(cygpath -u '{{justfile_directory()}}')/.claude/skills
    just _copy_dir "$src" "$home/.claude/skills"

# patch claude settings.json with values from this repo
[unix]
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

# windows variant: normalize paths, run .sh statusline/hook via bash (dotfiles path must have no spaces)
[windows]
claude-settings:
    #!/usr/bin/env bash
    set -euo pipefail
    home=$(cygpath -u '{{home_directory()}}')
    dir_u=$(cygpath -u '{{justfile_directory()}}')
    dir_m=$(cygpath -m '{{justfile_directory()}}')
    settings="$home/.claude/settings.json"
    patch="$dir_u/claude-settings-patch.json"
    mkdir -p "$home/.claude"
    if [ ! -f "$settings" ]; then
        echo "{}" > "$settings"
    else
        cp "$settings" "$settings.bak"
        echo "backed up $settings -> $settings.bak"
    fi
    # forward-slash dotfiles dir; statusline + hook are .sh, so invoke them via bash
    resolved=$(sed \
        -e "s|__DOTFILES_DIR__/claude-statusline.sh|bash $dir_m/claude-statusline.sh|g" \
        -e "s|__DOTFILES_DIR__/claude-prompt-submit-hook.sh|bash $dir_m/claude-prompt-submit-hook.sh|g" \
        "$patch")
    # --argjson avoids process substitution, which is unreliable under Git Bash
    merged=$(jq --argjson patch "$resolved" '. * $patch' "$settings")
    echo "$merged" > "$settings"
    echo "✓ Patched $settings"

# install claude marketplace plugins and skills
claude-install-plugins:
    #!/usr/bin/env bash
    set -euo pipefail
    export PATH="{{home_directory()}}/.local/bin:$PATH"
    marketplaces=$(claude plugin marketplace list 2>&1)
    for repo in {{_claude_marketplaces}}; do
        if grep -qF "$repo" <<<"$marketplaces"; then
            echo "✓ $repo marketplace already added"
        else
            echo "→ Adding $repo marketplace"
            claude plugin marketplace add "$repo"
        fi
    done
    echo "→ Updating marketplaces"
    claude plugin marketplace update
    # scope-filtered: `plugin list` also reports project/local installs from other
    # repos, and `plugin update` only operates on the user scope
    installed=$(claude plugin list --json | jq -r '.[] | select(.scope == "user") | .id')
    for plugin in {{_claude_plugins}}; do
        if grep -qxF "$plugin" <<<"$installed"; then
            echo "→ Updating $plugin"
            claude plugin update "$plugin"
        else
            echo "→ Installing $plugin"
            claude plugin install "$plugin"
        fi
    done

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

# set up veer global rules and register the PreToolUse hook
# (binary install lives in `formulae`)
veer: veer-config veer-install

veer-config:
    @mkdir -p {{home_directory()}}/.config/veer
    @just _symlink {{justfile_directory()}}/veer_config.toml {{home_directory()}}/.config/veer/config.toml

# register the veer PreToolUse hook in ~/.claude/settings.json
# (idempotent: re-running updates the hook entry to current version/flags)
veer-install:
    @veer install --global

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

# install or upgrade homebrew formulae
formulae:
    #!/usr/bin/env bash
    set -e
    for formula in {{_formulae}}; do
        name="${formula##*/}"
        if brew list "$name" &>/dev/null; then
            output=$(brew upgrade "$formula" 2>&1) || true
            if echo "$output" | grep -q "already installed"; then
                echo "✓ $name is up to date"
            else
                echo "↑ $name upgraded"
                echo "$output"
            fi
        else
            echo "→ Installing $name"
            brew install "$formula"
        fi
    done

# (a standalone ~/.bun/bin/bun shadows brew's on PATH, so drop it; ~/.bun stays the
#  home for `bun add -g` packages and their bin symlinks like pi and playwright-cli)
# install or upgrade bun via homebrew
bun:
    #!/usr/bin/env bash
    set -e
    if brew list bun &>/dev/null; then
        output=$(brew upgrade bun 2>&1) || true
        if echo "$output" | grep -q "already installed"; then
            echo "✓ bun is up to date"
        else
            echo "↑ bun upgraded"
            echo "$output"
        fi
    else
        echo "→ Installing bun"
        brew install bun
    fi
    standalone={{home_directory()}}/.bun/bin/bun
    if [ -f "$standalone" ] && [ ! -L "$standalone" ]; then
        rm -f "$standalone" {{home_directory()}}/.bun/bin/bunx
        echo "✓ Removed standalone bun/bunx (brew now owns the bun runtime)"
    fi

# install or upgrade playwright-cli (bun global) and sync its bundled skill into ~/.claude/skills
playwright: bun
    #!/usr/bin/env bash
    set -e
    export BUN_INSTALL={{home_directory()}}/.bun
    echo "→ Installing/upgrading @playwright/cli (bun global)"
    bun add -g @playwright/cli@latest
    just _copy_dir "$BUN_INSTALL/install/global/node_modules/@playwright/cli/skills/playwright-cli" {{home_directory()}}/.claude/skills/playwright-cli

# add a spacer tile to the macOS dock (run once per spacer you want)
dock-spacer:
    defaults write com.apple.dock persistent-apps -array-add '{tile-data={}; tile-type="spacer-tile";}'
    sleep 1
    killall Dock

# set up csess, the Claude Code session browser
csess:
    @mkdir -p {{home_directory()}}/.local/bin
    @just _symlink {{justfile_directory()}}/csess {{home_directory()}}/.local/bin/csess

# set up standup-digest, the daily standup gatherer
standup-digest:
    @mkdir -p {{home_directory()}}/.local/bin
    @just _symlink {{justfile_directory()}}/standup-digest {{home_directory()}}/.local/bin/standup-digest

# set up glab-comment, the GitLab MR review comment poster
glab-comment:
    @mkdir -p {{home_directory()}}/.local/bin
    @just _symlink {{justfile_directory()}}/glab-comment {{home_directory()}}/.local/bin/glab-comment

# run the python unit tests
test:
    @uv run --with pytest --with iterfzf pytest tests/ -q

# syntax-check the zsh config, shellcheck the hook scripts, lint the python scripts, validate the ghostty config
lint:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{justfile_directory()}}"
    for f in zshrc zsh.d/*.sh zsh.d/*.zsh; do
        zsh -n "$f"
    done
    shellcheck claude-statusline.sh claude-prompt-submit-hook.sh
    ruff check {{_scripts}}
    ruff format --check {{_scripts}}
    ghostty=/Applications/Ghostty.app/Contents/MacOS/ghostty
    # piped so the validator never treats stdout as a terminal and clears the screen
    if [ -x "$ghostty" ]; then
        "$ghostty" +validate-config --config-file=ghostty_config 2>&1 | cat
    fi
    echo "✓ lint passed"

# apply ruff fixes and formatting to the python scripts
fmt:
    ruff check --fix {{_scripts}}
    ruff format {{_scripts}}

# lint then test (run by the pre-commit hook)
check: lint test

# install a git pre-commit hook that runs just check
install-hooks:
    #!/usr/bin/env bash
    set -euo pipefail
    hook="{{justfile_directory()}}/.git/hooks/pre-commit"
    cat > "$hook" << 'HOOK'
    #!/bin/sh
    # git exports these to hooks; they would leak into the temp repos the tests create
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_AUTHOR_DATE
    just check
    HOOK
    chmod +x "$hook"
    echo "✓ Installed pre-commit hook: $hook"
