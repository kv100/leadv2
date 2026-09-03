# ANTI-SILENCE-ONE-MECHANISM-01 — one beat writer, one stamp, and a fallback that speaks

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ANTI-SILENCE-ONE-MECHANISM-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-broad-status.sh,plugins/leadv2/hooks/leadv2-single-lead-beat.sh,plugins/leadv2/hooks/leadv2-task-anchor.sh,plugins/leadv2/scripts/tests/test-beat-stamp-agreement.sh,tests/run-all.sh,docs/handoff/ANTI-SILENCE-ONE-MECHANISM-01/

Main is `95ed6f310` in `~/Projects/leadv2`. Branch from it. **This is the highest-priority lane.**

## The report

The founder, in a parallel session of persona-engine: "снова есть молчание, нет битов, пульсов,
апдейтов. Нужен 1 рабочий механизм." This is a repeat of a disease that has been "fixed" before.

## What I established, live, before writing this

`docs/leadv2/founder-status.md` in persona-engine had **mtime 11:51** and **line 1 stamped
`2026-08-31T08:50:15Z`**. Three hours apart. Earlier the same morning I caught the other
direction: the file said `08:50:54Z` while the ready line said `at=08:50:15Z`.

That matters because of what the relay contract instructs the lead to do
(`leadv2-task-anchor.sh:229` and the ready line's own text): *compare the ready-line's `at=`
with the stamp leading line 1 — if they differ, publish that fact, not the file.*

So the loop is: the stamps disagree → the lead is instructed not to publish the status → the
founder gets one sentence about staleness instead of a status → repeat every beat. **The
mechanism that exists to prevent lying-green is currently producing silence.** That is the bug.
Not the hook firing, not the collector, not the founder's repo.

`_emit_ready_line` (`leadv2-broad-status.sh:125-136`) prints `at=$BEAT_AT`, and the degraded
writer (`:150`) also prints `$BEAT_AT` — but the happy-path artifact writer does not
consistently, and `_now_iso` is used in neighbouring writes (`:175`, `:1237`). Find every place
line 1 of `founder-status.md` can be written and prove which ones do not use `$BEAT_AT`.

## [Critical] one stamp, written once

`BEAT_AT` is the beat's identity. Line 1 of the artifact and the `at=` token of the ready line
must be the same value from the same beat, on the happy path, the degraded path, and any
failure path. No `_now_iso` may ever appear in a position that becomes line 1.

## [Critical] the fallback must speak, not go quiet

Even with the stamps unified, a genuinely stale artifact must not reduce the founder to one
line about staleness. When the artifact cannot be trusted, the beat must still deliver **the
facts it can compute right now**: how many lanes are live, which, and their last activity —
computed at beat time, not read from the suspect file. Silence is never an acceptable output
of a beat that fired.

State in `report.md` what the minimum guaranteed content is, and make it impossible for the
beat to emit less than that.

## [Medium] make disagreement visible instead of inferred

Today the lead discovers the mismatch by eyeballing two timestamps. The ready line should
carry the artifact's own stamp too, so a mismatch is a fact in the line rather than a
comparison the reader has to perform and can silently get wrong.

## Acceptance

Build `test-beat-stamp-agreement.sh` against a fixture project root — never a real repo, never
a real state dir — covering:

1. happy path ⇒ line 1 of the artifact and the ready line's `at=` are byte-identical;
2. degraded path ⇒ same;
3. collection failure and render failure paths ⇒ same, or no `path=` token at all;
4. a deliberately stale artifact ⇒ the beat still emits live lane facts, not just a staleness
   notice;
5. zero live lanes ⇒ the beat still emits something truthful (the founder wants beats in every
   repo he works in — do NOT add an idleness guard, that was explicitly rejected).

Add the `EXTRA_SUITE_MAP` rows for every touched script and prove selection with
`--scope changed`.

## Rules

- Mutation INSIDE the production function body, RED, revert, GREEN, clean `git diff --stat`.
  A suite that stays green with the fix removed is a failed control; a printed `RED control:`
  line that does not change the exit code is not an assertion, and neither is a `FAIL:` line
  that leaves `$?` at 0 — that exact defect shipped in another lane last night.
- No `grep` against script source as an assertion; no negated command as an assertion; no
  scratch-copy mutation; no `git show HEAD:` pre-image; a commit message is not evidence.
- The suite must leave every repo path and every real state root byte-identical, on the failure
  path too. Another lane spent three rounds on exactly this.
- **Do not reorder or restructure the hook arrays in any `settings.json`** — a previous
  reordering evicted the tail of the array, including `scheduled-decisions-inject.sh`.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial.

## Done means

A beat that fires always produces a truthful, useful status; the artifact's stamp and the ready
line's `at=` can never disagree; and a mutation that reintroduces either failure turns the
suite red with the exit code following.
