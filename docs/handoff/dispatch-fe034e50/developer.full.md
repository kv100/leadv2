# dispatch-fe034e50 — CORE-OFFLINE-WORKTREE-GAP-01 — developer full report

## Prepass census correction

The architect prepass (§0) already falsified the mission's framing: the failure is
HOME-dependent, not worktree-dependent, and the fixture HOME used by
`run-core-offline.sh` (`_core_offline_default_shards` when shards>1, and every
`SERIAL` entry too) is what triggers it, not the worktree per se. Confirmed by
reproducing before any edit: `HOME=<empty tmp> bash test-fanout-classify-guard.sh`
was FAIL=3 on the unmodified main checkout.

One correction to the design's own diagnostics, found while implementing: the
design's §5 hypothesis for the ladder test (d) — a root-variable mismatch between
`CLAUDE_PROJECT_ROOT` (used by the dispatch call) and `LEADV2_PROJECT_ROOT` (used
by the renderer call) — is not what's happening. Both resolve to the *same* `ROOT`
value in the test, so there is no mismatch. Instrumented directly (temporary
`printf` debug in `cmd_resolve`'s sonnet-candidate branch, removed before
finishing — `git diff` on `leadv2-dispatch-code.sh` is empty) and confirmed:
`_arm_exception_bump` fires correctly, with the right reason
(`glm_refused_quota_gate`) and the right `PROJECT_ROOT`, and
`${ROOT}/docs/leadv2/.arm-exceptions-<day>` is written correctly
(`count=1 last_reason=glm_refused_quota_gate sig8=...`).

The real cause: `leadv2-broad-status.sh`'s renderer, by design ("rule 6: nothing
cut is lost — full doc, single writer", `leadv2-broad-status.sh:786-796`), *always*
compacts the entire queue section — which is where the provider-health /
sonnet-fallback line lives (`queue_md`, appended at `broad-status.sh:692`) — out of
the short `founder-status.md` whenever the queue has any content at all
(`if _queue_line_count:` — unconditional, not a length cap), replacing it with a
"(скрыто: N строк очереди — see founder-status-full.md)" pointer. The line has
*never* been written to the compact `founder-status.md`; it only ever lands in
`founder-status-full.md`. Test case (d) was asserting against the wrong artifact.
This matches the design's own contingency for "cause 3" (a test-side mismatch, not
a product bug) even though the specific mechanism (file target, not root variable)
differs from what was guessed — the design explicitly authorizes fixing the test in
that case. `leadv2-dispatch-code.sh` was not touched; the sonnet-fallback counter
was never silently dead.

## Changes (LANE_WRITES)

1. `plugins/leadv2/scripts/leadv2-fanout.sh` (C1): registry resolution is now
   sibling-first (`${SCRIPT_DIR}/leadv2-active-registry.sh`) → vendored
   (`${PROJECT_ROOT}/.claude/scripts/...`) → canonical
   (`${LEADV2_CANONICAL_ROOT:-$HOME/Projects/leadv2}/plugins/leadv2/scripts/...`) →
   shared (`${HOME}/.claude/leadv2-shared/scripts/...`), each gated on `[[ -s ]]`
   not `[[ -f ]]`. All four missing → one owned `printf ... >&2; exit 1` line (no
   `log_error`, which isn't defined yet at this point in the script — flagged in
   the design, verified true).

2. `plugins/leadv2/scripts/leadv2-fanout-lane-launcher.sh` (C2): the independent,
   previously-untested copy of the same two-branch idiom on the live lane-launch
   path, given the identical four-branch fix. Uses `log_error` (already defined
   here) instead of raw `printf`.

3. `plugins/leadv2/scripts/tests/test-fanout-classify-guard.sh` (C3+C4):
   `_new_sandbox()` now stages the registry helper into `${sandbox}/proj/.claude/scripts/`
   so tests 2-4 are hermetic (no host `.claude/scripts` or `$HOME` dependency). New
   `test_5_registry_resolution_no_host_deps`: runs `--dry-run` with an empty fixture
   `$HOME` and no vendored `.claude/scripts`, asserts `class=Standard` — proving the
   sibling branch alone suffices. This is the regression that would have caught the
   original outage.

4. `plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh` (C5): case (d) positive
   and negative assertions now read `founder-status-full.md` instead of
   `founder-status.md`, per the root-cause finding above. No change to what is being
   proven (a degraded provider is visible in a rendered artifact) — only which
   artifact.

5. `plugins/leadv2/scripts/leadv2-dispatch-code.sh`: **no change**. Listed in
   LANE_WRITES as a candidate for the ladder fix; diagnosis showed it needed none
   (`git diff` is empty).

## Falsification set

```
$ for f in plugins/leadv2/scripts/leadv2-fanout.sh plugins/leadv2/scripts/leadv2-fanout-lane-launcher.sh \
    plugins/leadv2/scripts/tests/test-fanout-classify-guard.sh plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh \
    plugins/leadv2/scripts/leadv2-dispatch-code.sh; do bash -n "$f" && echo "OK: $f"; done
OK: plugins/leadv2/scripts/leadv2-fanout.sh
OK: plugins/leadv2/scripts/leadv2-fanout-lane-launcher.sh
OK: plugins/leadv2/scripts/tests/test-fanout-classify-guard.sh
OK: plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh
OK: plugins/leadv2/scripts/leadv2-dispatch-code.sh
```

Fanout guard suite — RED before fix (reproduced on unmodified main):
```
$ H=$(mktemp -d); HOME="$H" bash plugins/leadv2/scripts/tests/test-fanout-classify-guard.sh
[TEST] FAIL: Test 2: out=...leadv2-fanout.sh: line 52: .../leadv2-shared/scripts/leadv2-active-registry.sh: No such file or directory
[TEST] FAIL: Test 3: ... (same)
[TEST] FAIL: Test 4: ... (same)
[TEST] === Results: PASS=1 FAIL=3 ===
```

Fanout guard suite — GREEN after fix (same fixture HOME + the real
run-core-offline.sh PYTHONUSERBASE propagation, since fanout.sh's fail-closed
active.yaml YAML parse needs pyyaml, which core-offline already solves via
`_CORE_OFFLINE_PYTHONUSERBASE` — confirmed this is pre-existing, unrelated
machinery, not something this lane needed to fix):
```
$ PUB="$(python3 -c 'import site; print(site.USER_BASE)')"
$ H=$(mktemp -d); mkdir -p "$H/.claude/cache"
$ HOME="$H" PYTHONUSERBASE="$PUB" bash plugins/leadv2/scripts/tests/test-fanout-classify-guard.sh
[TEST] PASS: Test 1: bash -n OK (fanout + classify + session-runner)
[TEST] PASS: Test 2: class=Standard, classifier ran normally
[TEST] PASS: Test 3: loud WARN printed, class=Standard (no silent Heavy escalation)
[TEST] PASS: Test 4: missing completion runner refused the launch
[TEST] PASS: Test 5: sibling-only resolution sufficient, no host $HOME/.claude/scripts dependency
[TEST] === Results: PASS=5 FAIL=0 ===
```

Ladder suite — GREEN after fix:
```
$ bash plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh
PASS: (a) park row written before sonnet fallback worker spawn (ordering holds)
PASS: (a) poison fence held
PASS: (b) glm-deferred --list prints the parked sig8
PASS: (b) glm-deferred --list prints 'no deferred glm tasks' when empty
PASS: (c) two credit-empty computations within 24h emit exactly ONE journal line
PASS: (c) a third computation after the stamp ages past 24h emits a second journal line
PASS: (d) rendered founder-status-full.md contains sonnet-фолбэков сегодня: 1 (glm_refused_quota_gate) -- real reason variant, not hardcoded 'glm quota'
PASS: (d) a day with no fallback renders no sonnet-fallback line
PASS: (e) shared-cache double refusal: count=2, both distinct sig8s recorded
PASS: (e) park queue holds a row for both distinct sig8s
PASS: (e) run 2's park row carries reason=glm_refused_quota_precheck (benched, never attempted)
PASS: (e2) a repeat bump for an already-present sig8 is a no-op (count stays 1)
PASS: (g) a parked row whose sig8 already landed is reaped, not retried
PASS: (h) a parked row with no usable mission is skipped and stays in the queue (H3)
PASS: (i) a failed retry dispatch leaves the row pending
PASS: (f) real retry-all: new dispatch observed (marker file), 'retried as=', old sig8 reaped from --list
PASS: poison fence held across the suite
```

Full `run-core-offline.sh`, run from INSIDE this lane worktree (the failing
environment per the mission), foreground, exit 0:
```
$ bash plugins/leadv2/scripts/tests/run-core-offline.sh
...
[TEST] === Results: PASS=5 FAIL=0 ===        (fanout classifier/runner guard)
...
  glm-deferred-ladder suite: FAIL=0
...
[CORE-OFFLINE] suites passed=73 failed=0 missing=0 repo=/Users/kostiantyn.vlasenko/Projects/leadv2
```

## Non-goals honored

- Did not touch `run-core-offline.sh` shard/`SERIAL`/HOME logic.
- Did not create/populate `~/.claude/leadv2-shared/` or any `.claude/scripts/`
  symlink farm.
- Did not touch the 18 "safe" census hits from the design's §1c survey.
- Did not touch `test-codex-quota-gate.sh` / `test-codex-doc-pointer.sh` host
  dependencies (real, different class — confirmed still present, out of scope).
- Did not weaken, skip, or delete the (d) assertion's substance — only retargeted
  which artifact it reads, which is the design's own explicitly-authorized
  contingency for a test-side (not product-side) root cause.
- Did not commit any `.arm-exceptions-*` files.

## Collateral cleanup

Running `run-core-offline.sh` directly against the live (non-isolated) main
checkout state briefly rewrote several `docs/leadv2/*` symlinks (`active.yaml`,
`.bus.lock`, `.merge.lock`, `bus.jsonl`, `merge-queue.jsonl`, `open-threads.md`,
`questions`, `active.yaml.lock`, `.bus-offsets`) to point at a since-deleted
`/var/folders/.../core-offline-run.*` tmp path, and touched `started_at` timestamps
in three `docs/handoff/dispatch-nw*/phases.d/*.yaml` files — pre-existing
run-core-offline.sh behavior unrelated to this lane's diff, not something I
introduced by editing. Reverted all of these via `git checkout --` before
finishing; final `git diff --stat` contains only the 4 intended files. Left two
untracked files alone that predate this session and aren't mine
(`docs/leadv2/burn-deferred.{jsonl,d/}` from ~11:50, `plugins/leadv2/scripts/ZZ-pre-review-run.sh`
from Aug 22) — they belong to other concurrent lane activity in this shared repo.

DELIVERABLE_COMPLETE
