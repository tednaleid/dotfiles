# ABOUTME: unit tests for the pure logic in the glab-comment script
# ABOUTME: network calls are out of scope; everything here runs offline

import importlib.machinery
import types
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "glab-comment"


def _load():
    """Import the extensionless script as a module."""
    loader = importlib.machinery.SourceFileLoader("glab_comment", str(SCRIPT))
    module = types.ModuleType(loader.name)
    loader.exec_module(module)
    return module


gc = _load()


class TestParseDiffLines:
    def test_added_line_has_new_line_only(self):
        diff = "@@ -0,0 +1 @@\n+first\n"
        assert gc.parse_diff_lines(diff) == [
            {"kind": "added", "old_line": None, "new_line": 1}
        ]

    def test_removed_line_has_old_line_only(self):
        diff = "@@ -3 +2,0 @@\n-gone\n"
        assert gc.parse_diff_lines(diff) == [
            {"kind": "removed", "old_line": 3, "new_line": None}
        ]

    def test_context_line_carries_both_numbers(self):
        diff = "@@ -5,2 +7,2 @@\n ctx\n+added\n"
        assert gc.parse_diff_lines(diff) == [
            {"kind": "context", "old_line": 5, "new_line": 7},
            {"kind": "added", "old_line": None, "new_line": 8},
        ]

    def test_second_hunk_resets_both_counters(self):
        diff = "@@ -1,1 +1,1 @@\n+one\n@@ -40,1 +50,1 @@\n+fifty\n"
        assert gc.parse_diff_lines(diff)[-1] == {
            "kind": "added",
            "old_line": None,
            "new_line": 50,
        }

    def test_ignores_no_newline_marker(self):
        diff = "@@ -1 +1 @@\n+text\n\\ No newline at end of file\n"
        assert gc.parse_diff_lines(diff) == [
            {"kind": "added", "old_line": None, "new_line": 1}
        ]


SAMPLE = gc.parse_diff_lines("@@ -5,3 +5,4 @@\n ctx\n-dropped\n+one\n+two\n")
# new file: 5 context, 6 added, 7 added.  old file: 5 context, 6 removed.


class TestFindAnchor:
    def test_added_line_anchors_on_new_line_alone(self):
        assert gc.find_anchor(SAMPLE, 6) == {"new_line": 6}

    def test_context_line_anchors_on_both_numbers(self):
        assert gc.find_anchor(SAMPLE, 5) == {"old_line": 5, "new_line": 5}

    def test_line_outside_the_diff_is_not_addressable(self):
        assert gc.find_anchor(SAMPLE, 99) is None

    def test_removed_line_anchors_on_old_line_alone(self):
        assert gc.find_anchor(SAMPLE, 6, side="old") == {"old_line": 6}


class TestNearestAddressable:
    def test_suggests_closest_lines_first(self):
        assert gc.nearest_addressable(SAMPLE, 9, count=2) == [7, 6]

    def test_never_suggests_the_requested_line(self):
        assert 6 not in gc.nearest_addressable(SAMPLE, 6)


class TestEnsureMarker:
    def test_prepends_the_marker_when_absent(self):
        assert gc.ensure_marker("Body text.").startswith(gc.MARKER)

    def test_keeps_the_body_below_a_blank_line(self):
        assert gc.ensure_marker("Body text.") == f"{gc.MARKER}\n\nBody text."

    def test_does_not_double_an_existing_marker(self):
        once = gc.ensure_marker("Body text.")
        assert gc.ensure_marker(once) == once

    def test_recognises_a_marker_after_leading_blank_lines(self):
        drafted = f"\n\n{gc.MARKER}\n\nBody text."
        assert gc.ensure_marker(drafted).count("From Claude") == 1

    def test_marker_names_claude_as_the_author(self):
        assert "From Claude" in gc.MARKER

    def test_marker_is_the_label_and_nothing_else(self):
        assert gc.MARKER == "> **From Claude:**"


SHAS = {"base_sha": "aaa", "start_sha": "bbb", "head_sha": "ccc"}


class TestBuildPayload:
    def test_carries_the_shas_and_paths(self):
        payload = gc.build_payload("text", SHAS, "api/app.py", {"new_line": 12})
        assert payload["position"] == {
            "position_type": "text",
            "base_sha": "aaa",
            "start_sha": "bbb",
            "head_sha": "ccc",
            "new_path": "api/app.py",
            "old_path": "api/app.py",
            "new_line": 12,
        }

    def test_body_is_marked_before_it_goes_out(self):
        payload = gc.build_payload("text", SHAS, "api/app.py", {"new_line": 12})
        assert payload["body"].startswith(gc.MARKER)

    def test_context_anchor_keeps_both_line_numbers(self):
        payload = gc.build_payload(
            "text", SHAS, "api/app.py", {"old_line": 9, "new_line": 12}
        )
        assert payload["position"]["old_line"] == 9
        assert payload["position"]["new_line"] == 12

    def test_added_file_has_no_old_path(self):
        payload = gc.build_payload(
            "text", SHAS, "api/new.py", {"new_line": 1}, old_path=None
        )
        assert "old_path" not in payload["position"]

    def test_renamed_file_keeps_both_paths(self):
        payload = gc.build_payload(
            "text", SHAS, "api/new.py", {"new_line": 1}, old_path="api/old.py"
        )
        assert payload["position"]["old_path"] == "api/old.py"


def _discussion(did, body, path="api/app.py", line=12, system=False, position=True):
    note = {"system": system, "body": body}
    if position:
        note["position"] = {"new_path": path, "new_line": line}
    return {"id": did, "notes": [note]}


class TestFindDuplicates:
    def test_finds_a_marked_note_at_the_same_anchor(self):
        existing = [_discussion("d1", f"{gc.MARKER}\n\nSomething.")]
        assert gc.find_duplicates(existing, "api/app.py", 12) == ["d1"]

    def test_ignores_a_marked_note_at_another_line(self):
        existing = [_discussion("d1", f"{gc.MARKER}\n\nSomething.", line=40)]
        assert gc.find_duplicates(existing, "api/app.py", 12) == []

    def test_ignores_a_marked_note_in_another_file(self):
        existing = [_discussion("d1", f"{gc.MARKER}\n\nx", path="api/other.py")]
        assert gc.find_duplicates(existing, "api/app.py", 12) == []

    def test_ignores_an_unmarked_human_note_at_the_same_anchor(self):
        existing = [_discussion("d1", "Ryan wrote this by hand.")]
        assert gc.find_duplicates(existing, "api/app.py", 12) == []

    def test_ignores_gitlab_system_notes(self):
        existing = [_discussion("d1", f"{gc.MARKER}\n\nx", system=True)]
        assert gc.find_duplicates(existing, "api/app.py", 12) == []

    def test_ignores_unpositioned_general_notes(self):
        existing = [_discussion("d1", f"{gc.MARKER}\n\nx", position=False)]
        assert gc.find_duplicates(existing, "api/app.py", 12) == []

    def test_tolerates_a_discussion_with_no_notes(self):
        assert gc.find_duplicates([{"id": "d1", "notes": []}], "api/app.py", 12) == []
