# ABOUTME: unit tests for the pure logic in the csess session browser
# ABOUTME: transcripts are synthesised on disk; no real Claude Code sessions are read

import importlib.machinery
import json
import os
import subprocess
import types
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parent.parent / "csess"


def _load():
    """Import the extensionless script as a module."""
    loader = importlib.machinery.SourceFileLoader("csess", str(SCRIPT))
    module = types.ModuleType(loader.name)
    module.__file__ = str(SCRIPT)
    loader.exec_module(module)
    return module


cs = _load()


def write_transcript(root, project_slug, session_id, records):
    """Write records as a .jsonl transcript and return its path."""
    directory = root / project_slug
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / f"{session_id}.jsonl"
    path.write_text("".join(json.dumps(r) + "\n" for r in records))
    return path


def session(session_id, cwd, mtime=0):
    return cs.Session(id=session_id, path=Path(f"/t/{session_id}.jsonl"), cwd=cwd, mtime=mtime)


class TestParseSession:
    def test_last_away_summary_wins(self, tmp_path):
        path = write_transcript(
            tmp_path,
            "p",
            "aaaaaaaa-1111-2222-3333-444444444444",
            [
                {"type": "system", "subtype": "away_summary", "content": "first recap"},
                {"type": "user", "cwd": "/Users/x/code/proj", "gitBranch": "main"},
                {"type": "system", "subtype": "away_summary", "content": "second recap"},
            ],
        )

        assert cs.parse_session(path).recap == "second recap"

    def test_recap_drops_the_disable_hint_claude_code_appends(self, tmp_path):
        path = write_transcript(
            tmp_path,
            "p",
            "s",
            [
                {
                    "type": "system",
                    "subtype": "away_summary",
                    "content": "Fixed the pagination bug. (disable recaps in /config)",
                }
            ],
        )

        assert cs.parse_session(path).recap == "Fixed the pagination bug."

    def test_extracts_branch_last_prompt_and_message_count(self, tmp_path):
        path = write_transcript(
            tmp_path,
            "p",
            "s",
            [
                {"type": "user", "cwd": "/Users/x/code/proj", "gitBranch": "main"},
                {"type": "assistant"},
                {"type": "user", "cwd": "/Users/x/code/proj", "gitBranch": "feature/x"},
                {"type": "assistant"},
                {"type": "last-prompt", "lastPrompt": "commit and push"},
            ],
        )

        parsed = cs.parse_session(path)

        assert parsed.branch == "feature/x"
        assert parsed.last_prompt == "commit and push"
        assert parsed.message_count == 4

    def test_damaged_lines_do_not_lose_the_rest_of_the_transcript(self, tmp_path):
        path = tmp_path / "p" / "s.jsonl"
        path.parent.mkdir()
        path.write_text(
            "\n".join(
                [
                    json.dumps({"type": "ai-title", "aiTitle": "kept"}),
                    "",
                    "{not json at all",
                    json.dumps({"type": "user", "cwd": "/Users/x/code/proj"})[:-4],
                    json.dumps(
                        {"type": "system", "subtype": "away_summary", "content": "also kept"}
                    ),
                ]
            )
            + "\n"
        )

        parsed = cs.parse_session(path)

        assert parsed.ai_title == "kept"
        assert parsed.recap == "also kept"


class TestTitleAndSummary:
    @pytest.mark.parametrize(
        "records,expected",
        [
            pytest.param(
                [
                    {"type": "ai-title", "aiTitle": "generated"},
                    {"type": "custom-title", "customTitle": "named"},
                ],
                "named",
                id="custom-title beats ai-title",
            ),
            pytest.param(
                [{"type": "ai-title", "aiTitle": "generated"}],
                "generated",
                id="ai-title when unnamed",
            ),
            pytest.param([], "aaaaaaaa", id="short id when untitled"),
            pytest.param(
                [
                    {"type": "custom-title", "customTitle": "first"},
                    {"type": "custom-title", "customTitle": "renamed"},
                ],
                "renamed",
                id="last rename wins",
            ),
        ],
    )
    def test_title_precedence(self, tmp_path, records, expected):
        path = write_transcript(
            tmp_path, "p", "aaaaaaaa-1111-2222-3333-444444444444", records
        )

        assert cs.parse_session(path).title == expected

    @pytest.mark.parametrize(
        "records,expected",
        [
            pytest.param(
                [
                    {"type": "last-prompt", "lastPrompt": "the prompt"},
                    {"type": "system", "subtype": "away_summary", "content": "the recap"},
                ],
                "the recap",
                id="recap beats last prompt",
            ),
            pytest.param(
                [{"type": "last-prompt", "lastPrompt": "the prompt"}],
                "the prompt",
                id="last prompt when no recap",
            ),
            pytest.param([], "", id="empty when neither"),
        ],
    )
    def test_summary_precedence(self, tmp_path, records, expected):
        path = write_transcript(tmp_path, "p", "s", records)

        assert cs.parse_session(path).summary == expected

    def test_one_line_collapses_whitespace(self):
        assert cs.one_line("first line\n\n  second   line\t") == "first line second line"


class TestProjectGrouping:
    @pytest.mark.parametrize(
        "cwd,root,worktree",
        [
            pytest.param("/Users/x/code/proj", "/Users/x/code/proj", None, id="main checkout"),
            pytest.param(
                "/Users/x/code/proj/.claude/worktrees/FORGE-310",
                "/Users/x/code/proj",
                "FORGE-310",
                id="worktree",
            ),
            pytest.param(
                "/Users/x/code/proj/.claude/worktrees/FORGE-310/packages/api",
                "/Users/x/code/proj",
                "FORGE-310",
                id="nested inside worktree",
            ),
            pytest.param("/", "/", None, id="filesystem root"),
        ],
    )
    def test_split_worktree(self, cwd, root, worktree):
        assert cs.split_worktree(cwd) == (root, worktree)

    def test_moved_repo_and_its_worktree_share_one_project_key(self, tmp_path):
        paths = [
            write_transcript(tmp_path, "a", "s1", [{"type": "user", "cwd": "/Users/x/code/proj"}]),
            write_transcript(
                tmp_path, "b", "s2", [{"type": "user", "cwd": "/Users/x/Documents/workspace/proj"}]
            ),
            write_transcript(
                tmp_path,
                "c",
                "s3",
                [{"type": "user", "cwd": "/Users/x/code/proj/.claude/worktrees/FORGE-310"}],
            ),
        ]

        assert {cs.parse_session(p).project_key for p in paths} == {"proj"}

    def test_session_without_cwd_falls_back_to_its_project_directory(self, tmp_path):
        path = write_transcript(
            tmp_path, "-Users-x-code-proj", "s", [{"type": "ai-title", "aiTitle": "t"}]
        )

        parsed = cs.parse_session(path)

        assert parsed.cwd is None
        assert parsed.project_key == "-Users-x-code-proj"


class TestCurrentProjectKey:
    def test_uses_the_git_toplevel(self, tmp_path):
        repo = tmp_path / "myrepo"
        (repo / "nested" / "deep").mkdir(parents=True)
        subprocess.run(["git", "init", "-q"], cwd=repo, check=True)

        assert cs.current_project_key(repo / "nested" / "deep") == "myrepo"

    def test_folds_a_worktree_into_its_parent(self, tmp_path):
        repo = tmp_path / "myrepo"
        repo.mkdir()
        env = {
            **os.environ,
            "GIT_AUTHOR_NAME": "t",
            "GIT_AUTHOR_EMAIL": "t@t",
            "GIT_COMMITTER_NAME": "t",
            "GIT_COMMITTER_EMAIL": "t@t",
        }
        subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
        subprocess.run(
            ["git", "commit", "-q", "--allow-empty", "-m", "init"], cwd=repo, check=True, env=env
        )
        worktree = repo / ".claude" / "worktrees" / "FORGE-1"
        subprocess.run(
            ["git", "worktree", "add", "-q", str(worktree)], cwd=repo, check=True, env=env
        )

        assert cs.current_project_key(worktree) == "myrepo"

    def test_outside_a_repo_is_the_directory_name(self, tmp_path):
        plain = tmp_path / "just-a-dir"
        plain.mkdir()

        assert cs.current_project_key(plain) == "just-a-dir"


class TestFiltering:
    @pytest.mark.parametrize(
        "text,seconds",
        [
            ("12h", 43_200),
            ("14d", 1_209_600),
            ("2w", 1_209_600),
            ("3m", 7_776_000),
            ("1y", 31_536_000),
        ],
    )
    def test_parse_duration(self, text, seconds):
        assert cs.parse_duration(text) == seconds

    @pytest.mark.parametrize("text", ["", "2", "d", "2x", "-3d", "two weeks"])
    def test_parse_duration_rejects_junk(self, text):
        with pytest.raises(ValueError):
            cs.parse_duration(text)

    def test_by_project_includes_worktrees_and_relocated_checkouts(self):
        sessions = [
            session("main", "/Users/x/code/proj"),
            session("tree", "/Users/x/code/proj/.claude/worktrees/FORGE-1"),
            session("moved", "/Users/x/Documents/workspace/proj"),
            session("other", "/Users/x/code/unrelated"),
        ]

        kept = cs.filter_sessions(sessions, project="proj")

        assert [s.id for s in kept] == ["main", "tree", "moved"]

    def test_by_age_keeps_only_recent_sessions(self):
        sessions = [session("recent", "/c", 900), session("stale", "/c", 100)]

        kept = cs.filter_sessions(sessions, since=500, now=1000)

        assert [s.id for s in kept] == ["recent"]


class TestGrep:
    def test_matches_anywhere_in_the_transcript(self, tmp_path):
        write_transcript(
            tmp_path,
            "p",
            "hit",
            [
                {"type": "user", "cwd": "/c/p"},
                {"type": "assistant", "message": {"content": "the PAGINATION fix"}},
            ],
        )
        write_transcript(tmp_path, "p", "miss", [{"type": "user", "cwd": "/c/p"}])
        sessions = cs.index_sessions(tmp_path)

        assert [s.id for s in cs.grep_sessions(sessions, "pagination")] == ["hit"]

    def test_accepts_a_regex(self, tmp_path):
        write_transcript(
            tmp_path,
            "p",
            "hit",
            [{"type": "assistant", "message": {"content": "error code 4711 raised"}}],
        )
        sessions = cs.index_sessions(tmp_path)

        assert [s.id for s in cs.grep_sessions(sessions, r"code \d{4}")] == ["hit"]

    def test_reports_a_bad_pattern_instead_of_crashing(self):
        with pytest.raises(ValueError):
            cs.grep_sessions([], "unclosed(")


class TestIndex:
    def test_returns_newest_first_and_skips_subagent_transcripts(self, tmp_path):
        old = write_transcript(tmp_path, "proj-a", "old", [{"type": "user", "cwd": "/c/a"}])
        new = write_transcript(tmp_path, "proj-b", "new", [{"type": "user", "cwd": "/c/b"}])
        nested = write_transcript(tmp_path / "proj-a", "subagents", "child", [{"type": "user"}])
        os.utime(old, (1_000_000, 1_000_000))
        os.utime(new, (2_000_000, 2_000_000))
        os.utime(nested, (3_000_000, 3_000_000))

        assert [s.id for s in cs.index_sessions(tmp_path)] == ["new", "old"]

    def test_records_modification_time(self, tmp_path):
        path = write_transcript(tmp_path, "proj", "s", [{"type": "user", "cwd": "/c"}])
        os.utime(path, (1_500_000, 1_500_000))

        assert cs.index_sessions(tmp_path)[0].mtime == 1_500_000

    def test_of_a_missing_root_is_empty(self, tmp_path):
        assert cs.index_sessions(tmp_path / "nope") == []

    def test_find_transcript_locates_a_session_by_id(self, tmp_path):
        wanted = write_transcript(tmp_path, "proj-b", "wanted", [{"type": "user"}])
        write_transcript(tmp_path, "proj-a", "other", [{"type": "user"}])

        assert cs.find_transcript(tmp_path, "wanted") == wanted

    def test_find_transcript_returns_none_for_an_unknown_id(self, tmp_path):
        assert cs.find_transcript(tmp_path, "nope") is None

    def test_find_transcript_ignores_path_separators_in_the_id(self, tmp_path):
        write_transcript(tmp_path, "proj", "real", [{"type": "user"}])

        assert cs.find_transcript(tmp_path, "../proj/real") is None

    def test_projects_root_defaults_under_the_home_claude_directory(self, monkeypatch):
        monkeypatch.delenv("CLAUDE_CONFIG_DIR", raising=False)

        assert cs.projects_root() == Path.home() / ".claude" / "projects"

    def test_projects_root_honours_the_config_dir_override(self, monkeypatch, tmp_path):
        monkeypatch.setenv("CLAUDE_CONFIG_DIR", str(tmp_path))

        assert cs.projects_root() == tmp_path / "projects"


class TestIndexCache:
    @staticmethod
    def _count_parses(monkeypatch):
        calls = []
        real = cs.parse_session

        def counted(path):
            calls.append(path)
            return real(path)

        monkeypatch.setattr(cs, "parse_session", counted)
        return calls

    def test_second_index_reuses_the_cache_instead_of_reparsing(self, tmp_path, monkeypatch):
        write_transcript(tmp_path, "p", "s", [{"type": "user", "cwd": "/c/p"}])
        cache = tmp_path / "cache.json"
        calls = self._count_parses(monkeypatch)

        first = cs.index_sessions(tmp_path, cache_file=cache)
        second = cs.index_sessions(tmp_path, cache_file=cache)

        assert len(calls) == 1
        assert [s.cwd for s in second] == [s.cwd for s in first]

    def test_a_changed_transcript_is_reparsed(self, tmp_path, monkeypatch):
        path = write_transcript(tmp_path, "p", "s", [{"type": "user", "cwd": "/c/p"}])
        cache = tmp_path / "cache.json"
        calls = self._count_parses(monkeypatch)
        cs.index_sessions(tmp_path, cache_file=cache)

        write_transcript(tmp_path, "p", "s", [{"type": "user", "cwd": "/c/moved"}])
        os.utime(path, (9_000_000, 9_000_000))
        reindexed = cs.index_sessions(tmp_path, cache_file=cache)

        assert len(calls) == 2
        assert reindexed[0].cwd == "/c/moved"

    def test_round_trips_every_displayed_field(self, tmp_path):
        write_transcript(
            tmp_path,
            "p",
            "s",
            [
                {"type": "user", "cwd": "/c/p", "gitBranch": "main"},
                {"type": "custom-title", "customTitle": "named"},
                {"type": "ai-title", "aiTitle": "generated"},
                {"type": "last-prompt", "lastPrompt": "do the thing"},
                {"type": "system", "subtype": "away_summary", "content": "the recap"},
            ],
        )
        cache = tmp_path / "cache.json"

        fresh = cs.index_sessions(tmp_path, cache_file=cache)[0]
        cached = cs.index_sessions(tmp_path, cache_file=cache)[0]

        for field in (
            "id", "cwd", "branch", "recap", "custom_title", "ai_title",
            "last_prompt", "message_count", "mtime", "path",
        ):
            assert getattr(cached, field) == getattr(fresh, field), field

    def test_a_corrupt_cache_is_ignored_rather_than_fatal(self, tmp_path):
        write_transcript(tmp_path, "p", "s", [{"type": "user", "cwd": "/c/p"}])
        cache = tmp_path / "cache.json"
        cache.write_text("this is not json")

        assert [s.cwd for s in cs.index_sessions(tmp_path, cache_file=cache)] == ["/c/p"]

    def test_forgets_transcripts_that_disappear(self, tmp_path):
        path = write_transcript(tmp_path, "p", "gone", [{"type": "user", "cwd": "/c/p"}])
        cache = tmp_path / "cache.json"
        cs.index_sessions(tmp_path, cache_file=cache)

        path.unlink()
        cs.index_sessions(tmp_path, cache_file=cache)

        assert "gone" not in cache.read_text()


class TestDisplay:
    @pytest.mark.parametrize(
        "seconds,expected",
        [
            (30, "now"),
            (90, "1m"),
            (7200, "2h"),
            (172_800, "2d"),
            (1_209_600, "2w"),
            (63_072_000, "2y"),
        ],
    )
    def test_format_age(self, seconds, expected):
        assert cs.format_age(seconds) == expected

    def test_row_leads_with_the_id_so_fzf_can_return_it(self):
        one = cs.Session(
            id="abc-123",
            path=Path("/t/abc-123.jsonl"),
            cwd="/Users/x/code/proj",
            branch="main",
            ai_title="Fix the thing",
            recap="Did the thing.",
            mtime=1000,
        )

        fields = cs.format_row(one, now=1000).split("\t")

        assert fields[0] == "abc-123"
        assert fields[1:] == ["now", "proj", "main", "Fix the thing", "Did the thing."]

    def test_row_names_the_worktree_alongside_its_project(self):
        one = session("s", "/Users/x/code/proj/.claude/worktrees/FORGE-1")

        assert cs.format_row(one, now=0).split("\t")[2] == "proj/FORGE-1"

    def test_row_survives_tabs_and_newlines_in_a_recap(self):
        one = cs.Session(
            id="s", path=Path("/t/s.jsonl"), cwd="/c/p", recap="line one\n\tline two", mtime=0
        )

        assert cs.format_row(one, now=0).split("\t")[5] == "line one line two"

    def test_preview_shows_the_origin_directory_and_the_full_recap(self):
        one = cs.Session(
            id="s",
            path=Path("/t/s.jsonl"),
            cwd="/Users/x/code/proj",
            branch="main",
            custom_title="named",
            recap="First paragraph.\n\nSecond paragraph.",
            mtime=0,
        )

        text = cs.render_preview(one, cwd="/Users/x/code/other", now=0)

        assert "named" in text
        assert "/Users/x/code/proj" in text
        assert "First paragraph." in text
        assert "Second paragraph." in text

    def test_preview_shows_a_relative_origin_when_it_sits_under_the_current_directory(self):
        one = session("s", "/Users/x/code/proj/.claude/worktrees/FORGE-1")

        text = cs.render_preview(one, cwd="/Users/x/code/proj", now=0)

        assert "./.claude/worktrees/FORGE-1" in text

    def test_preview_handles_a_session_with_no_recorded_directory(self):
        text = cs.render_preview(session("s", None), cwd="/Users/x/code/proj", now=0)

        assert "unknown" in text.lower()


class TestTranscript:
    def test_renders_both_string_and_block_message_shapes(self, tmp_path):
        path = write_transcript(
            tmp_path,
            "p",
            "s",
            [
                {"type": "user", "message": {"content": "plain string message"}},
                {
                    "type": "assistant",
                    "message": {
                        "content": [
                            {"type": "thinking", "thinking": "hidden reasoning"},
                            {"type": "text", "text": "block message"},
                        ]
                    },
                },
            ],
        )

        text = cs.render_transcript(cs.parse_session(path))

        assert "plain string message" in text
        assert "block message" in text
        assert "hidden reasoning" not in text

    def test_labels_who_said_what(self, tmp_path):
        path = write_transcript(
            tmp_path,
            "p",
            "s",
            [
                {"type": "user", "message": {"content": "a question"}},
                {"type": "assistant", "message": {"content": "an answer"}},
            ],
        )

        rendered = cs.render_transcript(cs.parse_session(path))
        lines = [line for line in rendered.splitlines() if line.strip()]

        assert lines[0].startswith("user")
        assert "assistant" in rendered

    def test_skips_records_with_no_displayable_text(self, tmp_path):
        path = write_transcript(
            tmp_path,
            "p",
            "s",
            [
                {"type": "user", "message": {"content": [{"type": "tool_result", "content": "x"}]}},
                {"type": "assistant", "message": {"content": "kept"}},
            ],
        )

        assert cs.render_transcript(cs.parse_session(path)).count("user") == 0


class TestPicker:
    def test_aborting_the_picker_is_not_an_error(self, monkeypatch):
        def abort(*_args, **_kwargs):
            raise KeyboardInterrupt

        monkeypatch.setattr(cs.iterfzf, "iterfzf", abort)

        assert cs.pick([session("s", "/c/p")]) is None

    def test_selecting_nothing_is_not_an_error(self, monkeypatch):
        monkeypatch.setattr(cs.iterfzf, "iterfzf", lambda *_a, **_k: None)

        assert cs.pick([session("s", "/c/p")]) is None

    def test_returns_the_session_matching_the_chosen_row(self, monkeypatch):
        wanted = session("wanted", "/c/p")
        rows = []

        def choose(candidates, *_a, **_k):
            rows.extend(candidates)
            return rows[1]

        monkeypatch.setattr(cs.iterfzf, "iterfzf", choose)

        assert cs.pick([session("other", "/c/p"), wanted]) is wanted


class TestResume:
    def test_argv_is_plain_when_already_in_the_origin_directory(self):
        one = session("abc123", "/Users/x/code/proj")

        assert cs.resume_argv(one, "/Users/x/code/proj") == ["claude", "--resume", "abc123"]

    def test_argv_orients_claude_when_resumed_elsewhere(self):
        one = session("abc123", "/Users/x/code/proj")

        argv = cs.resume_argv(one, "/Users/x/code/other")

        assert argv[:3] == ["claude", "--resume", "abc123"]
        assert argv[3] == "--append-system-prompt"
        assert "/Users/x/code/proj" in argv[4]
        assert "/Users/x/code/other" in argv[4]

    def test_argv_is_plain_when_the_origin_is_unknown(self):
        one = session("abc123", None)

        assert cs.resume_argv(one, "/Users/x/code/other") == ["claude", "--resume", "abc123"]
