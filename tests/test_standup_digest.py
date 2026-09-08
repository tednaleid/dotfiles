# ABOUTME: unit tests for the pure logic in the standup-digest gatherer
# ABOUTME: transcripts and git repos are synthesised on disk; no real data is read

import importlib.machinery
import json
import os
import subprocess
import types
from datetime import date, datetime, timedelta, timezone
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


class TestWindowAcrossDaylightSaving:
    def test_midnight_is_midnight_on_the_target_date(self):
        """A Monday in CST reaching back to a Friday in CDT still starts at 00:00."""
        start = sd.default_window(local("2026-11-02 09:00")).start

        assert (start.year, start.month, start.day) == (2026, 10, 30)
        assert (start.hour, start.minute) == (0, 0)


class TestLabelRendering:
    def test_label_renders_correct_date_across_dst(self):
        """Label correctly renders the wall-clock date even across DST transition."""
        window = sd.default_window(local("2026-11-02 09:00"))

        assert "2026-10-30" in window.label


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


class TestReadTurns:
    def test_reads_text_and_converts_to_local(self, tmp_path):
        path = write_transcript(
            tmp_path, "p", "s", [turn("user", "2026-09-04T18:30:00.000Z", "hello")]
        )

        turns = sd.read_turns(path)

        assert [t.kind for t in turns] == ["user"]
        assert turns[0].text == "hello"
        assert turns[0].when == datetime(2026, 9, 4, 18, 30, tzinfo=timezone.utc)

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

    def test_skips_user_record_with_no_timestamp_key(self, tmp_path):
        path = write_transcript(
            tmp_path,
            "p",
            "s",
            [
                {
                    "type": "user",
                    "message": {"content": [{"type": "text", "text": "no timestamp"}]},
                },
                turn("assistant", "2026-09-04T18:30:00.000Z", "ok"),
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
        inside = local("2026-09-04 12:00").timestamp()
        os.utime(path, (inside, inside))
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

    def test_drops_the_recap_when_the_session_continued_past_a_pinned_window(self, tmp_path):
        """The recap describes the session's latest state, which may be later than
        the pinned window's end; a session that kept going past that boundary
        cannot be trusted to describe only what the window covers. This only
        applies when the caller pinned the end with an explicit --until."""
        path = write_transcript(
            tmp_path,
            "p",
            "s",
            [
                turn("user", "2026-09-04T18:30:00.000Z", "during the window"),
                turn("user", "2026-09-05T20:00:00.000Z", "after the window closed"),
            ],
        )
        window = sd.compute_window(
            local("2026-09-05 09:00"), since="2026-09-04", until="2026-09-05T09:00"
        )

        selected = sd.select_sessions([index_entry(path)], window, pin_end=True)

        assert selected[0].recap is None

    def test_keeps_the_recap_when_the_session_ends_inside_a_pinned_window(self, tmp_path):
        path = write_transcript(
            tmp_path, "p", "s", [turn("user", "2026-09-04T18:30:00.000Z", "during the window")]
        )
        window = sd.compute_window(
            local("2026-09-05 09:00"), since="2026-09-04", until="2026-09-05T09:00"
        )

        selected = sd.select_sessions([index_entry(path)], window, pin_end=True)

        assert selected[0].recap == "a recap"

    def test_keeps_the_recap_on_a_default_run_even_past_the_window(self, tmp_path):
        """A default run's window ends at 'now', and any other session running
        concurrently can log a turn after that instant purely from the time
        gather() itself takes; that is concurrency, not foreknowledge, and
        must not cost the session its recap."""
        path = write_transcript(
            tmp_path,
            "p",
            "s",
            [
                turn("user", "2026-09-04T18:30:00.000Z", "during the window"),
                turn("user", "2026-09-05T20:00:00.000Z", "after the window closed"),
            ],
        )
        window = sd.compute_window(
            local("2026-09-05 09:00"), since="2026-09-04", until="2026-09-05T09:00"
        )

        selected = sd.select_sessions([index_entry(path)], window)

        assert selected[0].recap == "a recap"

    def test_tolerates_a_transcript_that_has_been_deleted(self, tmp_path):
        window = sd.compute_window(
            local("2026-09-05 09:00"), since="2026-09-04", until="2026-09-05T09:00"
        )
        missing = index_entry(tmp_path / "gone.jsonl")

        assert sd.select_sessions([missing], window) == []


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


class TestPromptRepeats:
    def test_folds_a_run_of_identical_prompts(self):
        session = make_session([user("poll the MR") for _ in range(5)])

        folded = sd.prompts(session)

        assert len(folded) == 1
        assert folded[0].repeats == 5
        assert folded[0].text == "poll the MR"

    def test_keeps_the_first_timestamp_of_the_run(self):
        session = make_session(
            [user("poll the MR", "2026-09-07 08:00"), user("poll the MR", "2026-09-07 09:00")]
        )

        assert sd.prompts(session)[0].when == local("2026-09-07 08:00")

    def test_a_single_prompt_gets_no_count(self):
        session = make_session([user("do the thing")])

        assert sd.prompts(session)[0].text == "do the thing"
        assert sd.prompts(session)[0].repeats == 1

    def test_does_not_fold_across_a_different_prompt(self):
        session = make_session([user("same"), user("other"), user("same")])

        assert [t.text for t in sd.prompts(session)] == ["same", "other", "same"]


class TestIsAutomatedTurns:
    def test_a_repeated_single_prompt_is_automated(self):
        turns = [user("poll the MR") for _ in range(4)]

        assert sd.is_automated_turns(turns)

    def test_a_one_shot_session_is_not_automated(self):
        turns = [user("do the thing")]

        assert not sd.is_automated_turns(turns)

    def test_a_session_with_varied_prompts_is_not_automated(self):
        turns = [user("poll"), user("poll"), user("poll"), user("now fix it")]

        assert not sd.is_automated_turns(turns)

    def test_two_repeats_is_below_the_floor(self):
        turns = [user("poll"), user("poll")]

        assert not sd.is_automated_turns(turns)

    def test_exactly_the_floor_is_automated(self):
        turns = [user("poll") for _ in range(sd.AUTOMATION_REPEATS)]

        assert sd.is_automated_turns(turns)


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

    def test_finds_a_commit_on_a_branch_not_checked_out(self, repo, tmp_path):
        tree = tmp_path / "wt"
        git(repo, "worktree", "add", "-q", "-b", "side", str(tree))
        (tree / "c.txt").write_text("c")
        git(tree, "add", "c.txt")
        git(tree, "commit", "-q", "-m", "Worktree commit")
        window = sd.compute_window(datetime.now().astimezone(), since="1d", until=None)

        subjects = [c.subject for c in sd.commits_in(repo, window)]

        assert "Worktree commit" in subjects

    def test_ignores_a_merge_commit(self, repo):
        git(repo, "checkout", "-q", "-b", "side")
        (repo / "d.txt").write_text("d")
        git(repo, "add", "d.txt")
        git(repo, "commit", "-q", "-m", "Side commit")
        git(repo, "checkout", "-q", "main")
        (repo / "e.txt").write_text("e")
        git(repo, "add", "e.txt")
        git(repo, "commit", "-q", "-m", "Main commit")
        git(repo, "merge", "--no-ff", "-q", "-m", "Merge side into main", "side")
        window = sd.compute_window(datetime.now().astimezone(), since="1d", until=None)

        subjects = [c.subject for c in sd.commits_in(repo, window)]

        assert "Merge side into main" not in subjects
        assert "Side commit" in subjects


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

    def test_a_malformed_response_becomes_a_problem_line_not_silence(self, repo, monkeypatch):
        git(repo, "remote", "add", "origin", "git@gitlab.example.com:group/thing.git")
        monkeypatch.setattr(sd, "run_tool", lambda *a, **k: "not json")
        window = sd.compute_window(datetime.now().astimezone(), since="1d", until=None)

        lines, problems = sd.mr_activity([repo], window)

        assert lines == []
        assert any("gitlab.example.com" in p for p in problems)

    def test_passes_the_hostname_from_the_remote(self, repo, monkeypatch):
        git(repo, "remote", "add", "origin", "git@gitlab.example.com:group/thing.git")
        seen = []
        monkeypatch.setattr(sd, "run_tool", lambda *args: seen.append(args) or None)
        window = sd.compute_window(datetime.now().astimezone(), since="1d", until=None)

        sd.mr_activity([repo], window)

        assert "--hostname" in seen[0]
        assert "gitlab.example.com" in seen[0]

    def test_paginates_the_events_request(self, repo, monkeypatch):
        git(repo, "remote", "add", "origin", "git@gitlab.example.com:group/thing.git")
        seen = []
        monkeypatch.setattr(sd, "run_tool", lambda *args: seen.append(args) or None)
        window = sd.compute_window(datetime.now().astimezone(), since="1d", until=None)

        sd.mr_activity([repo], window)

        assert "--paginate" in seen[0]


class TestFormatGithubPrs:
    def test_renders_a_pull_request_inside_the_window(self):
        window = sd.compute_window(
            local("2026-09-05 09:00"), since="2026-09-04", until="2026-09-05T09:00"
        )
        pulls = [
            {
                "number": 7,
                "title": "fix the parser",
                "state": "OPEN",
                "updatedAt": "2026-09-04T15:00:00-05:00",
                "repository": {"nameWithOwner": "ted/thing"},
            }
        ]

        lines = sd.format_github_prs(pulls, window)

        assert lines == ["2026-09-04 ted/thing #7 OPEN: fix the parser"]

    def test_drops_a_pull_request_outside_the_window(self):
        window = sd.compute_window(
            local("2026-09-05 09:00"), since="2026-09-04", until="2026-09-05T09:00"
        )
        pulls = [
            {
                "number": 7,
                "title": "old",
                "state": "OPEN",
                "updatedAt": "2026-08-01T15:00:00-05:00",
                "repository": {"nameWithOwner": "ted/thing"},
            }
        ]

        assert sd.format_github_prs(pulls, window) == []


class TestMrActivityGithub:
    def test_a_github_remote_selects_gh_over_glab(self, repo, monkeypatch):
        git(repo, "remote", "add", "origin", "https://github.com/ted/thing.git")
        seen = []
        monkeypatch.setattr(sd, "run_tool", lambda *args: seen.append(args) or None)
        window = sd.compute_window(datetime.now().astimezone(), since="1d", until=None)

        sd.mr_activity([repo], window)

        assert seen[0][0] == "gh"

    def test_a_well_formed_response_renders_into_lines(self, repo, monkeypatch):
        git(repo, "remote", "add", "origin", "https://github.com/ted/thing.git")
        now = datetime.now().astimezone()
        payload = json.dumps(
            [
                {
                    "number": 7,
                    "title": "fix the parser",
                    "state": "OPEN",
                    "updatedAt": now.isoformat(),
                    "repository": {"nameWithOwner": "ted/thing"},
                }
            ]
        )
        monkeypatch.setattr(sd, "run_tool", lambda *a, **k: payload)
        window = sd.compute_window(now, since="1d", until=None)

        lines, problems = sd.mr_activity([repo], window)

        assert problems == []
        assert any("#7" in line and "fix the parser" in line for line in lines)

    def test_an_unreachable_host_becomes_a_problem_line(self, repo, monkeypatch):
        git(repo, "remote", "add", "origin", "https://github.com/ted/thing.git")
        monkeypatch.setattr(sd, "run_tool", lambda *a, **k: None)
        window = sd.compute_window(datetime.now().astimezone(), since="1d", until=None)

        lines, problems = sd.mr_activity([repo], window)

        assert lines == []
        assert any("github.com" in p for p in problems)

    def test_a_malformed_response_becomes_a_problem_line(self, repo, monkeypatch):
        git(repo, "remote", "add", "origin", "https://github.com/ted/thing.git")
        monkeypatch.setattr(sd, "run_tool", lambda *a, **k: "not json")
        window = sd.compute_window(datetime.now().astimezone(), since="1d", until=None)

        lines, problems = sd.mr_activity([repo], window)

        assert lines == []
        assert any("github.com" in p for p in problems)


class TestParseJson:
    def test_parses_a_single_document(self):
        assert sd.parse_json("[1, 2]") == [1, 2]

    def test_flattens_concatenated_paginated_pages(self):
        """glab api --paginate writes one JSON array per page, back to back,
        rather than merging them into a single array."""
        assert sd.parse_json("[1, 2][3, 4]") == [1, 2, 3, 4]

    def test_returns_none_for_garbage(self):
        assert sd.parse_json("not json") is None

    def test_returns_none_when_a_concatenated_document_is_not_a_list(self):
        assert sd.parse_json('[1, 2]{"a": 1}') is None


class TestResolveMrIid:
    def test_a_merge_request_event_uses_its_own_iid(self):
        event = {"target_type": "MergeRequest", "target_iid": 42}

        assert sd.resolve_mr_iid(event) == 42

    def test_a_note_on_a_merge_request_uses_the_note_s_parent_iid(self):
        event = {
            "target_type": "Note",
            "target_iid": 999999,
            "note": {"noteable_type": "MergeRequest", "noteable_iid": 42},
        }

        assert sd.resolve_mr_iid(event) == 42

    def test_a_note_with_no_note_payload_returns_none(self):
        event = {"target_type": "Note", "target_iid": 999999}

        assert sd.resolve_mr_iid(event) is None

    def test_a_note_on_something_other_than_a_merge_request_returns_none(self):
        event = {
            "target_type": "Note",
            "target_iid": 999999,
            "note": {"noteable_type": "Issue", "noteable_iid": 42},
        }

        assert sd.resolve_mr_iid(event) is None


class TestFormatEventsWindowFiltering:
    def test_narrows_the_widened_request_back_to_the_exact_window(self):
        """format_events must trim what the +/-1 day widened glab request pulls in."""
        window = sd.compute_window(
            local("2026-09-05 09:00"), since="2026-09-04", until="2026-09-05T09:00"
        )
        events = [
            {
                "action_name": "opened",
                "target_type": "MergeRequest",
                "target_iid": 1,
                "target_title": "in window",
                "created_at": "2026-09-04T10:00:00-05:00",
            },
            {
                "action_name": "opened",
                "target_type": "MergeRequest",
                "target_iid": 2,
                "target_title": "on the extra widened day",
                "created_at": "2026-09-03T10:00:00-05:00",
            },
        ]

        lines = sd.format_events("gitlab.example.com", events, window)

        assert len(lines) == 1
        assert "in window" in lines[0]


class TestLoadIndex:
    def test_returns_empty_when_csess_is_unavailable(self, monkeypatch):
        monkeypatch.setattr(sd, "run_tool", lambda *a, **k: None)

        index, problem = sd.load_index()

        assert index == []
        assert "csess" in problem

    def test_returns_empty_for_blank_output(self, monkeypatch):
        monkeypatch.setattr(sd, "run_tool", lambda *a, **k: "")

        assert sd.load_index() == ([], None)

    def test_returns_empty_for_unparseable_json(self, monkeypatch):
        monkeypatch.setattr(sd, "run_tool", lambda *a, **k: "not json")

        index, problem = sd.load_index()

        assert index == []
        assert "csess" in problem

    def test_returns_a_valid_list_as_is(self, monkeypatch):
        monkeypatch.setattr(sd, "run_tool", lambda *a, **k: '[{"id": "s"}]')

        assert sd.load_index() == ([{"id": "s"}], None)

    def test_returns_empty_for_a_json_object_instead_of_a_list(self, monkeypatch):
        monkeypatch.setattr(sd, "run_tool", lambda *a, **k: '{"id": "s"}')

        assert sd.load_index() == ([], None)


class TestGatherSurfacesIndexProblem:
    def test_a_csess_failure_becomes_a_problem_line_in_the_digest(self, monkeypatch):
        monkeypatch.setattr(sd, "load_index", lambda: ([], "csess: could not be read"))
        monkeypatch.setattr(sd, "discover_repos", lambda s: [])
        monkeypatch.setattr(sd, "mr_activity", lambda r, w: ([], []))

        out = sd.gather(local("2026-09-08 09:00"), None, None)

        assert "csess: could not be read" in out

    def test_a_quiet_day_reports_no_problem(self, monkeypatch):
        monkeypatch.setattr(sd, "load_index", lambda: ([], None))
        monkeypatch.setattr(sd, "discover_repos", lambda s: [])
        monkeypatch.setattr(sd, "mr_activity", lambda r, w: ([], []))

        out = sd.gather(local("2026-09-08 09:00"), None, None)

        assert "## problems" not in out


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

    def test_a_folded_prompt_keeps_its_repeat_marker_when_truncated(self):
        long_poll = "x" * 400
        session = make_session([user(long_poll), user(long_poll), user(long_poll)])
        window = sd.default_window(local("2026-09-08 09:00"))

        out = sd.render(window, [session], [], [], [])

        assert "(repeated 3 times)" in out

    def test_lists_problems_when_a_host_failed(self):
        window = sd.default_window(local("2026-09-08 09:00"))

        out = sd.render(window, [], [], [], ["gitlab.example.com: could not be read"])

        assert "gitlab.example.com" in out


class TestGatherWidening:
    def test_widens_when_the_first_window_is_empty(self, monkeypatch):
        calls = []

        def fake_select(index, window, pin_end=False):
            calls.append(window.start.date())
            return [] if len(calls) == 1 else [make_session([user("work")])]

        monkeypatch.setattr(sd, "load_index", lambda: ([], None))
        monkeypatch.setattr(sd, "select_sessions", fake_select)
        monkeypatch.setattr(sd, "discover_repos", lambda s: [])
        monkeypatch.setattr(sd, "mr_activity", lambda r, w: ([], []))

        out = sd.gather(local("2026-09-08 09:00"), None, None)

        assert len(calls) == 2
        assert "widened" in out

    def test_does_not_widen_when_a_manual_window_is_given(self, monkeypatch):
        calls = []

        def fake_select(index, window, pin_end=False):
            calls.append(window.start.date())
            return [make_session([user("poll the MR") for _ in range(4)])]

        monkeypatch.setattr(sd, "load_index", lambda: ([], None))
        monkeypatch.setattr(sd, "select_sessions", fake_select)
        monkeypatch.setattr(sd, "discover_repos", lambda s: [])
        monkeypatch.setattr(sd, "mr_activity", lambda r, w: ([], []))

        out = sd.gather(local("2026-09-08 09:00"), since="2026-09-01", until=None)

        assert len(calls) == 1
        assert "widened" not in out

    def test_widens_past_a_day_of_only_automated_sessions(self, monkeypatch):
        calls = []

        def fake_select(index, window, pin_end=False):
            calls.append(window.start.date())
            if len(calls) == 1:
                return [make_session([user("poll the MR") for _ in range(4)])]
            return [make_session([user("real work")])]

        monkeypatch.setattr(sd, "load_index", lambda: ([], None))
        monkeypatch.setattr(sd, "select_sessions", fake_select)
        monkeypatch.setattr(sd, "discover_repos", lambda s: [])
        monkeypatch.setattr(sd, "mr_activity", lambda r, w: ([], []))

        out = sd.gather(local("2026-09-08 09:00"), None, None)

        assert len(calls) == 2
        assert "widened" in out

    def test_does_not_widen_when_a_person_worked(self, monkeypatch):
        calls = []

        def fake_select(index, window, pin_end=False):
            calls.append(window.start.date())
            return [make_session([user("real work")])]

        monkeypatch.setattr(sd, "load_index", lambda: ([], None))
        monkeypatch.setattr(sd, "select_sessions", fake_select)
        monkeypatch.setattr(sd, "discover_repos", lambda s: [])
        monkeypatch.setattr(sd, "mr_activity", lambda r, w: ([], []))

        sd.gather(local("2026-09-08 09:00"), None, None)

        assert len(calls) == 1

    def test_todays_work_does_not_suppress_widening(self, monkeypatch):
        calls = []

        def fake_select(index, window, pin_end=False):
            calls.append(window.start.date())
            if len(calls) == 1:
                return [
                    make_session([user("poll the MR", "2026-09-07 08:00") for _ in range(4)]),
                    make_session([user("this morning's real work", "2026-09-08 08:30")]),
                ]
            return [make_session([user("friday's real work", "2026-09-04 10:00")])]

        monkeypatch.setattr(sd, "load_index", lambda: ([], None))
        monkeypatch.setattr(sd, "select_sessions", fake_select)
        monkeypatch.setattr(sd, "discover_repos", lambda s: [])
        monkeypatch.setattr(sd, "mr_activity", lambda r, w: ([], []))

        out = sd.gather(local("2026-09-08 09:00"), None, None)

        assert len(calls) == 2
        assert "widened" in out

    def test_a_session_straddling_midnight_does_not_block_widening(self, monkeypatch):
        calls = []

        def fake_select(index, window, pin_end=False):
            calls.append(window.start.date())
            if len(calls) == 1:
                straddler = make_session(
                    [user("poll the MR", "2026-09-07 08:00") for _ in range(4)]
                    + [user("now fix the parser", "2026-09-08 09:30")]
                )
                return [straddler]
            return [make_session([user("friday's real work", "2026-09-04 10:00")])]

        monkeypatch.setattr(sd, "load_index", lambda: ([], None))
        monkeypatch.setattr(sd, "select_sessions", fake_select)
        monkeypatch.setattr(sd, "discover_repos", lambda s: [])
        monkeypatch.setattr(sd, "mr_activity", lambda r, w: ([], []))

        out = sd.gather(local("2026-09-08 10:00"), None, None)

        assert len(calls) == 2
        assert "widened" in out

    def test_an_assistant_only_earlier_slice_does_not_block_widening(self, monkeypatch):
        calls = []

        def fake_select(index, window, pin_end=False):
            calls.append(window.start.date())
            if len(calls) == 1:
                straddler = make_session(
                    [
                        bot("a" * 300, "2026-09-07 08:00"),
                        user("today's real work", "2026-09-08 08:30"),
                    ]
                )
                return [straddler]
            return [make_session([user("friday's real work", "2026-09-04 10:00")])]

        monkeypatch.setattr(sd, "load_index", lambda: ([], None))
        monkeypatch.setattr(sd, "select_sessions", fake_select)
        monkeypatch.setattr(sd, "discover_repos", lambda s: [])
        monkeypatch.setattr(sd, "mr_activity", lambda r, w: ([], []))

        out = sd.gather(local("2026-09-08 10:00"), None, None)

        assert len(calls) == 2
        assert "widened" in out


class TestMain:
    def test_a_bad_boundary_exits_cleanly(self, monkeypatch, capsys):
        monkeypatch.setattr(sd, "load_index", lambda: ([], None))

        with pytest.raises(SystemExit) as exit_info:
            sd.main(["--since", "bogus"])

        assert "bad boundary" in str(exit_info.value)
