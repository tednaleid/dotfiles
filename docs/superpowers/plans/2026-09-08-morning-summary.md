# morning-summary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `morning-summary` command that turns the last working day of
Claude Code sessions, git commits and merge request activity into a short
Slack standup post plus longer spoken-standup talking points.

**Architecture:** A stdlib-only `uv` single-file script, `standup-digest`,
gathers and filters the raw material and prints a markdown digest to stdout.
A Claude Code skill, `morning-summary`, runs that script and writes the prose.
A shell alias runs the skill headlessly via `claude -p`. The script holds no
judgment about what matters; the skill holds all of it.

**Tech Stack:** Python 3.12 (stdlib only), `uv` PEP 723 inline script
metadata, `pytest`, `just`, `csess`, `glab`, `gh`.

**Spec:** `docs/superpowers/specs/2026-09-08-morning-summary-design.md`

## Global Constraints

- Python `>=3.12`, declared in a PEP 723 `# /// script` header, matching `csess`.
- **Standard library only.** No `dependencies` entry in the script header.
  `csess` depends on `iterfzf`; this script must not, so that `just test`
  needs no new `--with` flag.
- Every file opens with two `# ABOUTME: ` comment lines. This repo follows
  that convention (`csess`, `justfile`, `tests/test_csess.py` all do).
- Tests live in `tests/` and are run by the existing `just test`, which is
  `uv run --with pytest --with iterfzf pytest tests/ -q`.
- Tests synthesise their own `.jsonl` transcripts and git repositories under
  `tmp_path`. No test reads a real Claude Code session or a real repository.
- Documentation and skill prose: no emojis, no em-dashes, no hyperbole.
- Comments are evergreen. No ticket ids, no dates, no "currently", no
  narration of what was tried and rejected.
- All timestamps in transcripts are UTC with a `Z` suffix. All output and all
  window arithmetic is in local time.

---

### Task 1: Capture the hand-built baseline

This task writes no code. It must complete before any implementation, because
its whole value is being uncontaminated by the tool's output. Comparing the
tool against a baseline written after seeing the tool's answer measures
nothing.

**Files:**
- Create: `${XDG_STATE_HOME:-$HOME/.local/state}/standup/2026-09-08-manual-baseline.md`

- [ ] **Step 1: Record the exact window**

Run and note both values verbatim; they are the `--since` and `--until` the
comparison in Task 10 will use.

```bash
date '+%Y-%m-%dT%H:%M'                       # the --until boundary
date -v-fri '+%Y-%m-%d'                      # most recent Friday
```

If today is Monday, the window start is that Friday at `00:00`. Otherwise it
is yesterday at `00:00`.

- [ ] **Step 2: Build the summary by hand**

Using whatever ad-hoc commands you like over `~/.claude/projects/*/*.jsonl`,
`git log` and `glab`, produce the two sections described in the spec: at most
five `Y:` Slack bullets with a pre-filled `T:`, then `###`-per-thread talking
points.

Do not consult this plan's later tasks for which messages to read. The point
is to capture unaided judgment.

- [ ] **Step 3: Write the baseline file**

Open the file with the window boundaries from Step 1 on their own lines, so
Task 10 can pin the tool to the same range:

```markdown
# Manual baseline

Window: 2026-09-05T00:00 through 2026-09-08T09:15 local.
Written before `standup-digest` existed.

## Slack
...

## Talking points
...
```

- [ ] **Step 4: Commit**

```bash
git add ${XDG_STATE_HOME:-$HOME/.local/state}/standup/2026-09-08-manual-baseline.md
git commit -m "Add hand-built standup baseline for tool comparison"
```

---

### Task 2: Window computation

**Files:**
- Create: `standup-digest`
- Create: `tests/test_standup_digest.py`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `Window` dataclass with fields `start: datetime`, `end: datetime`,
    `label: str`. Both datetimes are timezone-aware local.
  - `previous_working_day(day: date) -> date`
  - `parse_boundary(text: str, now: datetime) -> datetime`
  - `default_window(now: datetime) -> Window`
  - `compute_window(now: datetime, since: str | None, until: str | None) -> Window`
  - `widen(window: Window) -> Window`

- [ ] **Step 1: Write the failing tests**

Create `tests/test_standup_digest.py`:

```python
# ABOUTME: unit tests for the pure logic in the standup-digest gatherer
# ABOUTME: transcripts and git repos are synthesised on disk; no real data is read

import importlib.machinery
import types
from datetime import date, datetime, timedelta
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parent.parent / "standup-digest"


def _load():
    """Import the extensionless script as a module."""
    loader = importlib.machinery.SourceFileLoader("standup_digest", str(SCRIPT))
    module = types.ModuleType(loader.name)
    module.__file__ = str(SCRIPT)
    loader.exec_module(module)
    return module


sd = _load()


def local(text):
    """Parse 'YYYY-MM-DD HH:MM' as an aware local datetime."""
    return datetime.strptime(text, "%Y-%m-%d %H:%M").astimezone()


class TestPreviousWorkingDay:
    def test_monday_reaches_back_to_friday(self):
        assert sd.previous_working_day(date(2026, 9, 7)) == date(2026, 9, 4)

    def test_tuesday_reaches_back_to_monday(self):
        assert sd.previous_working_day(date(2026, 9, 8)) == date(2026, 9, 7)

    def test_saturday_reaches_back_to_friday(self):
        assert sd.previous_working_day(date(2026, 9, 5)) == date(2026, 9, 4)

    def test_sunday_reaches_back_to_friday(self):
        assert sd.previous_working_day(date(2026, 9, 6)) == date(2026, 9, 4)


class TestDefaultWindow:
    def test_monday_run_sweeps_the_weekend(self):
        window = sd.default_window(local("2026-09-07 09:15"))

        assert window.start == local("2026-09-04 00:00")
        assert window.end == local("2026-09-07 09:15")

    def test_midweek_run_starts_at_yesterday_midnight(self):
        window = sd.default_window(local("2026-09-09 08:00"))

        assert window.start == local("2026-09-08 00:00")


class TestParseBoundary:
    def test_duration_counts_back_from_now(self):
        now = local("2026-09-08 09:00")

        assert sd.parse_boundary("2h", now) == local("2026-09-08 07:00")

    def test_bare_date_means_local_midnight(self):
        assert sd.parse_boundary("2026-09-04", local("2026-09-08 09:00")) == local(
            "2026-09-04 00:00"
        )

    def test_date_and_time_is_exact(self):
        assert sd.parse_boundary("2026-09-04T13:30", local("2026-09-08 09:00")) == local(
            "2026-09-04 13:30"
        )

    def test_rejects_nonsense(self):
        with pytest.raises(ValueError):
            sd.parse_boundary("last tuesday", local("2026-09-08 09:00"))


class TestComputeWindow:
    def test_overrides_replace_the_defaults(self):
        window = sd.compute_window(
            local("2026-09-08 09:00"), since="2026-09-04", until="2026-09-05T17:00"
        )

        assert window.start == local("2026-09-04 00:00")
        assert window.end == local("2026-09-05 17:00")

    def test_since_alone_keeps_now_as_the_end(self):
        now = local("2026-09-08 09:00")

        assert sd.compute_window(now, since="3d", until=None).end == now


class TestWiden:
    def test_steps_back_one_more_working_day(self):
        window = sd.default_window(local("2026-09-08 09:00"))

        assert sd.widen(window).start == local("2026-09-04 00:00")

    def test_label_records_the_widening(self):
        window = sd.widen(sd.default_window(local("2026-09-08 09:00")))

        assert "widened" in window.label
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `just test`
Expected: collection error, `FileNotFoundError` for `standup-digest`.

- [ ] **Step 3: Write the script skeleton and window logic**

Create `standup-digest`:

```python
#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# ///

# ABOUTME: gather one working day of Claude sessions, commits and MR activity
# ABOUTME: prints a markdown digest for the morning-summary skill to summarise

import argparse
import json
import re
import subprocess
import sys
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path

DURATION = re.compile(r"^(\d+)([hdw])$")
DURATION_UNITS = {"h": 3600, "d": 86400, "w": 604800}


@dataclass
class Window:
    start: datetime
    end: datetime
    label: str


def previous_working_day(day):
    """The most recent weekday strictly before the given day."""
    step = day - timedelta(days=1)
    while step.weekday() >= 5:
        step -= timedelta(days=1)
    return step


def start_of(day, reference):
    """Local midnight on the given date, as an aware datetime."""
    return datetime.combine(day, datetime.min.time()).astimezone(reference.tzinfo)


def describe(start, end):
    return f"{start:%a %Y-%m-%d %H:%M} through {end:%a %Y-%m-%d %H:%M}"


def default_window(now):
    """Local midnight on the previous working day, through now."""
    start = start_of(previous_working_day(now.date()), now)
    return Window(start=start, end=now, label=describe(start, now))


def parse_boundary(text, now):
    """Turn 12h, 2026-09-04 or 2026-09-04T13:30 into an aware local datetime."""
    match = DURATION.match(text)
    if match:
        seconds = int(match.group(1)) * DURATION_UNITS[match.group(2)]
        return now - timedelta(seconds=seconds)
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError as exc:
        raise ValueError(
            f"bad boundary {text!r}: use 12h, 14d, 2w, YYYY-MM-DD or YYYY-MM-DDTHH:MM"
        ) from exc
    return parsed.astimezone(now.tzinfo) if parsed.tzinfo else parsed.replace(tzinfo=now.tzinfo)


def compute_window(now, since, until):
    """The default window, with either boundary replaced by an override."""
    window = default_window(now)
    start = parse_boundary(since, now) if since else window.start
    end = parse_boundary(until, now) if until else window.end
    return Window(start=start, end=end, label=describe(start, end))


def widen(window):
    """Step the start back one further working day."""
    start = start_of(previous_working_day(window.start.date()), window.start)
    return Window(
        start=start, end=window.end, label=f"{describe(start, window.end)} (widened)"
    )
```

Note `start_of` takes the reference datetime only to borrow its `tzinfo`;
`astimezone` on a naive datetime uses the system zone, which is what the tests
construct with their own `.astimezone()`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `just test`
Expected: PASS for every test in `TestPreviousWorkingDay`, `TestDefaultWindow`,
`TestParseBoundary`, `TestComputeWindow` and `TestWiden`.

- [ ] **Step 5: Commit**

```bash
git add standup-digest tests/test_standup_digest.py
git commit -m "Add standup-digest window computation"
```

---

### Task 3: Session selection from transcripts

**Files:**
- Modify: `standup-digest`
- Modify: `tests/test_standup_digest.py`

**Interfaces:**
- Consumes: `Window` from Task 2.
- Produces:
  - `Turn` dataclass: `kind: str` (`"user"` or `"assistant"`), `when: datetime`
    (aware local), `text: str`.
  - `DigestSession` dataclass: `id`, `title`, `project`, `worktree`, `branch`,
    `cwd`, `recap`, `transcript: Path`, `turns: list[Turn]`.
  - `read_turns(path) -> list[Turn]`
  - `select_sessions(index: list[dict], window: Window) -> list[DigestSession]`
    where `index` is the parsed output of `csess list -a --json`.

The critical behaviour is that selection reads timestamps out of the
transcript. `csess` reports a session's file mtime, which advances when Claude
Code appends metadata records that carry no `timestamp` field, so a session
whose conversation ended on Tuesday can report a Wednesday mtime.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_standup_digest.py`:

```python
import json


def write_transcript(root, project_slug, session_id, records):
    """Write records as a .jsonl transcript and return its path."""
    directory = root / project_slug
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / f"{session_id}.jsonl"
    path.write_text("".join(json.dumps(r) + "\n" for r in records))
    return path


def turn(kind, utc, text):
    """A conversation record as Claude Code writes it."""
    return {
        "type": kind,
        "timestamp": utc,
        "message": {"content": [{"type": "text", "text": text}]},
    }


def index_entry(path, **overrides):
    entry = {
        "id": path.stem,
        "title": "a session",
        "project": "proj",
        "worktree": None,
        "branch": "main",
        "cwd": "/Users/x/code/proj",
        "recap": "a recap",
        "transcript": str(path),
    }
    entry.update(overrides)
    return entry


class TestReadTurns:
    def test_reads_text_and_converts_to_local(self, tmp_path):
        path = write_transcript(
            tmp_path, "p", "s", [turn("user", "2026-09-04T18:30:00.000Z", "hello")]
        )

        turns = sd.read_turns(path)

        assert [t.kind for t in turns] == ["user"]
        assert turns[0].text == "hello"
        assert turns[0].when.utcoffset() is not None

    def test_skips_records_without_a_timestamp(self, tmp_path):
        path = write_transcript(
            tmp_path,
            "p",
            "s",
            [
                {"type": "cost-state", "totalCostUSD": 1.0},
                turn("assistant", "2026-09-04T18:30:00.000Z", "hi"),
            ],
        )

        assert len(sd.read_turns(path)) == 1

    def test_skips_records_with_no_text_content(self, tmp_path):
        path = write_transcript(
            tmp_path,
            "p",
            "s",
            [
                {
                    "type": "user",
                    "timestamp": "2026-09-04T18:30:00.000Z",
                    "message": {"content": [{"type": "tool_result", "content": "x"}]},
                }
            ],
        )

        assert sd.read_turns(path) == []

    def test_survives_a_damaged_line(self, tmp_path):
        path = tmp_path / "p" / "s.jsonl"
        path.parent.mkdir(parents=True)
        path.write_text(
            "not json\n" + json.dumps(turn("user", "2026-09-04T18:30:00.000Z", "ok")) + "\n"
        )

        assert len(sd.read_turns(path)) == 1


class TestSelectSessions:
    def test_keeps_a_session_with_conversation_in_the_window(self, tmp_path):
        path = write_transcript(
            tmp_path, "p", "s", [turn("user", "2026-09-04T18:30:00.000Z", "work")]
        )
        window = sd.compute_window(
            local("2026-09-05 09:00"), since="2026-09-04", until="2026-09-05T09:00"
        )

        selected = sd.select_sessions([index_entry(path)], window)

        assert [s.id for s in selected] == ["s"]
        assert selected[0].recap == "a recap"

    def test_drops_a_session_whose_conversation_predates_the_window(self, tmp_path):
        path = write_transcript(
            tmp_path, "p", "s", [turn("user", "2026-09-01T18:30:00.000Z", "old work")]
        )
        window = sd.compute_window(
            local("2026-09-05 09:00"), since="2026-09-04", until="2026-09-05T09:00"
        )

        assert sd.select_sessions([index_entry(path)], window) == []

    def test_drops_a_session_touched_by_metadata_but_not_conversation(self, tmp_path):
        """The mtime trap: metadata records carry no timestamp and are not work."""
        path = write_transcript(
            tmp_path,
            "p",
            "s",
            [
                turn("user", "2026-09-01T18:30:00.000Z", "old work"),
                {"type": "ai-title", "aiTitle": "renamed later"},
                {"type": "cost-state", "totalCostUSD": 2.0},
            ],
        )
        window = sd.compute_window(
            local("2026-09-05 09:00"), since="2026-09-04", until="2026-09-05T09:00"
        )

        assert sd.select_sessions([index_entry(path)], window) == []

    def test_drops_a_session_with_no_conversation_at_all(self, tmp_path):
        path = write_transcript(tmp_path, "p", "s", [{"type": "cost-state"}])
        window = sd.compute_window(
            local("2026-09-05 09:00"), since="2026-09-04", until="2026-09-05T09:00"
        )

        assert sd.select_sessions([index_entry(path)], window) == []

    def test_keeps_only_the_turns_inside_the_window(self, tmp_path):
        path = write_transcript(
            tmp_path,
            "p",
            "s",
            [
                turn("user", "2026-09-01T18:30:00.000Z", "before"),
                turn("user", "2026-09-04T18:30:00.000Z", "during"),
            ],
        )
        window = sd.compute_window(
            local("2026-09-05 09:00"), since="2026-09-04", until="2026-09-05T09:00"
        )

        assert [t.text for t in sd.select_sessions([index_entry(path)], window)[0].turns] == [
            "during"
        ]

    def test_tolerates_a_transcript_that_has_been_deleted(self, tmp_path):
        window = sd.compute_window(
            local("2026-09-05 09:00"), since="2026-09-04", until="2026-09-05T09:00"
        )
        missing = index_entry(tmp_path / "gone.jsonl")

        assert sd.select_sessions([missing], window) == []
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `just test`
Expected: FAIL with `AttributeError: module 'standup_digest' has no attribute 'read_turns'`.

- [ ] **Step 3: Implement transcript reading and selection**

Add to `standup-digest`, after the window functions. Task 2 already put every
import this file needs at the top; nothing below adds to them.

```python
@dataclass
class Turn:
    kind: str
    when: datetime
    text: str


@dataclass
class DigestSession:
    id: str
    title: str
    project: str
    worktree: str | None
    branch: str | None
    cwd: str | None
    recap: str | None
    transcript: Path
    turns: list


def iter_records(path):
    """Yield the parseable JSON records of a transcript, skipping damaged lines."""
    for line in path.read_text(errors="replace").splitlines():
        if not line.startswith("{"):
            continue
        try:
            yield json.loads(line)
        except ValueError:
            continue


def message_text(record):
    """Pull the human-readable text out of a user or assistant record."""
    content = (record.get("message") or {}).get("content")
    if isinstance(content, str):
        return content.strip()
    if isinstance(content, list):
        parts = [
            block.get("text", "")
            for block in content
            if isinstance(block, dict) and block.get("type") == "text"
        ]
        return "\n".join(part for part in parts if part).strip()
    return ""


def read_turns(path):
    """Every conversation turn in a transcript, timestamped in local time."""
    turns = []
    for record in iter_records(path):
        if record.get("type") not in ("user", "assistant"):
            continue
        stamp = record.get("timestamp")
        text = message_text(record)
        if not stamp or not text:
            continue
        turns.append(
            Turn(
                kind=record["type"],
                when=datetime.fromisoformat(stamp).astimezone(),
                text=text,
            )
        )
    return turns


def select_sessions(index, window):
    """Index entries with conversation inside the window, carrying those turns."""
    selected = []
    for entry in index:
        path = Path(entry["transcript"])
        if not path.is_file():
            continue
        turns = [t for t in read_turns(path) if window.start <= t.when <= window.end]
        if not turns:
            continue
        selected.append(
            DigestSession(
                id=entry["id"],
                title=entry.get("title") or entry["id"][:8],
                project=entry.get("project") or "unknown",
                worktree=entry.get("worktree"),
                branch=entry.get("branch"),
                cwd=entry.get("cwd"),
                recap=entry.get("recap"),
                transcript=path,
                turns=turns,
            )
        )
    return selected
```

`datetime.fromisoformat` handles the trailing `Z` on Python 3.11 and later,
and `.astimezone()` with no argument converts to the system zone.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `just test`
Expected: PASS, including
`test_drops_a_session_touched_by_metadata_but_not_conversation`.

- [ ] **Step 5: Commit**

```bash
git add standup-digest tests/test_standup_digest.py
git commit -m "Select sessions by transcript timestamp, not file mtime"
```

---

### Task 4: Turn filtering and the morning-summary exclusion

**Files:**
- Modify: `standup-digest`
- Modify: `tests/test_standup_digest.py`

**Interfaces:**
- Consumes: `Turn`, `DigestSession` from Task 3.
- Produces:
  - `is_summary_invocation(text: str) -> bool`
  - `is_prompt(text: str) -> bool`
  - `clean(text: str, limit: int) -> str`
  - `prompts(session: DigestSession) -> list[Turn]`
  - `conclusions(session: DigestSession, per_day: int = 5, min_chars: int = 200) -> list[Turn]`
  - `drop_summary_sessions(sessions: list[DigestSession]) -> list[DigestSession]`

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_standup_digest.py`:

```python
def make_session(turns, **overrides):
    fields = {
        "id": "s",
        "title": "t",
        "project": "p",
        "worktree": None,
        "branch": "main",
        "cwd": "/c",
        "recap": None,
        "transcript": Path("/t/s.jsonl"),
        "turns": turns,
    }
    fields.update(overrides)
    return sd.DigestSession(**fields)


def user(text, when="2026-09-04 10:00"):
    return sd.Turn(kind="user", when=local(when), text=text)


def bot(text, when="2026-09-04 10:00"):
    return sd.Turn(kind="assistant", when=local(when), text=text)


class TestIsPrompt:
    def test_rejects_a_skill_preamble(self):
        assert not sd.is_prompt("Base directory for this skill: /Users/x/.claude/skills/commit")

    def test_rejects_a_system_reminder(self):
        assert not sd.is_prompt("<system-reminder>be careful</system-reminder>")

    def test_rejects_whitespace(self):
        assert not sd.is_prompt("   ")

    def test_accepts_a_real_prompt(self):
        assert sd.is_prompt("can you open that in a browser?")


class TestClean:
    def test_collapses_newlines_and_runs_of_space(self):
        assert sd.clean("a\n\n  b", 100) == "a b"

    def test_truncates_to_the_limit(self):
        assert sd.clean("x" * 300, 200) == "x" * 200

    def test_collapses_an_image_attachment_marker(self):
        text = "look at [Image: source: /Users/x/CleanShot 2026-09-02 at 10.57.10@2x.png] here"

        assert sd.clean(text, 200) == "look at [image] here"


class TestSummaryInvocation:
    def test_detects_the_slash_command(self):
        assert sd.is_summary_invocation("/morning-summary")

    def test_detects_it_with_arguments(self):
        assert sd.is_summary_invocation("/morning-summary --since 3d")

    def test_detects_the_skill_preamble(self):
        assert sd.is_summary_invocation(
            "Base directory for this skill: /Users/x/.claude/skills/morning-summary"
        )

    def test_ignores_an_unrelated_prompt(self):
        assert not sd.is_summary_invocation("summarise the morning for me")


class TestDropSummarySessions:
    def test_drops_a_session_that_only_ran_the_summary(self):
        only = make_session([user("/morning-summary"), bot("here is your standup")])

        assert sd.drop_summary_sessions([only]) == []

    def test_keeps_a_session_that_also_did_work(self):
        mixed = make_session([user("/morning-summary"), user("now fix the parser")])

        kept = sd.drop_summary_sessions([mixed])

        assert len(kept) == 1

    def test_removes_the_invocation_turn_from_a_kept_session(self):
        mixed = make_session([user("/morning-summary"), user("now fix the parser")])

        kept = sd.drop_summary_sessions([mixed])

        assert [t.text for t in kept[0].turns if t.kind == "user"] == ["now fix the parser"]


class TestConclusions:
    def test_keeps_only_substantial_messages(self):
        session = make_session([bot("ok"), bot("x" * 250)])

        assert [t.text for t in sd.conclusions(session)] == ["x" * 250]

    def test_keeps_the_last_five_of_a_day(self):
        session = make_session([bot(f"{i}" * 250, "2026-09-04 10:00") for i in range(8)])

        kept = sd.conclusions(session)

        assert len(kept) == 5
        assert kept[0].text.startswith("3")

    def test_counts_each_day_separately(self):
        session = make_session(
            [bot(f"{i}" * 250, "2026-09-04 10:00") for i in range(6)]
            + [bot(f"{i}" * 250, "2026-09-05 10:00") for i in range(6)]
        )

        assert len(sd.conclusions(session)) == 10

    def test_ignores_user_turns(self):
        session = make_session([user("y" * 250)])

        assert sd.conclusions(session) == []


class TestPrompts:
    def test_returns_user_turns_that_are_real_prompts(self):
        session = make_session(
            [user("Base directory for this skill: /x"), user("do the thing"), bot("done")]
        )

        assert [t.text for t in sd.prompts(session)] == ["do the thing"]
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `just test`
Expected: FAIL with `AttributeError: module 'standup_digest' has no attribute 'is_prompt'`.

- [ ] **Step 3: Implement the filters**

Add to `standup-digest`:

```python
SKILL_PREAMBLE = "Base directory for this skill:"
SUMMARY_COMMAND = "/morning-summary"
SUMMARY_SKILL = "skills/morning-summary"
IMAGE_MARKER = re.compile(r"\[Image:[^\]]*\]")
PROMPT_LIMIT = 200
CONCLUSION_LIMIT = 400


def clean(text, limit):
    """Collapse to one line, replace attachment markers, and truncate."""
    collapsed = " ".join(IMAGE_MARKER.sub("[image]", text).split())
    return collapsed[:limit]


def is_prompt(text):
    """True for something Ted typed, as opposed to injected machinery."""
    stripped = text.strip()
    if not stripped or stripped.startswith("<"):
        return False
    return not stripped.startswith(SKILL_PREAMBLE)


def is_summary_invocation(text):
    """True when this turn is a run of the morning-summary skill itself."""
    stripped = text.strip()
    return stripped.startswith(SUMMARY_COMMAND) or (
        stripped.startswith(SKILL_PREAMBLE) and SUMMARY_SKILL in stripped
    )


def drop_summary_sessions(sessions):
    """Remove summary invocations, and any session that was nothing else."""
    kept = []
    for session in sessions:
        turns = [t for t in session.turns if not is_summary_invocation(t.text)]
        if not any(t.kind == "user" and is_prompt(t.text) for t in turns):
            continue
        session.turns = turns
        kept.append(session)
    return kept


def prompts(session):
    """The user turns worth showing."""
    return [t for t in session.turns if t.kind == "user" and is_prompt(t.text)]


def conclusions(session, per_day=5, min_chars=200):
    """The last few substantial assistant messages of each day."""
    by_day = defaultdict(list)
    for t in session.turns:
        if t.kind == "assistant" and len(t.text) >= min_chars:
            by_day[t.when.date()].append(t)
    kept = []
    for day in sorted(by_day):
        kept.extend(by_day[day][-per_day:])
    return kept
```

Note that `drop_summary_sessions` requires a surviving *user* prompt, which
also discards a session whose only content was an assistant turn.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `just test`
Expected: PASS for all of `TestIsPrompt`, `TestClean`, `TestSummaryInvocation`,
`TestDropSummarySessions`, `TestConclusions` and `TestPrompts`.

- [ ] **Step 5: Commit**

```bash
git add standup-digest tests/test_standup_digest.py
git commit -m "Filter transcript turns and exclude morning-summary's own runs"
```

---

### Task 5: Repository discovery and commits

**Files:**
- Modify: `standup-digest`
- Modify: `tests/test_standup_digest.py`

**Interfaces:**
- Consumes: `DigestSession` from Task 3, `Window` from Task 2.
- Produces:
  - `git_root(path: str) -> Path | None` — the main working tree of the
    repository containing `path`, with worktrees resolved to their parent.
  - `discover_repos(sessions: list[DigestSession]) -> list[Path]` — de-duplicated,
    sorted.
  - `Commit` dataclass: `repo: str`, `when: datetime`, `sha: str`, `subject: str`.
  - `commits_in(repo: Path, window: Window) -> list[Commit]`

A git worktree's `.git` is a file, and `git rev-parse --show-toplevel` inside
one returns the worktree, not the parent. `--git-common-dir` points at the
parent's `.git`, so its parent directory is the main working tree. That is how
a worktree and its parent collapse to one repository.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_standup_digest.py`:

```python
import subprocess


def git(repo, *args):
    subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True)


@pytest.fixture
def repo(tmp_path):
    """A real git repository with one commit, authored by a known address."""
    root = tmp_path / "repo"
    root.mkdir()
    git(root, "init", "-q", "-b", "main")
    git(root, "config", "user.email", "ted@example.com")
    git(root, "config", "user.name", "Ted Naleid")
    (root / "a.txt").write_text("a")
    git(root, "add", "a.txt")
    git(root, "commit", "-q", "-m", "First commit")
    return root


class TestGitRoot:
    def test_finds_the_top_level(self, repo):
        nested = repo / "sub"
        nested.mkdir()

        assert sd.git_root(str(nested)) == repo

    def test_a_worktree_resolves_to_its_parent(self, repo, tmp_path):
        tree = tmp_path / "wt"
        git(repo, "worktree", "add", "-q", "-b", "side", str(tree))

        assert sd.git_root(str(tree)) == repo

    def test_returns_none_outside_a_repository(self, tmp_path):
        loose = tmp_path / "loose"
        loose.mkdir()

        assert sd.git_root(str(loose)) is None

    def test_returns_none_for_a_missing_directory(self, tmp_path):
        assert sd.git_root(str(tmp_path / "gone")) is None


class TestDiscoverRepos:
    def test_collapses_a_worktree_and_its_parent(self, repo, tmp_path):
        tree = tmp_path / "wt"
        git(repo, "worktree", "add", "-q", "-b", "side", str(tree))
        sessions = [make_session([], cwd=str(repo)), make_session([], cwd=str(tree))]

        assert sd.discover_repos(sessions) == [repo]

    def test_ignores_sessions_with_no_cwd(self):
        assert sd.discover_repos([make_session([], cwd=None)]) == []


class TestCommitsIn:
    def test_finds_a_commit_by_the_repo_identity(self, repo):
        window = sd.compute_window(datetime.now().astimezone(), since="1d", until=None)

        found = sd.commits_in(repo, window)

        assert [c.subject for c in found] == ["First commit"]

    def test_ignores_another_author(self, repo):
        git(repo, "config", "user.email", "someone.else@example.com")
        (repo / "b.txt").write_text("b")
        git(repo, "add", "b.txt")
        git(repo, "commit", "-q", "-m", "Their commit")
        git(repo, "config", "user.email", "ted@example.com")
        window = sd.compute_window(datetime.now().astimezone(), since="1d", until=None)

        assert [c.subject for c in sd.commits_in(repo, window)] == ["First commit"]

    def test_ignores_a_commit_outside_the_window(self, repo):
        window = sd.compute_window(
            datetime.now().astimezone(), since="2020-01-01", until="2020-01-02"
        )

        assert sd.commits_in(repo, window) == []
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `just test`
Expected: FAIL with `AttributeError: module 'standup_digest' has no attribute 'git_root'`.

- [ ] **Step 3: Implement discovery and commit gathering**

Add to `standup-digest`:

```python
@dataclass
class Commit:
    repo: str
    when: datetime
    sha: str
    subject: str


def run_git(repo, *args):
    """Run git in a repository, returning stdout, or None if it fails."""
    try:
        done = subprocess.run(
            ["git", "-C", str(repo), *args], capture_output=True, text=True, check=True
        )
    except (subprocess.CalledProcessError, FileNotFoundError, NotADirectoryError):
        return None
    return done.stdout.strip()


def git_root(path):
    """The main working tree containing path, with worktrees folded into it."""
    if not Path(path).is_dir():
        return None
    common = run_git(path, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if not common:
        return None
    return Path(common).parent


def discover_repos(sessions):
    """Every distinct repository the window's sessions were run in."""
    roots = {git_root(s.cwd) for s in sessions if s.cwd}
    return sorted(r for r in roots if r)


def commits_in(repo, window):
    """Commits in the window authored by this repository's configured identity."""
    email = run_git(repo, "config", "user.email")
    if not email:
        return []
    out = run_git(
        repo,
        "log",
        "--all",
        "--no-merges",
        f"--author={email}",
        f"--since={window.start.isoformat()}",
        f"--until={window.end.isoformat()}",
        "--format=%H%x1f%cI%x1f%s",
    )
    if not out:
        return []
    commits = []
    for line in out.splitlines():
        sha, when, subject = line.split("\x1f", 2)
        commits.append(
            Commit(
                repo=repo.name,
                when=datetime.fromisoformat(when).astimezone(),
                sha=sha[:8],
                subject=subject,
            )
        )
    return commits
```

`--all` is needed because the work may sit on a branch that is not checked
out in the main working tree; a worktree's commits are reachable from the
parent's ref store.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `just test`
Expected: PASS for `TestGitRoot`, `TestDiscoverRepos` and `TestCommitsIn`.

- [ ] **Step 5: Commit**

```bash
git add standup-digest tests/test_standup_digest.py
git commit -m "Discover repositories from sessions and gather their commits"
```

---

### Task 6: Merge request activity

**Files:**
- Modify: `standup-digest`
- Modify: `tests/test_standup_digest.py`

**Interfaces:**
- Consumes: `Window` from Task 2, `discover_repos` from Task 5.
- Produces:
  - `remote_host(repo: Path) -> str | None` — the hostname of `origin`.
  - `mr_activity(repos: list[Path], window: Window) -> tuple[list[str], list[str]]`
    returning `(lines, problems)`.

**The API shapes here are unverified and must be confirmed against a live
response before the implementation is written.** This is the part of the
design most likely to be wrong.

- [ ] **Step 1: Find out what the APIs actually return**

Run these and read the output. Do not skip this step and do not write the
implementation from the guesses below.

```bash
glab api "events?after=2026-09-01&before=2026-09-09&per_page=20" | jq '.[0]'
glab api "events?after=2026-09-01&before=2026-09-09&per_page=20" \
  | jq -r '[.[] | .action_name] | unique'
gh search prs --involves=@me --updated=">=2026-09-01" --json number,title,url,updatedAt,state --limit 5
```

Note in particular whether `after`/`before` are exclusive, what
`action_name` values appear for opening, merging, approving and commenting,
and whether the event carries enough to name the MR without a second call.

Write down what you found in the commit message for this task. If the shapes
differ from the guesses below, follow what you observed.

- [ ] **Step 2: Write the failing tests**

Only the degradation behaviour and host parsing are unit-tested; the API
shapes are covered by Step 1 and the end-to-end run in Task 7. Append:

```python
class TestRemoteHost:
    def test_reads_an_ssh_remote(self, repo):
        git(repo, "remote", "add", "origin", "git@gitlab.example.com:group/thing.git")

        assert sd.remote_host(repo) == "gitlab.example.com"

    def test_reads_an_https_remote(self, repo):
        git(repo, "remote", "add", "origin", "https://github.com/owner/thing.git")

        assert sd.remote_host(repo) == "github.com"

    def test_returns_none_without_a_remote(self, repo):
        assert sd.remote_host(repo) is None


class TestMrActivityDegradation:
    def test_an_unreachable_host_becomes_a_problem_line_not_an_exception(
        self, repo, monkeypatch
    ):
        git(repo, "remote", "add", "origin", "git@gitlab.example.com:group/thing.git")
        monkeypatch.setattr(sd, "run_tool", lambda *a, **k: None)
        window = sd.compute_window(datetime.now().astimezone(), since="1d", until=None)

        lines, problems = sd.mr_activity([repo], window)

        assert lines == []
        assert any("gitlab.example.com" in p for p in problems)
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `just test`
Expected: FAIL with `AttributeError: module 'standup_digest' has no attribute 'remote_host'`.

- [ ] **Step 4: Implement, following what Step 1 observed**

Add to `standup-digest`. The `glab`/`gh` argument lists below are the starting
guess; replace them with what Step 1 showed.

```python
REMOTE_HOST = re.compile(r"^(?:[\w.+-]+@|\w+://(?:[^@/]+@)?)([^:/]+)")


def run_tool(*args):
    """Run an external CLI, returning stdout, or None if it is unavailable."""
    try:
        done = subprocess.run(list(args), capture_output=True, text=True, check=True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None
    return done.stdout.strip()


def remote_host(repo):
    """The hostname of the repository's origin remote."""
    url = run_git(repo, "remote", "get-url", "origin")
    if not url:
        return None
    match = REMOTE_HOST.match(url)
    return match.group(1) if match else None


def mr_activity(repos, window):
    """Merge request events in the window, plus a list of what could not be read."""
    lines, problems = [], []
    hosts = {remote_host(r) for r in repos}
    for host in sorted(h for h in hosts if h):
        tool = ["gh"] if host == "github.com" else ["glab"]
        raw = run_tool(
            *tool,
            "api",
            f"events?after={window.start:%Y-%m-%d}&before={window.end:%Y-%m-%d}&per_page=100",
        )
        if raw is None:
            problems.append(f"{host}: could not be read")
            continue
        lines.extend(format_events(host, raw, window))
    return lines, problems
```

And `format_events`, whose field names are the ones Step 1 must confirm or
correct:

```python
MR_ACTIONS = {"opened", "merged", "approved", "commented on", "closed"}


def format_events(host, raw, window):
    """Render merge request events inside the window as one line each."""
    try:
        events = json.loads(raw)
    except ValueError:
        return []
    lines = []
    for event in events:
        if event.get("target_type") not in ("MergeRequest", "Note"):
            continue
        action = event.get("action_name", "")
        if not any(action.startswith(known) for known in MR_ACTIONS):
            continue
        when = datetime.fromisoformat(event["created_at"]).astimezone()
        if not window.start <= when <= window.end:
            continue
        iid = event.get("target_iid") or "?"
        title = clean(event.get("target_title") or "", 120)
        lines.append(f"{when:%Y-%m-%d} {host} !{iid} {action}: {title}")
    return lines
```

The window is re-checked here because the API's `after` and `before`
parameters are day-granular, so the response overshoots both ends.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `just test`
Expected: PASS for `TestRemoteHost` and `TestMrActivityDegradation`.

- [ ] **Step 6: Verify against the real thing**

```bash
./standup-digest --since 4d 2>&1 | sed -n '/## merge requests/,$p'
```

Expected: real MR lines for the window, or a `problems:` line naming the host.
A traceback here is a failure of this task.

- [ ] **Step 7: Commit**

```bash
git add standup-digest tests/test_standup_digest.py
git commit -m "Gather merge request activity, degrading to a problem line"
```

Record in the commit body what Step 1 observed about the event API.

---

### Task 7: Rendering, widening and the command line

**Files:**
- Modify: `standup-digest`
- Modify: `tests/test_standup_digest.py`

**Interfaces:**
- Consumes: everything from Tasks 2 through 6.
- Produces:
  - `load_index() -> list[dict]` — parsed `csess list -a --json`.
  - `render(window, sessions, commits, mr_lines, problems) -> str`
  - `gather(now, since, until) -> str` — the whole pipeline, including widening.
  - `main(argv=None) -> int`

- [ ] **Step 1: Write the failing tests**

Append:

```python
class TestRender:
    def test_includes_the_window_label(self):
        out = sd.render(sd.default_window(local("2026-09-08 09:00")), [], [], [], [])

        assert "2026-09-07" in out

    def test_shows_a_session_with_its_recap_and_turns(self):
        session = make_session(
            [user("fix the parser"), bot("z" * 250)], recap="we fixed it", title="parser-work"
        )
        window = sd.default_window(local("2026-09-08 09:00"))

        out = sd.render(window, [session], [], [], [])

        assert "parser-work" in out
        assert "we fixed it" in out
        assert "fix the parser" in out
        assert "z" * 250 in out

    def test_truncates_a_long_prompt(self):
        session = make_session([user("q" * 400)])
        window = sd.default_window(local("2026-09-08 09:00"))

        out = sd.render(window, [session], [], [], [])

        assert "q" * 200 in out
        assert "q" * 201 not in out

    def test_tags_each_turn_with_its_date(self):
        session = make_session([user("today's work", "2026-09-07 10:00")])
        window = sd.default_window(local("2026-09-08 09:00"))

        assert "2026-09-07" in sd.render(window, [session], [], [], [])

    def test_lists_problems_when_a_host_failed(self):
        window = sd.default_window(local("2026-09-08 09:00"))

        out = sd.render(window, [], [], [], ["gitlab.example.com: could not be read"])

        assert "gitlab.example.com" in out


class TestGatherWidening:
    def test_widens_when_the_first_window_is_empty(self, monkeypatch):
        calls = []

        def fake_select(index, window):
            calls.append(window.start.date())
            return [] if len(calls) == 1 else [make_session([user("work")])]

        monkeypatch.setattr(sd, "load_index", lambda: [])
        monkeypatch.setattr(sd, "select_sessions", fake_select)
        monkeypatch.setattr(sd, "discover_repos", lambda s: [])
        monkeypatch.setattr(sd, "mr_activity", lambda r, w: ([], []))

        out = sd.gather(local("2026-09-08 09:00"), None, None)

        assert len(calls) == 2
        assert "widened" in out

    def test_does_not_widen_when_a_manual_window_is_given(self, monkeypatch):
        calls = []

        def fake_select(index, window):
            calls.append(window.start.date())
            return []

        monkeypatch.setattr(sd, "load_index", lambda: [])
        monkeypatch.setattr(sd, "select_sessions", fake_select)
        monkeypatch.setattr(sd, "discover_repos", lambda s: [])
        monkeypatch.setattr(sd, "mr_activity", lambda r, w: ([], []))

        sd.gather(local("2026-09-08 09:00"), since="2026-09-01", until=None)

        assert len(calls) == 1
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `just test`
Expected: FAIL with `AttributeError: module 'standup_digest' has no attribute 'render'`.

- [ ] **Step 3: Implement rendering, gathering and the CLI**

Add to `standup-digest`:

```python
def load_index():
    """Every known session, as csess reports it."""
    raw = run_tool("csess", "list", "-a", "--json")
    if not raw:
        return []
    try:
        return json.loads(raw)
    except ValueError:
        return []


def session_heading(session):
    where = session.project
    if session.worktree:
        where = f"{where}/{session.worktree}"
    return f"### {where} ({session.branch or '-'}) {session.title}"


def render(window, sessions, commits, mr_lines, problems):
    """The digest the morning-summary skill reads."""
    out = ["# standup digest", "", f"window: {window.label}", "", "## sessions"]
    if not sessions:
        out.append("")
        out.append("none")
    for session in sessions:
        out += ["", session_heading(session)]
        if session.recap:
            out.append(f"recap: {clean(session.recap, 600)}")
        out.append(f"transcript: {session.transcript}")
        for turn in prompts(session):
            out.append(f"- prompt {turn.when:%Y-%m-%d %H:%M} {clean(turn.text, PROMPT_LIMIT)}")
        for turn in conclusions(session):
            out.append(
                f"- said {turn.when:%Y-%m-%d %H:%M} {clean(turn.text, CONCLUSION_LIMIT)}"
            )

    out += ["", "## commits"]
    out.append("" if commits else "none")
    for commit in sorted(commits, key=lambda c: c.when):
        out.append(f"- {commit.when:%Y-%m-%d} {commit.repo} {commit.sha} {commit.subject}")

    out += ["", "## merge requests"]
    out.append("" if mr_lines else "none")
    out += [f"- {line}" for line in mr_lines]

    if problems:
        out += ["", "## problems"] + [f"- {p}" for p in problems]
    return "\n".join(out) + "\n"


def gather(now, since, until):
    """Run the whole pipeline, widening an empty default window once."""
    index = load_index()
    window = compute_window(now, since, until)
    sessions = drop_summary_sessions(select_sessions(index, window))
    if not sessions and not since and not until:
        window = widen(window)
        sessions = drop_summary_sessions(select_sessions(index, window))
    repos = discover_repos(sessions)
    commits = [c for repo in repos for c in commits_in(repo, window)]
    mr_lines, problems = mr_activity(repos, window)
    return render(window, sessions, commits, mr_lines, problems)


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="standup-digest",
        description="Gather one working day of sessions, commits and MR activity.",
    )
    parser.add_argument("--since", metavar="WHEN", help="12h, 14d, 2w, YYYY-MM-DD or YYYY-MM-DDTHH:MM")
    parser.add_argument("--until", metavar="WHEN", help="same forms; defaults to now")
    args = parser.parse_args(argv)
    try:
        sys.stdout.write(gather(datetime.now().astimezone(), args.since, args.until))
    except ValueError as exc:
        sys.exit(f"standup-digest: {exc}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `just test`
Expected: PASS for `TestRender` and `TestGatherWidening`, and every earlier test.

- [ ] **Step 5: Run it for real and read the output**

```bash
chmod +x standup-digest
./standup-digest --since 4d | head -60
./standup-digest --since 4d | wc -l
```

Expected: a digest naming real sessions, in the 200 to 400 line range from the
spec. If it is far longer, the truncation limits or `per_day` are wrong; fix
them and note the change.

Confirm no session in the output is a `morning-summary` run.

- [ ] **Step 6: Commit**

```bash
git add standup-digest tests/test_standup_digest.py
git commit -m "Render the digest and wire up the standup-digest command line"
```

---

### Task 8: Installation

**Files:**
- Modify: `justfile`
- Modify: `zshrc`

**Interfaces:**
- Consumes: the `standup-digest` script from Task 7.
- Produces: `~/.local/bin/standup-digest` on PATH, and a `morning-summary`
  shell alias.

- [ ] **Step 1: Add the justfile recipe**

In `justfile`, after the `csess` recipe:

```just
# set up standup-digest, the daily standup gatherer
standup-digest:
    @mkdir -p {{home_directory()}}/.local/bin
    @just _symlink {{justfile_directory()}}/standup-digest {{home_directory()}}/.local/bin/standup-digest
```

Add `standup-digest` to the `all` recipe's dependency list, after `csess`, and
add a line to the `default` recipe's help text:

```
    @echo "  just standup-digest - set up the daily standup gatherer"
```

- [ ] **Step 2: Install and confirm it is on PATH**

```bash
just standup-digest
which standup-digest
standup-digest --help
```

Expected: the symlink is created, `which` resolves it, and `--help` prints the
two options.

- [ ] **Step 3: Add the alias**

In `zshrc`, beside the other aliases:

```sh
alias morning-summary='claude -p "/morning-summary"'
```

Leave the tool allowlist off for now. Task 9 Step 4 determines whether one is
needed by observing a real run.

- [ ] **Step 4: Commit**

```bash
git add justfile zshrc
git commit -m "Install standup-digest and add the morning-summary alias"
```

---

### Task 9: The morning-summary skill

**Files:**
- Create: `.claude/skills/morning-summary/SKILL.md`

**Interfaces:**
- Consumes: `standup-digest` on PATH.
- Produces: a skill invocable as `/morning-summary`, which writes
  `${XDG_STATE_HOME:-$HOME/.local/state}/standup/YYYY-MM-DD.md`.

- [ ] **Step 1: Write the skill**

Create `.claude/skills/morning-summary/SKILL.md`:

````markdown
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

The digest reports its window on the second line. Say what it was if it
was widened past the previous working day, because that means the previous
working day held no work.

### 2. Read the digest

Each session block carries a recap, the user's prompts, and the last few
substantial assistant messages of each day.

The recap is already a model-written summary and is usually the best single
source for what a session was about. The assistant messages are where
concrete outcomes live: a merged MR number, a verified plan, a root cause.

Group across sessions. One piece of work often spans several sessions, and
several worktrees of the same repository; it gets one bullet, not three.

If a session looks substantial but its recap is thin and its messages do not
explain what happened, read that one transcript directly with the path in
its `transcript:` line. Do this for one or two sessions at most.

### 3. Split yesterday from today

Every prompt and message is tagged with its date. Anything dated today is
not a `Y:` bullet; it is a `T:` candidate.

### 4. Write the report

Write to `${XDG_STATE_HOME:-$HOME/.local/state}/standup/$(date +%Y-%m-%d).md`,
creating the directory if needed.

Then copy only the Slack section to the clipboard:

```bash
sed -n '/^## Slack$/,/^---$/p' "$file" | sed '1d;$d' | pbcopy
```

Print the whole file to the conversation, then say the path and that the
Slack section is on the clipboard.

## Output format

```markdown
## Slack

Y:
- <one bullet per story or thread, leading with the ticket or MR number>

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
- Meetings never appear in the digest. Always leave the
  `[meetings / anything not in a session]` line for the user to fill.
- Never report a merge, a deploy, or a fix as done unless the digest says
  so. A plan to do a thing is not the thing.
- No emojis, no em-dashes, no hyperbole.
````

- [ ] **Step 2: Install the skill**

```bash
just claude-skills
ls ~/.claude/skills/morning-summary/
```

Expected: `SKILL.md` present.

- [ ] **Step 3: Run it interactively and read the output**

In a Claude Code session: `/morning-summary --since 4d`

Expected: both sections, at most five `Y:` bullets, the file written under
`~/.local/state/standup/`, and the Slack block on the clipboard. Check the
clipboard with `pbpaste`.

- [ ] **Step 4: Run it headlessly and fix the allowlist**

```bash
morning-summary
```

Expected: the same output with no permission prompt. If it stalls or reports
a denied tool, note which tool it wanted and add the allowlist to the alias in
`zshrc`, for example:

```sh
alias morning-summary='claude -p "/morning-summary" --allowedTools Bash Read Write'
```

Then re-run and confirm.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/morning-summary/SKILL.md zshrc
git commit -m "Add the morning-summary skill"
```

---

### Task 10: Compare against the baseline

**Files:**
- Modify: `standup-digest` (only if the comparison finds a real gap)
- Modify: `${XDG_STATE_HOME:-$HOME/.local/state}/standup/2026-09-08-manual-baseline.md` (append the outcome)

- [ ] **Step 1: Run the tool over the baseline's exact window**

Read the two boundaries from the `Window:` line at the top of the baseline
file and pin the run to them:

```bash
standup-digest --since <baseline start> --until <baseline end> > /tmp/digest.md
wc -l /tmp/digest.md
```

Pinning both ends matters. Without `--until`, the window would include all of
the implementation work done since Task 1, and the comparison would measure
the clock rather than the extraction.

- [ ] **Step 2: Summarize the pinned digest**

In a Claude Code session: `/morning-summary --since <start> --until <end>`

- [ ] **Step 3: Compare, and answer three questions in writing**

1. Did the tool find every thread the hand pass found? A missing thread means
   the window, the session filter, or the exclusion rule dropped something.
2. Did the tool invent a thread that was not real work? That usually means a
   probe or throwaway session survived filtering.
3. Is the detail it kept the detail worth keeping? This is the assistant
   selection heuristic, the part most likely to need tuning.

- [ ] **Step 4: Fix what the comparison found**

Only change the heuristic if the comparison showed a real gap. Likely knobs,
in order of how much they cost: `per_day`, `min_chars`, `CONCLUSION_LIMIT`,
and whether user prompts need a longer `PROMPT_LIMIT`.

Any change here needs a test in `tests/test_standup_digest.py` that pins the
new behaviour, and `just test` must pass.

- [ ] **Step 5: Append the outcome to the baseline file**

Add a short section recording what the comparison found and what changed as a
result. This is the record of whether the heuristic was any good; without it
the next person tuning it starts from nothing.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Tune standup-digest against the hand-built baseline"
```
