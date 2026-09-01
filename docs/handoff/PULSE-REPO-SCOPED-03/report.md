# PULSE-REPO-SCOPED-03 — repo-scoped status board (dispatch-82bb6960)

Founder report 2026-08-31: in `~/Projects/platform` the beat showed another repo's data —
`08:42 · посты н/д · комменты н/д · реплаи н/д` and `persona-engine/dispatch-… foreign repo
persona-engine; pid=alive`. The beat itself is wanted; only the foreign data is not.

Scoped design (authoritative): **status renderer only.** `leadv2-broad-status.sh` is the single
changed production file; the collector and its `LEADV2_LANES_ALL_REPOS=1` pin are deliberately
untouched — that pin is what keeps a dispatching session able to see a lane whose registry row
lives in another repo; the renderer now scopes what that pin feeds through.

## Change 1 — product line is repo-owned

`leadv2-broad-status.sh` (embedded render.py, rule-1 section): the `посты/комменты/реплаи` bits
now render **only when the repo actually published at least one of the six candidate product
keys** (`posts_today/posts_floor/comments_today/comments_floor/replies_today/replies_floor`).

Key used and why (no new config file): the override tree's natural home already existed — each
repo's own `.claude/leadv2-overrides/status-collector-facts.sh` defines `collect_repo_facts()`,
which the collector lifts verbatim into the snapshot's `repo_facts` section; the renderer's
documented candidate-key contract (comment above `_metric`) already reads exactly those keys.
"Declares product metrics" = at least one of the six keys present in that object. A repo that
declares nothing (no facts hook, or one publishing other facts) gets **no product line at all**
— line 1 is just the time (plus `окно` if declared). A repo that declares some-but-not-all
keeps the line with `н/д` for the missing ones — the rule-1 "never 0" contract is scoped, not
removed. persona-engine publishes all six plus `ny_window` → byte-identical line.

## Change 2 — foreign lanes render only for the session that owns them

`leadv2-broad-status.sh` (embedded render.py, right after the malformed-row filter, before
dedup/digest/delta/cap accounting): a row carrying `repo=<slug>` (own-repo rows never do)
survives **only when `<PROJECT_ROOT>/docs/leadv2/tasks/<task_id>/` exists** — the dispatch
journal directory is the ownership mark, and this is exactly the case the collector pin was
added to rescue. Every other foreign row is dropped before any accounting, so no
hidden-count or closed-lane line ever reports a lane this repo never owned; a one-line stderr
note records the drop count (diagnostics only, never the board). `repo_read_error` rows keep
their degraded-line treatment (read-failure diagnostics, not lanes). The collector pin is
NOT set to 0 anywhere.

## Test evidence (`test-status-repo-scoped.sh`, hermetic fixture repo + stubbed collector)

- C1 (control + assertion): no declared metrics ⇒ no product line, 0 `посты|комменты|реплаи`
  substrings, own row still renders; C2: declared ⇒ line exactly as today; C2b: partial
  declaration keeps `н/д`; C3: foreign lane without a dispatch record ⇒ absent; C5: own-repo
  lane ⇒ present; C4: foreign lane WITH a dispatch record ⇒ present (pin-rescue regression
  guard).
- GREEN: `PASS=7 FAIL=0`, exit 0.
- RED control 1 (mutation inside the production body: filter condition → `True`): C3 FAIL
  (`foreign lane … leaked: | otherrepo/dispatch-beef0001 |`), exit 1. Reverted.
- RED control 2 (mutation: product gate → `if True`): C1 FAIL, reproducing the founder's exact
  line `17:59 · посты н/д · комменты н/д · реплаи н/д`, exit 1. Reverted; GREEN re-verified.

## Existing suites updated (fixture alignment, contracts unchanged)

Three pre-existing suites exercise the renderer with foreign rows that are the
"dispatched-from-here" case under the new scoping; their fixtures now seed the dispatch
records (`<repo>/docs/leadv2/tasks/<task_id>/`) the production code checks, all inside their
scratch repos:
- `test-broad-status-foreign-lanes.sh` — R1's foreign lane (S1–S4 are snapshot-layer, untouched).
- `test-broad-status-lanes-blind.sh` — cap/surge/mix/round-robin foreign rows.
- `test-broad-status-row-identity.sh` — identity/dedup/digest-key foreign rows.
- `tests/run-all.sh` — one `EXTRA_SUITE_MAP` row: `leadv2-broad-status.sh:…/test-status-repo-scoped.sh`.
  Only one row because only one production script changed (the scoped design removed the
  collector from scope; the original brief's "both touched scripts" no longer applies).

## Census check (PREPASS-MECHANISM-CLOSURE-01)

The scoped design's census held: leaks verified at the cited lines; no unlisted renderer of
the product line exists (`founder-status-full.md` carries no product line); every existing
suite that asserts product words (`test-pulse-readable-rendering.sh`) is a declaring-repo
fixture (partial declaration) and still passes under the gate. Nothing falsified.

## Falsification set

`bash -n` (bash 5 + `/bin/bash` 3.2) on every changed shell file: OK. No Python files changed
(the edit is inside the embedded heredoc, covered by `bash -n` and by the suite exercising the
render). `tests/run-all.sh --scope changed`: see final report message for the raw tail.
