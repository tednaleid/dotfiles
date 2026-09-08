# morning-summary design

A daily standup summary built from Claude Code sessions, git commits and
merge request activity.

## Purpose

Ted attends two kinds of standup. On Monday, Wednesday and Friday it is a
spoken standup, where he needs talking points with enough detail to answer a
follow-up question. On Tuesday and Thursday it is a written Slack standup,
where he posts a short bullet list under a `Y:` heading for yesterday and a
`T:` heading for today.

Both are currently assembled by hand, or by asking Claude to trawl
`~/.claude/projects` interactively. That works and has produced good output
twice, but it re-derives the same `jq` incantations every time and burns
context printing raw transcripts.

The goal is a single command, run after login, that produces both forms.

## Scope

In scope: Claude Code sessions, git commits authored by Ted, and merge request
activity on GitLab and GitHub.

Out of scope, deliberately:

- **JIRA enrichment.** Ticket numbers already live in branch names and MR
  titles, which is where the summary should read them from.
- **Calendar integration.** Meetings are a real part of the standup post and
  the tool will never know them. It leaves a placeholder for Ted to fill.
- **A config file.** Repositories are discovered from the sessions themselves.
- **History or trend tracking** across days.

## Components

Three pieces with one interface between them.

| Path | Role |
| --- | --- |
| `~/code/dotfiles/standup-digest` | `uv` single-file script; gathers and filters; emits markdown to stdout |
| `~/code/dotfiles/.claude/skills/morning-summary/SKILL.md` | runs the script, writes the prose |
| `zshrc` function `morning-summary` | opens an interactive session seeded with `/morning-summary` |

`standup-digest` contains no prose, no judgment about what matters, and makes
no API calls. `morning-summary` supplies all the judgment. The split exists so
that the mechanical work is fast, testable and unchanging, while the part that
needs a model stays in the model.

The script is installed by a `standup-digest` justfile recipe symlinking it
into `~/.local/bin`, following the existing `csess` and `glab-comment`
recipes, and added to `all`. The skill is copied into `~/.claude/skills` by
the existing `claude-skills` recipe.

`claude` dispatches skills as slash commands and forwards arguments to them,
whether the session is headless or interactive. This was verified against the
existing `weekly-status` skill before writing this document.

The entry point is a shell function rather than an alias, and it starts an
interactive session rather than a headless one, following the same shape as
the `mrreview` function beside it. A run takes about two minutes, and headless
mode shows nothing at all while it works, which reads as a hang. Interactive
mode streams the tool calls, and the session stays open afterwards so the
summary can be reworked in place: dropping a bullet, pulling in a meeting, or
asking what a thread was actually about. That last part is the real reason,
since a standup note is usually two edits away from right.

The function also sets the montty surface red, matching how `mrreview` marks
its tab green, and leaves it set.

### Relationship to `weekly-status`

`~/.claude/skills/weekly-status/SKILL.md` is a sibling, not a parent.
It reports on the whole team, over a Monday-to-Friday window, from git and
merge requests. `morning-summary` reports on Ted, over a one-day window,
led by Claude sessions. They share conventions but no code.

### Relationship to `csess`

`standup-digest` shells out to `csess list -a --json` for session discovery
rather than reimplementing it. One tool owns the knowledge of where sessions
live and how to read their recap.

The window is not passed down to `csess`. Its index is cached and returns all
412 local sessions in half a second, so filtering there saves nothing, and
`csess` exits non-zero with a human-readable error when a filter matches
nothing, which is an awkward signal to consume. `standup-digest` takes the
whole index and does every filtering decision itself.

## The window

The default window runs from **00:00 local on the previous working day** to
**now**.

- Run on Monday, it reaches back to Friday and sweeps Saturday and Sunday into
  the same window. Weekend activity is rare and folds into the same list
  rather than getting its own section.
- Run Tuesday through Friday, it reaches back to yesterday.

Two behaviours the naive version gets wrong:

**Drop sessions with no conversation.** The index includes sessions that hold
no user or assistant turns at all, such as an aborted launch. It also includes
throwaway probe sessions run from `/tmp`. Anything with no conversation inside
the window is dropped by the window filter below.

**Filter on transcript timestamps, not file mtime.** `csess` reports a
session's modified time, which moves when Claude Code appends metadata records
(`cost-state`, `ai-title`, `last-prompt` and similar) that carry no
`timestamp` field. A session whose conversation ended on Tuesday can therefore
report a Wednesday mtime. This produced a false entry in a hand-built summary.
The script uses `csess --since` as a wide net, then filters precisely on the
`.timestamp` values of conversation records inside each transcript, and drops
any session with no conversation inside the window.

**Widen automatically when the window is empty.** There is no holiday
calendar. If the previous working day yields nothing at all, step back one
more working day and label the window in the output. This handles a holiday
Monday without modelling holidays.

### Overrides

```
standup-digest [--since <duration|date>] [--until <duration|date>]
```

Durations use the `csess` forms (`12h`, `14d`, `2w`) and count back from now.
Dates are `YYYY-MM-DD`, meaning 00:00 local on that day, or
`YYYY-MM-DDTHH:MM` local for a precise boundary. `--until` exists so a run can
be pinned to a historical window, which the verification plan below depends
on.

### Splitting yesterday from today

Every record the script emits is tagged with the local date it occurred on.
The skill uses that tag to separate `Y:` from work already done today, which
becomes a `T:` candidate rather than a `Y:` bullet.

## Gatherer output

One markdown document on stdout, targeting 200 to 400 lines, in three parts.

### Sessions

One block per session with conversation inside the window:

- project, branch, worktree, title
- recap
- the user's prompts, truncated to 200 characters each
- up to five assistant messages per session per day, selected as described
  below, truncated to 400 characters each

**Excluded sessions.** A user turn counts as a summary invocation when its
text begins with `/morning-summary`, or when it is the skill preamble naming
`morning-summary`. A session whose only user turns are summary invocations is
dropped entirely: running the summary is not a work item and must not appear
in tomorrow's summary. A session where Ted invoked the summary and then kept
working is kept, minus those turns.

**Excluded turns.** Two kinds of user record are not prompts and are filtered
out:

- skill invocation preambles, which begin `Base directory for this skill:`
- system reminders and tool results, which begin with `<`

Attachment markers of the form `[Image: source: …]` collapse to `[image]`.

**Assistant message selection.** This is the only heuristic in the script.
Per session per day, keep assistant text messages of at least 200 characters
and take the last five. The rationale is empirical rather than theoretical: in
the hand-built summaries, the details worth reporting that the recap did not
already carry — a verified terraform plan, a merged MR number, a root cause —
were consistently in the final substantial assistant messages of a working
session. Position and length are cheap proxies that worked; pattern-matching
for conclusion-shaped language was not tried and is not needed.

The skill retains an escape hatch: when a session is large and its recap is
thin, it reads that one transcript directly rather than guessing from the
digest.

### Commits

Repositories are discovered from the `cwd` of every session in the window,
resolved to their git top level. Worktrees resolve to their common directory
so a worktree and its parent are not counted twice.

For each repository, commits are selected by that repository's effective
`git config user.email`, since work and personal identities differ.

### Merge request activity

MRs and PRs opened, merged, approved or commented on within the window.

The specific API calls are left to implementation and must be verified against
a live response rather than assumed. The likely shapes are the GitLab `/events`
endpoint for the authenticated user via `glab api`, and `gh search prs
--involves=@me`. Host and project are derived from each discovered
repository's remote.

Failure to reach a host is reported as a line in the output, not an exception.
A standup summary missing its MR section is still useful; a summary that
crashes at 8:55am is not.

## Skill output

Written to `${XDG_STATE_HOME:-$HOME/.local/state}/standup/YYYY-MM-DD.md`.
State rather than data: the files are regenerable and would never be restored
from a backup. `~/.local/state` already holds `claude`, `gh` and
`review-branch`.

Both sections are printed to the terminal in full. Only the Slack section is
copied to the clipboard, since that is the part that gets pasted.

The document has two sections.

**Slack.** At most five `Y:` bullets, one per story or thread, leading with
the ticket or MR number. A thread that spans several sessions collapses to one
bullet. `T:` is pre-filled with candidates drawn from the `Next:` lines of
session recaps, MRs awaiting Ted's approval, and anything already done today,
plus a `[meetings / not in a session]` placeholder.

**Talking points.** One `###` heading per thread at the level of detail of the
hand-built summaries, with anything blocked on Ted called out explicitly.

## Testing

`pytest` in `tests/test_standup_digest.py`, run by the existing `just test`,
against a fixture directory of small `.jsonl` transcripts. Test-driven, since
every one of these is a case that has already been got wrong by hand:

- window boundaries at both ends, with `--since` and `--until` honoured
- a session whose mtime is inside the window but whose conversation is not
- the Monday sweep across Friday, Saturday and Sunday
- empty-window widening to the working day before
- the `Y` versus today split
- `morning-summary` sessions excluded; a mixed session kept without that turn
- skill preambles and system reminders filtered from prompts
- assistant selection returning the last five substantial messages per day
- a worktree and its parent resolving to one repository
- an unreachable git host degrading to a reported line

The prose is not unit-testable. It is covered by the verification plan.

## Verification

A hand-built summary is written **before** the script exists, covering the
same window the tool will later be pinned to. It is kept outside this
repository, because a real day's summary is a log of real work and this
repository is public.

After implementation, `standup-digest` is run pinned to that window with
`--since` and `--until`, the skill summarizes it, and the two are compared.
Pinning matters: without `--until`, the tool's window would include the whole
of the implementation work and the comparison would measure the clock rather
than the extraction.

The comparison asks three questions. Did the tool find every thread the hand
pass found? Did it invent a thread that was not real? Is the detail it kept
the detail that was worth keeping? Differences drive changes to the assistant
selection heuristic, which is the part most likely to be wrong.

The baseline is a one-time artifact, not a regression fixture. It is not
asserted against by `just test`.

### What the comparison found

Coverage and detail both held up: every thread the hand pass found was
present, and the detail kept matched or beat it.

It found one real defect. A session's recap describes its state *now*, not its
state at the window's end, so a session still running past a pinned `--until`
leaked later work into the digest as though it had already happened. One
fabricated thread and one commit that did not yet exist. `select_sessions`
now drops the recap when `--until` was supplied and the transcript runs past
it.

One residual gap is known and unfixed: `## commits` only covers repositories
reachable from a session's `cwd`, so work committed to a repository you never
had a session in is missed. Fixing it needs a different repo-discovery
approach rather than a threshold change.

The result worth recording is that the hand-built baseline contained the same
class of temporal leak the tool did, claiming something that in fact happened
after the window it described. A baseline written by someone who already knows
how the day turned out is not automatically the more trustworthy of the two.
