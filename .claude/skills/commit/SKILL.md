---
name: commit
description: Create a git commit with an issue/JIRA ticket prefix and succinct message. Use when the user asks to commit changes, create a commit, or uses /commit. Determines the Issue/JIRA ticket from the branch name, stages specific files, and commits with a properly formatted message.
allowed-tools: Bash(git *)
---

# Commit

Create a git commit following message conventions.

## Workflow

1. Run `git status` (never `-uall`), `git diff`, and `git log --oneline -5` in parallel.
2. Determine the commit prefix:
   - Extract the issue or JIRA ticket from branch name (e.g., `ISSUE-1234-feature-name` -> `ISSUE-1234`).
   - If no issue/ticket found, use the branch name as a fallback
   - If the branch name is main/master, synthesize a very short name out of the contents of the commit
3. Draft a succinct commit message. One line of substance, not paragraphs.
4. Stage relevant files by name. Never use `git add -A` or `git add .`.
5. Commit using the heredoc format below.

## Message Format

```
<ISSUE/JIRA TICKET> Succinct description
```

## Commit Command

NEVER use `$()` command substitution in the commit command. Always use `git commit -F -` with a heredoc:

```bash
git commit -F - <<'EOF'
<ISSUE/JIRA TICKET> Succinct description
EOF
```

## Rules

* Always use plain `git` commands (e.g., `git status`, not `git -C /path status`). The `-C` flag breaks permission matching.
* Never use `--no-verify`.
* Never push unless explicitly asked.
* Do not commit files that likely contain secrets (.env, credentials, etc.).
