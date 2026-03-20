#!/usr/bin/env bash
# ABOUTME: Claude Code UserPromptSubmit hook that records the submission
# ABOUTME: timestamp for the statusline to compute response duration.

# Saves epoch milliseconds to a cache file keyed by session ID so
# multiple concurrent sessions don't interfere with each other.

set -euo pipefail

input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id')
cache_file="/tmp/.claude-prompt-submit-${session_id}"

# epoch seconds
date +%s > "$cache_file"
