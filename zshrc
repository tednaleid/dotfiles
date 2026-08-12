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
# Full security audit + dump rebuild at most once per 24h; otherwise load the
# cached dump with -C (skips the audit). The glob is evaluated in the array
# assignment (it would NOT expand inside [[ ]]); the array is non-empty only when
# a fresh dump exists. touch advances the mtime so the fast path keeps engaging
# even when compinit leaves the dump's contents unchanged.
autoload -Uz compinit
local -a fresh_zcompdump=( ~/.zcompdump(N.mh-24) )
if (( $#fresh_zcompdump )); then
  compinit -C
else
  compinit
  touch ~/.zcompdump
fi

# unsetopt menucomplete
unsetopt flowcontrol
setopt auto_menu
setopt complete_in_word
setopt always_to_end
setopt auto_pushd

zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'

# PROMPT ############################################################ 

# The prompt (with an asynchronous git segment) lives in its own module so it
# does not clutter this file. See zsh.d/prompt.zsh.
local prompt_module="${HOME}/.zsh.d/prompt.zsh"
[[ -e ${prompt_module} ]] && source ${prompt_module}

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

alias icat='upscale show'

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

if ! type tag &> /dev/null; then
  echo "missing tag, install with:"
  echo "brew install tag"
elif ! type trash &> /dev/null; then
  echo "missing trash, install with:"
  echo "brew install trash"
else
  function trash-tagged() {
    tag -m "${1:-Red}" -0 | tee >(tr '\0' '\n' >&2) | xargs -0 trash
  }
fi

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

# AWS
aws-profile() {
  if [ ! -d ~/.aws ]; then
    echo "No ~/.aws directory found"
    return 1
  fi
  local profile
  if [ -z "$1" ]; then
    profile=$(aws configure list-profiles | fzf --prompt="AWS Profile> " --header="Current: ${AWS_PROFILE:-<not set>}")
    [ -n "$profile" ] && export AWS_PROFILE="$profile" && echo "Switched to: $profile"
  else
    export AWS_PROFILE="$1"
    echo "Switched to: $1"
  fi
}

# Create (or reuse) a worktree for a branch / MR / PR and cd into it.
#   wtcd                      current branch
#   wtcd JIRA-123-my-branch   branch name
#   wtcd 254                  MR/PR number
#   wtcd <mr-url>             MR/PR URL
# Extra flags (-q, -v) are passed through to `wt create`.
wtcd() {
  # wt derives the repo from cwd, so run it from the main checkout even when
  # called from inside another worktree.
  local main_wt
  main_wt=$(git worktree list --porcelain 2>/dev/null | head -1 | cut -d' ' -f2-)
  if [[ -z "$main_wt" ]]; then
    print -u2 "wtcd: not inside a git repository"
    return 1
  fi

  local errfile wt_path rc
  errfile=$(mktemp)
  wt_path=$(cd "$main_wt" && wt create "$@" 2>"$errfile")
  rc=$?
  cat "$errfile" >&2
  if (( rc != 0 )); then
    wt_path=$(sed -n 's/^worktree already exists: //p' "$errfile")
    if [[ -z "$wt_path" ]]; then
      rm -f "$errfile"
      return $rc
    fi
    print -u2 "wtcd: reusing existing worktree"
  fi
  rm -f "$errfile"

  cd "$wt_path"
}

# Review a GitLab MR in its own worktree:  mrreview 254  |  mrreview <mr-url>
mrreview() {
  local target="${1:?usage: mrreview <mr-number|mr-url>}"
  local num="${target##*/merge_requests/}"; num="${num%%/*}"
  if [[ "$num" != <-> ]]; then
    print -u2 "mrreview: no MR number in '$target'"
    return 2
  fi

  wtcd "$num" || return

  claude -n "review-branch-$num" \
    --append-system-prompt "The git worktree for MR $num already exists and this session is running inside it. Skip the review-branch skill's worktree-creation step and review in the current directory." \
    "/review-branch $num"
}


## PRIVATE / HOST SPECIFIC ############################################ 

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
export PATH="$BUN_INSTALL/bin:$PATH"
