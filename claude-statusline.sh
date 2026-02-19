#!/usr/bin/env bash
# ABOUTME: Claude Code status line script that displays directory, git branch,
# ABOUTME: model name, and color-coded context usage with a progress bar.

# Reads JSON from stdin (piped by Claude Code) and renders a status line.
# Format: directory branch ✔/✘ | Model Name | tokens [progress bar] pct%
#
# Context token colors:
#   green  < 150k
#   yellow   150k-170k
#   red    > 170k

set -euo pipefail

input=$(cat)

# --- Working directory (yellow, truncated for long paths) ---
cwd=$(echo "$input" | jq -r '.workspace.current_dir')
dir_display="${cwd/#$HOME/\~}"
depth=$(echo "$dir_display" | awk -F'/' '{print NF-1}')

if [ "$depth" -gt 5 ]; then
  dir_display=$(echo "$dir_display" | awk -F'/' '{printf "%s/%s/.../%s/%s", $1, $2, $(NF-1), $NF}')
elif [ "$depth" -gt 4 ]; then
  dir_display=$(echo "$dir_display" | awk -F'/' '{
    result=""
    for (i=NF-3; i<=NF; i++) {
      if (result!="") result=result"/"
      result=result $i
    }
    print result
  }')
fi

# --- Git branch + clean/dirty indicator ---
git_branch=""
if git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
  branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null \
        || git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
  if [ -n "$branch" ]; then
    if [ -z "$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)" ]; then
      git_branch=" \033[32m${branch} ✔\033[0m"
    else
      git_branch=" \033[32m${branch}\033[31m ✘\033[0m"
    fi
  fi
fi

# --- Model name ---
model=$(echo "$input" | jq -r '.model.display_name')

# --- Context usage (color-coded progress bar) ---
# used_percentage and context_window_size reflect current context, not cumulative session totals
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
window_size=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')

if [ -n "$used_pct" ] && [ "$used_pct" != "null" ]; then
  used_tokens=$(awk "BEGIN {printf \"%.0f\", $used_pct / 100 * $window_size}")
else
  used_tokens=0
fi

if [ "$used_tokens" -ge 1000 ]; then
  token_display="$((used_tokens / 1000))k"
else
  token_display="${used_tokens}"
fi

if [ "$used_tokens" -gt 170000 ]; then
  color_code="\033[31m"   # red
elif [ "$used_tokens" -ge 150000 ]; then
  color_code="\033[33m"   # yellow
else
  color_code="\033[32m"   # green
fi

if [ -n "$used_pct" ] && [ "$used_pct" != "null" ]; then
  used_int=$(printf "%.0f" "$used_pct")
  filled=$((used_int / 5))
  empty=$((20 - filled))
  bar=$(printf "%${filled}s" | tr ' ' '█')$(printf "%${empty}s" | tr ' ' '░')
  context_display="${color_code}${token_display} [${bar}] ${used_pct}%\033[0m"
else
  context_display="${color_code}${token_display}\033[0m"
fi

# --- Render ---
printf "\033[33m%s\033[0m%b | %s | %b" "$dir_display" "$git_branch" "$model" "$context_display"
