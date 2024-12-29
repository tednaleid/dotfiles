# based off of: https://github.com/mrnugget/dotfiles/blob/master/Makefile

.PHONY: default all git zsh ghostty atuin

default:
	@echo "To set up missing symlinks in your home directory, run: "
	@echo "  make all"

DOTFILE_PATH := $(shell pwd)

all: git zsh ghostty atuin

# % is a wildcard, $^ is the right side of the colon, $@ is the left side of the colon
# so this target will create a symlink from the right side to the left side
$(HOME)/.%: %
	ln -sf $(DOTFILE_PATH)/$^ $@

git: $(HOME)/.gitconfig $(HOME)/.gitignore
zsh: $(HOME)/.zshrc $(HOME)/.zsh.d

$(HOME)/.config/ghostty/config:
	mkdir -p $(HOME)/.config/ghostty
	ln -sf $(DOTFILE_PATH)/ghostty_config $(HOME)/.config/ghostty/config

ghostty: $(HOME)/.config/ghostty/config

$(HOME)/.config/atuin/config.toml:
	mkdir -p $(HOME)/.config/atuin
	ln -sf $(DOTFILE_PATH)/atuin_config.toml $(HOME)/.config/atuin/config.toml

atuin: $(HOME)/.config/atuin/config.toml