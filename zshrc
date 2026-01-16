# BASIC SETUP ######################################################### 

typeset -U PATH
autoload colors; colors;

XDG_CONFIG_HOME="$HOME/.config"

# HOMEBREW ############################################################ 

# $(brew --prefix) is slow, check existing env variable instead
if [ "$CPUTYPE" = "arm64" ]; then
  HOMEBREW_PREFIX=/opt/homebrew
else 
  HOMEBREW_PREFIX=/usr/local
fi

PATH=$HOMEBREW_PREFIX/bin:$HOMEBREW_PREFIX/sbin:$PATH

# HISTORY ############################################################ 

HISTFILE=$HOME/.zsh_history
HISTSIZE=50000
SAVEHIST=50000

setopt INC_APPEND_HISTORY     # Immediately append to history file.
setopt EXTENDED_HISTORY       # Record timestamp in history.
setopt HIST_EXPIRE_DUPS_FIRST # Expire duplicate entries first when trimming history.
setopt HIST_IGNORE_DUPS       # Dont record an entry that was just recorded again.
setopt HIST_IGNORE_ALL_DUPS   # Delete old recorded entry if new entry is a duplicate.
setopt HIST_FIND_NO_DUPS      # Do not display a line previously found.
setopt HIST_IGNORE_SPACE      # Dont record an entry starting with a space.
setopt HIST_SAVE_NO_DUPS      # Dont write duplicate entries in the history file.
setopt SHARE_HISTORY          # Share history between all sessions.
unsetopt HIST_VERIFY          # Execute commands using history (e.g.: using !$) immediately

# COMPLETION ############################################################ 

# Add completions installed through Homebrew packages
# See: https://docs.brew.sh/Shell-Completion
if type brew &>/dev/null; then
  FPATH="${HOMEBREW_PREFIX}/share/zsh/site-functions:${FPATH}"
fi

# Speed up completion init, see: https://gist.github.com/ctechols/ca1035271ad134841284
autoload -Uz compinit
for dump in ~/.zcompdump(N.mh+24); do
  compinit
done
compinit -C

# unsetopt menucomplete
unsetopt flowcontrol
setopt auto_menu
setopt complete_in_word
setopt always_to_end
setopt auto_pushd

zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'

# PROMPT ############################################################ 

setopt prompt_subst

# left prompt is just a > that is colored red if there are background jobs
local promptnormal="> %{$reset_color%}"
local promptjobs="%{$fg_bold[red]%}> %{$reset_color%}"
PROMPT='%(1j.$promptjobs.$promptnormal)'

# static prompt above where the cursor is
git_status_short() {
  if [[ ! -z $(git status --porcelain 2> /dev/null | tail -n1) ]]; then
    echo "%{$fg_bold[red]%} ✘%{$reset_color%}"
  else
    echo "%{$fg_bold[green]%} ✔%{$reset_color%}"
  fi
}

git_prompt_info() {
  # get the branch name if we're in a git repo, otherwise return
  ref=$(git symbolic-ref HEAD 2> /dev/null) || \
  ref=$(git rev-parse --short HEAD 2> /dev/null) || return

  # we're in a git repo, emit the branch name and 1 character status
  echo " %{$fg_bold[green]%}${ref#refs/heads/}$(git_status_short)%{$reset_color%}"
}

local timestamp="%{$fg[blue]%}%D{%H:%M:%S}%{$reset_color%}"
local working_directory=" %{$fg_bold[yellow]%}%(5~|%-2~/.../%2~|%4~)%{$reset_color%}"
local exit_code="%(?.. [%{$fg_bold[red]%}%?%{$reset_color%}])"

# create a line above the prompt to with info
precmd() {
    print -rP '${timestamp}${working_directory}$(git_prompt_info)${exit_code}'
}

# ALIASES/FUNCTIONS ############################################################ 

case $OSTYPE in
  darwin*)
    local aliasfile="${HOME}/.zsh.d/aliases.Darwin.sh"
    [[ -e ${aliasfile} ]] && source ${aliasfile}
  ;;
esac

alias gs='git status --short'
alias grh="git reset --hard"
alias grs="git reset --soft"
alias gd="git diff"
alias gds="git diff --stat"
alias gdh1="git diff HEAD~1"

alias dh='dirs -v'  # directory history

alias spwd='pwd | pbcopy'  # copy the current working directory to the clipboard

alias agrep='alias | grep -i'

# builtins don't have their own man page
alias manbi='man zshbuiltins'

# directory usage recursive
alias duc='du -sh *(/)'

# starts a server on port 8000 that makes the current directory browsable with a webbrowser
alias webshare='python -m SimpleHTTPServer'

alias ws='windsurf'

function drma() {
  ## docker remove all containers
  [[ -z $(docker ps -aq) ]] || docker rm -f $(docker ps -aq)
}

function drmav() {
  ## docker remove all volumes
  [[ -z $(docker volume ls -q) ]] || docker volume rm $(docker volume ls -q)
}

function epochToDate() {
  if [ -z $1 ] ; then
    echo "USAGE: epochToDate 1509821064514"
    return 1
  fi
  date -j -r $(($1 / 1000))
}

# cd into a git worktree with fzf fuzzy matching
wcd() {
  local worktree
  worktree=$(git worktree list | fzf --query="$1" --select-1 --exit-0 | awk '{print $1}')
  [[ -n "$worktree" ]] && cd "$worktree"
}

# ENV ################################################################# 

case $OSTYPE in
  darwin*)
    local envfile="${HOME}/.zsh.d/env.Darwin.sh"
    [[ -e ${envfile} ]] && source ${envfile}
  ;;
esac

export EDITOR=code
export WORDS=/usr/share/dict/words

# direnv
if type direnv &> /dev/null; then
  eval "$(direnv hook zsh)"
else
  echo "missing direnv, install with:"
  echo "brew install direnv"
fi

# atuin
if type atuin &> /dev/null; then
  eval "$(atuin init zsh)"
else
  echo "missing atuin, install with:"
  echo "brew install atuin"
fi

# fzf
if type fzf &> /dev/null; then
  local fzf_shell="/opt/homebrew/opt/fzf/shell"

  if [[ -d "${fzf_shell}" ]]; then
    export FZF_CTRL_R_OPTS="--min-height=20 --exact --preview 'echo {}' --preview-window down:3:wrap"
    export FZF_DEFAULT_COMMAND='rg --files --no-ignore --hidden --follow -g "!{.git,node_modules,build}/*" 2> /dev/null'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"

    export FZF_CTRL_T_OPTS=$'--min-height=20 --preview \'[[ $(file --mime {}) =~ binary ]] && echo {} is a binary file ||
                    (bat --style=numbers --color=always {} ||
                      cat {}) 2> /dev/null | head -500
    \''

    export FZF_DEFAULT_OPTS="
      --layout=reverse
      --info=inline
      --height=80%
      --bind '?:toggle-preview'
    "

    source "${fzf_shell}/completion.zsh" 2> /dev/null
    source "${fzf_shell}/key-bindings.zsh"
  else
    echo "fzf shell scripts not found, check installation"
  fi 
else
  echo "missing fzf, install with:"
  echo "brew install fzf"
fi

# mise
if type mise &> /dev/null; then
  eval "$(mise activate zsh)"
else
  echo "missing mise, install with:"
  echo "brew install mise"
fi

# PATH ################################################################

if [[ -d "$HOME/.cargo/bin" ]]; then
  export PATH="$HOME/.cargo/bin:$PATH"
fi

if [[ -d "$HOME/.local/bin" ]]; then
  export PATH="$HOME/.local/bin:$PATH"
fi

if [[ -d "$HOME/bin" ]]; then
  export PATH="$HOME/bin:$PATH"
fi

if [[ -d "$HOME/.codeium/windsurf/bin" ]]; then
  export PATH="$HOME/.codeium/windsurf/bin:$PATH"
fi

# PRIVATE / HOST SPECIFIC ############################################ 

# Include private stuff that's not supposed to show up in the dotfiles repo
local private="${HOME}/.zsh.d/private.sh"
if [ -e ${private} ]; then
  . ${private}
fi

# Include host specific settings that likely won't apply to other machines
# HOST sometimes has .local on the end for some reason, this seems more consistent
local SIMPLE_HOST=$(hostname -s)
local this_host="${HOME}/.zsh.d/${SIMPLE_HOST}.sh"
[[ -e ${this_host} ]] && source ${this_host}

# sometimes, we have things we don't want checked into git, so also support a nonshared.sh as an alternative
local nonsharedfile="${HOME}/.zsh.d/nonshared.sh"
[[ -e ${nonsharedfile} ]] && source ${nonsharedfile}

# bun
export BUN_INSTALL="$HOME/.bun"
if [[ -d "$BUN_INSTALL/bin" ]]; then
  export PATH="$BUN_INSTALL/bin:$PATH"

  # bun completions
  # [ -s "${HOME}/.bun/_bun" ] && source "${HOME}/.bun/_bun"
fi

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"
