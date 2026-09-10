---
name: morning-summary
description: >
  Generate a daily standup summary from Claude Code sessions, git commits
  and merge request activity for the last working day. Produces a short
  Slack-ready block and longer spoken-standup talking points. Use when the
  user asks for their standup, morning summary, daily summary, "what did I
  do yesterday", or runs /morning-summary.
---

# Morning Summary

## Workflow

### 1. Gather

```bash
standup-digest
```

Pass `--since` and `--until` straight through if the user supplied them.

The digest reports its window on the third line. Say what it was if it
was widened past the previous working day, because that means the previous
working day held no work.

### 2. Read the digest

Each session heading has the form `### project[/worktree] (branch) title`.
Read ticket numbers out of the branch name here, and out of MR titles in the
`## merge requests` section.

A session block carries the user's prompts and the last few substantial
assistant messages of each day, and a `recap:` line when the session did not
run past the window's end. csess drops the recap otherwise, so it may be
absent.

When present, the recap is already a model-written summary and is usually
the best single source for what a session was about. The assistant messages
are where concrete outcomes live: a merged MR number, a verified plan, a
root cause. When the recap is absent, rely on the prompts and assistant
messages instead.

Group across sessions. One piece of work often spans several sessions, and
several worktrees of the same repository; it gets one bullet, not three.

If a session looks substantial but its recap is thin or absent and its
messages do not explain what happened, read that one transcript directly
with the path in its `transcript:` line. Do this for one or two sessions at
most.

A `## merge request links` section lists each merge request once, as
`- !<iid> <url>  <title>`. The url is the link target for that `!<iid>`, and
the title is the raw material for its parenthetical. A merge request that
appears only in session prose is absent here and has no url.

A `jira base:` line near the top gives the JIRA site. A key links to
`<base>/browse/<KEY>`. The line is absent when no JIRA site is configured.

A `## problems` section lists a host or tool the digest could not read: a
`csess` failure, or a GitLab/GitHub API call that did not respond or did not
parse. Whichever section that source feeds (`## sessions` or
`## merge requests`) is then incomplete for exactly the part that failed.
Say so plainly in the report rather than presenting the digest as a complete
picture of the day.

### 3. Split yesterday from today

Every prompt and message is tagged with its date. Anything dated today is
not a `Y:` bullet; it is a `T:` candidate.

### 4. Write the report

Write the full report to
`${XDG_STATE_HOME:-$HOME/.local/state}/standup/$(date +%Y-%m-%d).md`,
creating the directory if needed.

Also write the Slack block on its own (no `## Slack` heading, no `---`
separator, just the `Y:`/`T:` bullets) to a second file:
`${XDG_STATE_HOME:-$HOME/.local/state}/standup/$(date +%Y-%m-%d)-slack.md`.
This second file is the only source for the clipboard. Do not extract the
Slack section back out of the full report with `sed` or anything else; write
it directly, once, as its own file.

Copy that file to the clipboard:

```bash
pbcopy < "$slack_file"
```

Then verify before claiming success:

```bash
test -s "$slack_file"
```

If this fails, the file is missing or empty and the state directory may be
unwritable. Say so plainly and fix it rather than reporting the run as
successful.

```bash
grep -q "Talking points" "$slack_file"
```

If that matches, the Slack file has the full report in it instead of just
the Slack block. Say so plainly and fix it rather than reporting the run as
successful.

Print the whole report to the conversation, then say the path and that the
Slack section is on the clipboard.

## Output format

When the digest reports a widened window, the `Y:` line carries the
parenthetical named in the Rules section below; otherwise it is bare.

```markdown
## Slack

Y: (Friday 09-04, Monday was Labor Day)
- [!367](url) (streamlit app removal) approved and merged. <what it means>
- Chase Ryan's approval on [!352](url) ([FORGE-404](url) module onboarding docs)

T:
- <candidates from recap Next: lines, MRs awaiting approval, work already
  done today>
- [meetings / anything not in a session]

---

## Talking points

### <thread name, with ticket or MR number>
- <what happened, at the level of detail that answers a follow-up question>
- <anything blocked on the user, called out as such>
```

## Rules

- At most five `Y:` bullets. If there were more than five threads, the
  smallest ones merge or drop. A standup is not a changelog.
- Lead each Slack bullet with the ticket or MR number when there is one.
  Read them from branch names and MR titles.

The next four rules apply to the Slack section only. Slack renders markdown,
and that section gets read by people who were not in any of these sessions.
The talking points are for the user alone and stay plain text.

- Link every reference. `!367` becomes `[!367](url)` using the url from
  `## merge request links`. `FORGE-404` becomes
  `[FORGE-404](<jira base>/browse/FORGE-404)`. A JIRA key links from the key
  alone, so link every one whenever a `jira base:` line is present. A merge
  request links only when the links section lists it; leave the others as
  plain `!367` rather than guessing a url that may 404.
- Follow each reference with a parenthetical of five words or fewer saying
  what it is, so the line is not all magic numbers. Compress the MR title
  from the links section, or use what the sessions say. `!275` with the title
  "FORGE-332: Pool and retry OMNI connections" becomes
  `[!275](url) (pool omni connections)`. Skip the parenthetical only when the
  surrounding sentence already says what the thing is.
- Write for a teammate, not for the user's own recall. Cut anything only the
  user can resolve: review finding ids, local branch names, scratch file
  paths. "Finish reviewing !275" beats "decide on the two remaining !275
  test-coverage findings (f3, f6)".
- Leave the user's own deliberation out. "Decide whether to post the drafted
  reply" is a private next action, not a standup item, and it is usually
  already implied by the bullet about getting the thing merged.
- Meetings never appear in the digest. Always leave the
  `[meetings / anything not in a session]` line for the user to fill.
- Never report a merge, a deploy, or a fix as done unless the digest says
  so. A plan to do a thing is not the thing.
- When `## problems` is non-empty, say so plainly in the report. A section
  the digest could not read is a gap, not a quiet day, and presenting the
  rest as the complete picture would hide it.
- When the digest reports a widened window, the `Y:` line names the day it
  actually covers and why, e.g. `Y: (Friday 09-04, Monday was Labor Day)`.
  Otherwise a Friday summary reads as if it were Monday's.
- No emojis, no em-dashes, no hyperbole.
