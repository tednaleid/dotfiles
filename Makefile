# based off of: https://github.com/mrnugget/dotfiles/blob/master/Makefile

.PHONY: default all git zsh ghostty atuin claude

default:
	@echo "To set up missing symlinks in your home directory, run: "
	@echo "  make all"

DOTFILE_PATH := $(shell pwd)

all: git zsh ghostty atuin claude

# % is a wildcard, $^ is the right side of the colon, $@ is the left side of the colon
# so this target will create a symlink from the right side to the left side
$(HOME)/.%: %
	ln -sf $(DOTFILE_PATH)/$^ $@

git: $(HOME)/.gitconfig $(HOME)/.gitignore
zsh: $(HOME)/.zshrc $(HOME)/.zsh.d

$(HOME)/.claude/CLAUDE.md:
	mkdir -p $(HOME)/.claude
	ln -sf $(DOTFILE_PATH)/.claude/CLAUDE.md $@

$(HOME)/.claude/commands:
	ln -sf $(DOTFILE_PATH)/.claude/commands $@

$(HOME)/.claude/docs:
	ln -sf $(DOTFILE_PATH)/.claude/docs $@

claude: $(HOME)/.claude/CLAUDE.md $(HOME)/.claude/commands $(HOME)/.claude/docs

$(HOME)/.config/ghostty/config:
	mkdir -p $(HOME)/.config/ghostty
	ln -sf $(DOTFILE_PATH)/ghostty_config $(HOME)/.config/ghostty/config

$(HOME)/.config/ghostty/shaders:
	mkdir -p $(HOME)/.config/ghostty
	ln -sf $(DOTFILE_PATH)/ghostty_shaders $(HOME)/.config/ghostty/shaders

ghostty: $(HOME)/.config/ghostty/config $(HOME)/.config/ghostty/shaders

$(HOME)/.config/atuin/config.toml:
	mkdir -p $(HOME)/.config/atuin
	ln -sf $(DOTFILE_PATH)/atuin_config.toml $(HOME)/.config/atuin/config.toml

atuin: $(HOME)/.config/atuin/config.toml