#!/usr/bin/env bash
# ABOUTME: Claude Code status line script that displays directory, git branch,
# ABOUTME: model name, and color-coded context usage with a progress bar.

# Reads JSON from stdin (piped by Claude Code) and renders a status line.
# Format: directory branch ✔/✘ | Model Name | tokens [progress bar] pct%
#
# Context color: smooth truecolor gradient from green -> yellow -> red based
# on percentage used. Colors are read from the Ghostty theme palette.
# Env vars (all optional):
#   CLAUDE_CONTEXT_GRADIENT  three comma-separated pcts (default 15,40,70)
#   CLAUDE_CONTEXT_COLORS    three comma-separated hex colors: green,yellow,red

set -euo pipefail

input=$(cat)

# --- Theme-aware gradient colors ---
if [ -n "${CLAUDE_CONTEXT_COLORS:-}" ]; then
  IFS=',' read -r color_green color_yellow color_red <<< "$CLAUDE_CONTEXT_COLORS"
else
  ghostty_config="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty/config"
  theme_name=$(grep -m1 '^theme' "$ghostty_config" 2>/dev/null | sed 's/.*= *//; s/"//g')
  theme_file=$(find "/Applications/Ghostty.app/Contents/Resources/ghostty/themes/" -iname "$theme_name" -print -quit 2>/dev/null)
  if [ -n "$theme_file" ] && [ -f "$theme_file" ]; then
    color_green=$(grep '^palette = 2=' "$theme_file" | sed 's/.*=//')
    color_yellow=$(grep '^palette = 3=' "$theme_file" | sed 's/.*=//')
    color_red=$(grep '^palette = 1=' "$theme_file" | sed 's/.*=//')
  fi
fi
color_green="${color_green:-#5adecd}"
color_yellow="${color_yellow:-#f2a272}"
color_red="${color_red:-#f37f97}"

IFS=',' read -r green_pct yellow_pct red_pct <<< "${CLAUDE_CONTEXT_GRADIENT:-15,40,70}"

hex_to_rgb() {
  local hex="${1#\#}"
  printf "%d %d %d" "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

# Convert theme colors to RGB once
read -r _gr _gg _gb <<< "$(hex_to_rgb "$color_green")"
read -r _yr _yg _yb <<< "$(hex_to_rgb "$color_yellow")"
read -r _rr _rg _rb <<< "$(hex_to_rgb "$color_red")"

# Sets _r, _g, _b to the gradient RGB at the given percentage
compute_rgb() {
  local pct=$1
  if [ "$pct" -le "$green_pct" ]; then
    _r=$_gr; _g=$_gg; _b=$_gb
  elif [ "$pct" -le "$yellow_pct" ]; then
    local span=$((yellow_pct - green_pct))
    local t=$((pct - green_pct))
    _r=$(( _gr + (_yr - _gr) * t / span ))
    _g=$(( _gg + (_yg - _gg) * t / span ))
    _b=$(( _gb + (_yb - _gb) * t / span ))
  elif [ "$pct" -le "$red_pct" ]; then
    local span=$((red_pct - yellow_pct))
    local t=$((pct - yellow_pct))
    _r=$(( _yr + (_rr - _yr) * t / span ))
    _g=$(( _yg + (_rg - _yg) * t / span ))
    _b=$(( _yb + (_rb - _yb) * t / span ))
  else
    _r=$_rr; _g=$_rg; _b=$_rb
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

compute_rgb "$used_int"
printf -v color_code "\033[38;2;%d;%d;%dm" "$_r" "$_g" "$_b"

if [ -n "$used_pct" ] && [ "$used_pct" != "null" ]; then
  filled=$((used_int / 5))
  bar=""
  for ((i=0; i<20; i++)); do
    if [ "$i" -lt "$filled" ]; then
      bar+="${color_code}█"
    else
      # Unfilled cells show the gradient at their position, dimmed
      compute_rgb $((i * 5))
      printf -v dim_color "\033[38;2;%d;%d;%dm" "$((_r / 3))" "$((_g / 3))" "$((_b / 3))"
      bar+="${dim_color}░"
    fi
  done
  context_display="${color_code}${token_display} [${bar}${color_code}] ${used_pct}%\033[0m"
else
  context_display="${color_code}${token_display}\033[0m"
fi

# --- Render ---
printf "\033[33m%s\033[0m%b | %s | %b | %s" "$dir_display" "$git_branch" "$model" "$context_display" "$duration_display"
