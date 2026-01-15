---
description: Monitor a GitLab CI pipeline, showing job statuses and investigating failures
argument-hint: "[pipeline_id]"
allowed-tools: Bash(glab:*), Bash(sed:*), Bash(git remote get-url origin), Bash(jq:*)
---

# GitLab Pipeline Monitor

**Branch:** !`git branch --show-current`
**Project (URL-encoded):** !`git remote get-url origin | sed -E 's|.*[:/]([^/]+/.*)(\.git)?$|\1|' | sed 's|\.git$||' | jq -Rr @uri`

## Task
Monitor pipeline $ARGUMENTS (or latest pipeline for current branch if not specified).

## Workflow
1. Get pipeline status: `glab ci status --branch <branch>`
2. For failures, fetch job IDs: `glab api "projects/<path>/pipelines/<id>/jobs?per_page=50" | jq -r '.[] | select(.status == "failed") | "\(.id) \(.name)"'`
3. Get failure logs: `glab api "projects/<path>/jobs/<job_id>/trace" | tail -100`
4. Recheck every 30-45s until complete or user stops

**Avoid:** `glab ci view` (crashes non-interactively)