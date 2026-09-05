REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=0 high=1 medium=3 low=5

FINDING: severity=High file=report.md line=1 dimension=design desc=Lane overwrites the tracked root `report.md` — another lane's deliverable (PLUGIN-PAPERCUTS-01, base blob cb9b598 salvaged by 7acecac) — with a stale round-1 duplicate of this lane's own report, destroying a foreign artifact on merge and leaving two contradictory copies in-tree.

## Evidence basis (live probes run this review)

- Both new suites re-run green: `test-glm-lock-per-lane: 14 passed, 0 failed` (rc 0), `test-glm-flash-handle: 13 passed, 0 failed` (rc 0), `LEADV2_SUITE_LOCK_DISABLE=1`.
- Falsifiability gate re-run on lock suite: `verdict: falsifiable` (matches report round-2 output).
- `cmd_bg` final `echo "${run_id}"` at glm-coder.sh:1892 — verified exactly one occurrence in the file; `cmd_status` empty-arg → `latest_run_id()` fallback at 1900-1908 verified (round-3 guard rationale is real).
- `EXTRA_SUITE_MAP` consumer loops all rows and `add_suite` dedupes — duplicate `glm-coder.sh:` keys are the established pattern, no finding.
- All lock paths go through `lock_dir_for` → `LOCK_ROOT` (grep: lines 448/489/560/1562/1891); `.lockref`-based revive inherits the new key consistently.
- kimi sibling halving bug confirmed still present (`_kimi_half`, leadv2-dispatch-code.sh ~5060).
- abcef42 exists ("salvage(dispatch): unattributed handle parser…") — report history claim corroborated.

## Findings

**High — root `report.md` clobbers a foreign lane's tracked artifact.** The diff modifies `report.md` at repo root (index cb9b598→c0a456c); the base content is the PLUGIN-PAPERCUTS-01 analysis report, last touched by that lane's salvage commit 7acecac (`git show main:report.md` → "# PLUGIN-PAPERCUTS-01 Analysis Report"). This lane replaces it with a duplicate of its own report — and a **stale round-1** duplicate (claims 7/0 and 8/0; current reality is 14/0 and 13/0 per my runs), while the canonical copy lives at `docs/handoff/GLM-ARM-THROUGHPUT-01/report.md`. On merge this silently destroys another lane's deliverable and ships contradictory numbers. Census of the shape: one instance — every other touched file is in this lane's write set. Fix: drop the root `report.md` hunk from the commit (restore main's blob); the handoff-dir report is the deliverable.

**Medium — dispatcher takes full stdout, the suite pins only the last line.** The production fix is `handle="${out%$'\n'}"` (leadv2-dispatch-code.sh _spawn_worker_body), i.e. handle = the launcher's *entire* stdout, while the suite's launcher case captures with `| tail -1` (test-glm-flash-handle.sh:119-125). Note `$(...)` already strips trailing newlines, so `%$'\n'` is a no-op — handle is verbatim full stdout. A launcher that ever emits one extra stdout line (warning, deprecation notice) produces a multi-line garbage handle in production while the suite stays green. The test should assert stdout is *exactly one non-empty line*, matching the code path it claims to guard.

**Medium — discarded probe can leave a stale rc in the (c) subdir assertion.** test-glm-lock-per-lane.sh case (c): `c3_rc=0`; the `nonexistent-sub` probe runs `|| c3_rc=$?`, then the *real* `${REPO}/sub` probe runs `|| c3_rc=$?`. If the second probe *succeeds* (rc 0 — exactly the regression the case exists to catch), the `||` branch is skipped and `c3_rc` keeps the first, discarded probe's value. A false PASS requires the nonexistent-path probe to have exited 75 (its fallback hash key colliding with a held lock — 48-bit unlikely), so it is not practically exploitable today, but the assertion reads the wrong probe's result by construction. Run the real-subdir probe into a fresh variable, or delete the dead nonexistent-sub invocation.

**Medium — headline incident citation is not reproducible from the tree.** The handoff report's "What was wrong (evidence)" cites "Incident journal row (2026-09-01T20:02:10Z, task 8799bc93): `spawn_failed by=router model=glm-flash ... reason=not_live`". No `docs/handoff/dispatch-8799bc93/` or `docs/leadv2/tasks/dispatch-8799bc93/` exists in this worktree; grep of `docs/leadv2/tasks/*/journal.md` and `bus.jsonl` finds zero `not_live` rows. The incident *class* is corroborated (186 `reason=not_live` mentions across `~/.claude/cache/glm-runs/*/journal.jsonl` transcripts) and the parser bug itself is verified in source, so this does not drive the code decision — but the report presents a specific artifact as evidence that I could not locate; either name the actual file path or mark it UNVERIFIED.

**Low — degenerate lock keys when `--show-toplevel` is empty.** `glm_lock_key_for`: cwd inside `.git/`, `worktrees/<id>/`, or a bare repo makes `toplevel` empty → key = `common_abs|` — all such cwds of one repo share one key, where the old code hashed distinct cwd strings. Unreachable from the dispatcher (always a project/worktree cwd) but it is a behavior change on degenerate inputs.

**Low — handoff report's own figures drift internally.** The "Suites (new)" section still says "7 pass / 0 fail, 2.9 s" / "8 pass / 0 fail, 6.5 s" while the round-2/3 sections (and my live runs) say 14/0 and 13/0. Append-only history is fine; a one-line "(superseded, see Round 2)" would prevent a reader citing the stale counts — as the root report.md already demonstrates.

**Low — kimi arm still ships the identical halving bug.** Confirmed live: `_kimi_temp`/`_kimi_half` truncation and `spawn_failed ... model=kimi ... reason=not_live` remain in `_spawn_worker_body`. Documented as out-of-scope in the report, but every kimi spawn through the router is stillborn until a lane fixes it — ensure it reaches the backlog, not just this report.

**Low — mutation-control guard greps the whole file.** test-glm-flash-handle.sh's "mutation NOT applied" guard is `grep -Fq 'echo "${run_id}"' "${MUT_SCRIPT}"`. Safe today (exactly one occurrence, glm-coder.sh:1892 — verified), but a second occurrence anywhere in the file would make every honest run report "mutation NOT applied" and fail spuriously. Anchor the guard to the needle the python step asserts (`echo "${run_id}"\n}\n\nlatest_run_id()`).

**Low — dead env assignment in the lock mutation control.** `mut1` sets `GLM_LOCK_SUITE_SCRIPT="${MUT_SCRIPT}"` for an inner `bash -c` that invokes `"$1"` directly and never reads the variable.

## Claims-without-evidence enumeration (added lines only)

Git-semantics claims driving the key design (`--git-common-dir` vs `--show-toplevel` for main-vs-worktree discrimination, symlink-spelling collapse) — verified live via the green suite run (cases a/b2/c exercise exactly this) plus my source read of `git` invocation sites. Quota-stub "three-provider shape" and `unknown_capped` — internal dispatcher behavior, exercised green. `ZAI_BASE_URL` is context, not added. No untagged external-API claim drives a decision; the one soft citation is the Medium incident-row item above.

The core code fixes (per-worktree lock key, handle parser, suite falsifiability hardening) are correct and independently reproduced green; the FAIL is the foreign-file clobber, which is a commit-hygiene fix, not a code rewrite.

NOT-COMMITTED: review only — I changed no files (probe artifacts above; both suites and the gate were run read-only against hermetic temp fixtures). No stash created.
