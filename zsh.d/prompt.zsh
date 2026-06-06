# ABOUTME: zsh prompt with an asynchronous git segment so pressing Enter never
# ABOUTME: blocks on `git status` (slow in large repos and on Dropbox storage).

# Two-line prompt, visually identical to the old synchronous one:
#   line 1: HH:MM:SS  working-dir  <branch + dirty mark>  [exit]  aws:profile
#   line 2: "> "  (the ">" turns red when there are background jobs)
#
# The git segment is the only slow part, so it is computed in a background job
# and painted in with `zle reset-prompt` when ready. Everything else is cheap
# and rendered synchronously. Pure zsh, no external dependencies.

autoload -Uz add-zsh-hook
setopt prompt_subst

# --- asynchronous git segment ----------------------------------------------

typeset -g _git_seg=''   # formatted git segment shown in PROMPT (filled async)
typeset -g _git_fd=0     # read-end fd of the in-flight worker (0 = none)

# Runs in a background subshell. Prints the formatted segment, or nothing when
# the working directory is not inside a git repo.
_git_seg_compute() {
  local ref
  ref=$(command git symbolic-ref --short HEAD 2>/dev/null) \
    || ref=$(command git rev-parse --short HEAD 2>/dev/null) \
    || return
  local mark='%F{green} ✔%f'
  [[ -n $(command git status --porcelain 2>/dev/null | tail -n1) ]] && mark='%F{red} ✘%f'
  print -r -- " %B%F{green}${ref}%f%b${mark}"
}

# Unregister and close the in-flight worker's fd. Closing the pipe makes an
# abandoned worker exit on its own (EOF / SIGPIPE), so there is nothing to kill.
_git_seg_cleanup() {
  (( _git_fd )) && { zle -F $_git_fd 2>/dev/null; exec {_git_fd}<&- 2>/dev/null; }
  _git_fd=0
}

# zle fd-handler: fires when the worker has produced output (or closed the pipe).
_git_seg_ready() {
  local seg
  IFS= read -r -u $1 seg     # one short line; empty on EOF (not a git repo)
  _git_seg=$seg
  _git_seg_cleanup
  zle reset-prompt           # always valid here: fd-handlers run inside zle
}

# precmd: abandon any previous worker, clear stale info, start a fresh one.
_git_seg_start() {
  _git_seg_cleanup
  _git_seg=''                # so a previous repo's status never lingers
  exec {_git_fd}< <(_git_seg_compute)
  zle -F $_git_fd _git_seg_ready
}
add-zsh-hook precmd _git_seg_start

# --- aws segment (cheap, rendered synchronously) ---------------------------

if [[ -d ~/.aws ]]; then
  aws_prompt_info() {
    if [[ -n "$AWS_PROFILE" ]]; then
      local color=magenta
      [[ "$AWS_PROFILE" == *prod* ]] && color=red
      echo " %F{${color}}aws:${AWS_PROFILE}%f"
    fi
  }
else
  aws_prompt_info() { }
fi

# --- prompt ----------------------------------------------------------------

PROMPT='%F{blue}%D{%H:%M:%S}%f %B%F{yellow}%(5~|%-2~/.../%2~|%4~)%f%b${_git_seg}%(?.. [%B%F{red}%?%f%b])$(aws_prompt_info)
%(1j.%B%F{red}> %f%b.> )'
