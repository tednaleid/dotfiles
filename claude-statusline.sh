#!/usr/bin/env bash
# ABOUTME: Claude Code status line script that displays directory, git branch,
# ABOUTME: model name, and color-coded context usage with a progress bar.

# Reads JSON from stdin (piped by Claude Code) and renders a status line.
# Format: directory branch ✔/✘ | Model Name | tokens [progress bar] pct%
#
# Context color: ANSI green -> yellow -> red based on percentage used.
# Uses terminal palette colors so the bar matches the active theme.
# Env var (optional):
#   CLAUDE_CONTEXT_GRADIENT  three comma-separated pcts (default 15,40,70)

set -euo pipefail

input=$(cat)

# --- Context gradient thresholds ---
IFS=',' read -r green_pct yellow_pct red_pct <<< "${CLAUDE_CONTEXT_GRADIENT:-15,40,70}"

# Returns the ANSI color code for a given percentage on the gradient
ansi_color_at() {
  local pct=$1
  if [ "$pct" -le "$yellow_pct" ]; then
    echo "32"  # green
  elif [ "$pct" -le "$red_pct" ]; then
    echo "33"  # yellow
  else
    echo "31"  # red
  fi
}

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

# --- Last response duration (wall-clock since prompt submission) ---
session_id=$(echo "$input" | jq -r '.session_id')
submit_cache="/tmp/.claude-prompt-submit-${session_id}"
if [ -f "$submit_cache" ]; then
  submit_sec=$(cat "$submit_cache")
  now_sec=$(date +%s)
  elapsed_sec=$((now_sec - submit_sec))
  duration_display="${elapsed_sec}s"
else
  duration_display="--"
fi

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

if [ -n "$used_pct" ] && [ "$used_pct" != "null" ]; then
  used_int=$(printf "%.0f" "$used_pct")
else
  used_int=0
fi

color_code="\033[$(ansi_color_at "$used_int")m"

if [ -n "$used_pct" ] && [ "$used_pct" != "null" ]; then
  filled=$((used_int / 5))
  bar=""
  for ((i=0; i<20; i++)); do
    if [ "$i" -lt "$filled" ]; then
      bar+="${color_code}█"
    else
      # Unfilled cells show their position's color, dimmed
      bar+="\033[2;$(ansi_color_at $((i * 5)))m░\033[22m"
    fi
  done
  context_display="${color_code}${token_display} [${bar}${color_code}] ${used_pct}%\033[0m"
else
  context_display="${color_code}${token_display}\033[0m"
fi

# --- Render ---
printf "\033[33m%s\033[0m%b | %s | %b | %s" "$dir_display" "$git_branch" "$model" "$context_display" "$duration_display"
