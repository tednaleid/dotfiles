---
name: glab-comment
description: Post line-anchored review comments to a GitLab merge request. Use ONLY when Ted explicitly asks to post a specific comment or set of comments. Never invoke on your own initiative; default to drafting the comment and showing it instead. Handles diff-ref lookup, anchor validation, duplicate detection, and the From Claude attribution marker.
allowed-tools: Bash(glab-comment:*)
---

# glab-comment

Posts comments to a GitLab MR under Ted's account. GitLab only.

## Before you post

- Ted must have asked for this specific post. Drafting is the default; posting is the exception.
- One ask authorizes one post. "Post 4, 5, and 12" does not authorize posting 13 later in the session. Ask again.
- Never resolve, approve, merge, or close. This tool posts comments and nothing else.

If the ask is ambiguous, write the draft and show it. That is always the safe move.

## Usage

```sh
glab-comment api/app/omni_data.py:141 --body-file draft.md   # one comment, MR from branch
glab-comment --mr 190 api/app/omni_data.py:141 --body-file - # explicit MR, body on stdin
glab-comment --mr 190 --manifest findings.json               # batch, the review-pass case
glab-comment --mr 190 --general --body-file summary.md       # unpositioned MR note
glab-comment --mr 190 --manifest findings.json --dry-run     # print payloads, post nothing
```

Manifest is a JSON array of `{"file": ..., "line": ..., "body_file": ...}`, or `body` for
inline text. Run `--dry-run` first on any batch.

`FILE:LINE` is a line number in the **new** file. A comment can only land on a line the MR
diff touches. If the line is not in the diff the script refuses, names the closest
addressable lines, and posts nothing. Re-anchor to a line the MR actually introduced; that
is usually the better anchor anyway.

## Writing the comment

One finding per comment. Two findings, two comments.

The marker costs a line before you start. Spend the rest carefully.

Avoid:

> I noticed that in this function the error handling might potentially be an issue. It
> seems like the exception tuple may not cover all cases, which could possibly lead to
> unexpected behavior. You might want to consider whether this is the intended behavior.

Better:

> `_round_or_none` catches only `TypeError`; a `Decimal` string here raises
> `InvalidOperation` and 500s the endpoint.

Avoid:

> This adds a new tab showing temporal validation results, which is good, but there is no
> test coverage for it.

Better:

> No test asserts the tab renders. This MR exists because that tab silently disappeared.

- Lead with the claim. Cut "I noticed", "It seems", "You might want to consider".
- Name the failure as input to wrong result, not "could be an issue".
- Do not summarize what the code does. The author wrote it.
- Suggest a fix only if it fits on one line. Otherwise state the problem.
- Unsure? Ask. "Is the empty case intentional?" beats "this is wrong."

## What it does for you

Every body gets the `> **From Claude:**` marker prepended. The comment posts under Ted's
account, so that label is the only thing separating your voice from his.

It also re-reads the MR's diff refs on every run, validates each anchor before posting any
of them, and refuses a line that already carries a From Claude comment. A POST that looks
like it failed may have landed, so never retry by hand; re-run the script and let the
duplicate check decide.

## Limits

- Anchors target new-file lines. Commenting on a removed line is not exposed.
- No multi-line (`line_range`) comments, no replies into an existing thread.
- No editing or deleting. Fix a bad comment in the GitLab UI.
- A raw `glab api ... /discussions -X POST` is blocked by a veer rule. That is deliberate:
  it skips the marker, the anchor check, and the duplicate check.
