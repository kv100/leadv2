# LIVE-LANES-RUN-WITHOUT-A-JOURNAL-01

## Bug

`leadv2-journal.sh` (writer, canonical in this repo, symlinked into
persona-engine/m3-market/respiro-ios) fell back to `git rev-parse
--show-toplevel`, which returns the WORKTREE from inside a linked worktree.
`scripts/anti-silence-pulse.sh` (reader, persona-engine) had no such
fallback and resolved a fixed root from its own session. A worker
journaling from a worktree was invisible to a reader rooted elsewhere in
the same repo — "runs without a journal" even though the worker journaled
correctly by its own rule.

A prior fix round (`faa445d6f`/`522776e58`, dispatch-e9272511) widened the
READER to guess 4 candidate paths (own-root/foreign-root × founder-key/
dispatch-key). A live confirmation on 2026-09-06
(`persona-engine/docs/handoff/LIVE-LANES-RUN-WITHOUT-A-JOURNAL-01/live-confirmation-20260906.md`)
showed a lane with 5 journals under mismatched sub-dispatch/review IDs
still reported absent — guessing can never fully converge with an
independently evolving writer.

## Fix: one resolver, not two guessers

`leadv2-journal.sh` gained a `path <task-id>` subcommand. Internally it now
resolves `TASK_DIR` via `leadv2-state-path.sh --no-link "tasks/<task-id>"`,
which roots at `git rev-parse --git-common-dir` — identical from every
worktree of one repo, unlike `--show-toplevel`. Falls back to the old
per-checkout layout only if the resolver script is missing/errors, so a
worker is never left unable to write.

`anti-silence-pulse.sh` gained a tier 0: shell out to
`leadv2-journal.sh path <task-id>` (and again for the dispatch key) as the
FIRST two candidates, before the 4 existing guess-based tiers, which remain
as fallback for lanes journaled by an older writer. Reader and writer now
compute the address by calling the same function, not by synchronized
duplicated logic.

**Root chosen**: the shared control-plane state root
(`~/.claude/leadv2-state/<repo-slug>/tasks/<task-id>/journal.md`), not the
checkout. This is the existing precedent for every other managed
control-plane name (`active.yaml`, `bus.jsonl`, etc.) and is the only root
that is simultaneously reachable and worktree-invariant — a checkout-rooted
address is by definition private to one worktree, which is the bug.

## Proof

1. **Before/after, real worktree lane** — `test-leadv2-journal.sh`
   "worktree path identity": `git worktree add` a linked worktree of a
   scratch repo, resolve `path <task-id>` from both roots — byte-identical,
   outside both checkouts.
2. **Both consumers agree** — `anti-silence-pulse.sh` is the only concrete
   external reader found. `leadv2-lane-liveness.sh` was checked
   (`journal.jsonl`/`progress.log` at lines 501/554) — unrelated Codex-run
   journals, not this resolver. No second "Monitor" consumer of this
   resolver exists today, per the mission's escape hatch.
3. **Negative control** — a task-id that never journaled returns empty
   output, rc=0 (not a fabricated entry); `anti-silence-pulse.sh`'s
   pre-existing tier-void test continues to pass unmodified.
4. **Mutation control (RED-then-GREEN)**:
   ```
   leadv2:         leadv2-journal path-identity (pre_rc=1 -> post_rc=0)
   persona-engine: tier0-canonical-founder-key (pre_rc=1 -> post_rc=0)
   persona-engine: tier0b-canonical-dispatch-key (pre_rc=1 -> post_rc=0)
   ```
   leadv2 mutant forces `TASK_DIR` back to the old per-checkout formula —
   diverges (RED), real script agrees (GREEN). persona-engine mutants
   delete/no-op each new `_add(_canonical_journal(...))` call — fails
   (RED), real script succeeds (GREEN).
5. **CI selection proof** (state file reset first):
   ```
   $ rm -f "$(git rev-parse --git-dir)/leadv2-run-all-last-checked-sha"
   $ LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed
   [SELECT] .../plugins/leadv2/scripts/tests/test-leadv2-journal.sh
   run-all: 5 selected, scope=changed, select_only=1
   ```
   Auto-selected by the stem convention (`leadv2-journal.sh` →
   `test-leadv2-journal.sh`); no `EXTRA_SUITE_MAP` row needed.
   persona-engine has no select-only mode; `--scope changed` itself
   confirms selection: `OK: PASS test-anti-silence-pulse.sh`.
6. **Every triggering suite run** — `test-anti-silence-pulse-hooks.sh` also
   matches "anti-silence-pulse" by grep but covers a disjoint pair of
   scripts (`.claude/hooks/anti-silence-pulse-arm-inject.sh`,
   `anti-silence-pulse-detector.sh`), not `scripts/anti-silence-pulse.sh`;
   confirmed out of scope, correctly not selected. No other leadv2 suite
   references `leadv2-journal.sh`.
7. **Results**:
   - leadv2 `--scope changed`: 4 passed, 1 failed (`run-core-offline.sh`,
     always-on regardless of scope; all nested reds are the 15 entries
     already in `tests/known-red-suites.txt`, dated 2026-09-02,
     FIFTEEN-RED-SUITES-01 — none reference `leadv2-journal.sh` or
     `leadv2-state-path.sh`). No allowlist change (only shrink permitted;
     nothing here to shrink).
   - persona-engine `--scope changed`: `test-anti-silence-pulse.sh` 88/88
     (82 pre-existing + 6 new). Two OTHER suites fail
     (`test-probe-generate.sh`, `test-sessionstart-hook-schema.sh`) —
     unrelated subsystems (engine-flag rows, SessionStart hook JSON
     shape). Root cause: this lane's branch is an ancestor of `main`
     (`git merge-base --is-ancestor HEAD main`), so `--scope changed`
     diffs against a stale merge-base and pulls in ~219 files of drift
     this lane never touched. Not fixed here (pre-existing branch
     staleness, not a consequence of this task's diff);
     `tests/known-failures.txt` untouched.

## Commits
- leadv2: `ecb3225d` (writer + `path` subcommand + `test-leadv2-journal.sh`)
- persona-engine: `ffae79872` (tier-0 resolver call + 6 new test assertions)
