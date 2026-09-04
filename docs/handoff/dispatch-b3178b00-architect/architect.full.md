# architect — dispatch-b3178b00 (PLUGIN-CORE-OFFLINE-4RED-01, ROUND 2 finisher design)

Lane worktree: `.claude/worktrees/e2e9d9b2`, branch `worktree-e2e9d9b2` (round-1 diff uncommitted).
Design only — no implementation here.

## 0. What the round-1 diff actually is (verified in the lane)

`git diff --stat` in the lane, test files only:

| file | round-1 change |
|---|---|
| `tests/fixtures/pe_run_cache_sync.sh` | file-level `DRY_RUN="${LEADV2_TEST_DRY_RUN:-false}"` (the wrong lever — CRITICAL-1) |
| `tests/test-fg-dispatch-guard.sh` | case 20 rewritten to grep the *dispatcher file* for the guard name (the lying green — HIGH-1) |
| `tests/test-lane-truth-batch-01.sh` | 3 call sites given explicit `--write` (correct pattern; keep) |
| `tests/test-routing-enforcement-p1.sh` | `log` case added to fake codex + `LEADV2_CODEX_FIRST_BYTE_SECS` per call + new dead-arm case (keep) |

Plus two tracked journal files dirtied by running the suite (`docs/leadv2/tasks/dispatch-567ba028/journal.md`,
`dispatch-59ae8b51/journal.md`, +90 lines) — MEDIUM-1, must be reverted, never committed.

The 4 suites that went red in the critic's full-runner pass map to (run-core-offline.sh line → file):

| runner label | file | finding |
|---|---|---|
| plugin sync quarantine/dry-run safety (:104) | `test-drift-guard-quarantine-perimeter.sh` | CRITICAL-1 |
| product-close waits for worker exit (:86) | `test-no-work-terminal.sh` | CRITICAL-1 (shared-state class) |
| Codex full-cycle runner (:89) | `test-codex-session-runner.sh` | MEDIUM-2 (live quota) |
| supervisor reconciliation (:99) | `test-supervise-v2.sh` | CRITICAL-1 (shared-state class) |

## 1. CRITICAL-1 — kill the order/state dependence

### 1a. Root-cause frame (what the evidence already narrows to)

`run_check()` (run-core-offline.sh:47-66) executes each suite as `"$@"` → a child `bash`, so suites
cannot leak *shell* state to each other, but they inherit **the runner's whole environment**, and
they share **three global surfaces**:

1. **Environment inheritance from the invoking shell.** Every suite is a child of the operator's
   shell. Any `LEADV2_*` / `DRY_RUN` / `CLAUDE_*` / `GIT_*` variable exported in the session that
   launched the runner is visible to all 50 suites. This is the only mechanism that explains
   "passes twice standalone, fails inside the runner" without any suite-to-suite write, and it is
   also the mechanism the round-1 fixture default is defenceless against
   (`DRY_RUN="${LEADV2_TEST_DRY_RUN:-false}"` obeys whatever the outer session exported).
2. **The real `$HOME` / `~/.claude` state tree.** Suites that do not override `HOME` read live
   caches: `~/.claude/cache/arm-cooldown` (leadv2-arm-cooldown.sh:34), the state-path-resolved
   `codex-circuit.json` (leadv2-codex-circuit.sh:17-24), dispatch cache dirs, lockout files. A suite
   that *writes* one of those (or a real earlier dispatch that did) changes a later suite's verdict.
3. **The real repo working tree** (`docs/leadv2/**` journals, `active.yaml`, `bus.jsonl`,
   `merge-queue.jsonl`) — MEDIUM-1's surface, and a genuine cross-suite channel: suite A's journal
   append is suite B's input.

`test-drift-guard-quarantine-perimeter.sh:104-122` additionally hides *which* invariant broke: the
dry-run case is one `if A && B && C` with a single `fail` string, so the round-1 dev could not tell
whether the target got reconciled (A), quarantine got written (B), or the
`DRY_RUN DIRECTION-SAFETY` line never appeared (C). **Decomposing that compound assertion is part
of the fix, not a nicety** — it is the instrument that names the leaking variable.

### 1b. Prescribed changes

**(i) Fixture takes mode as a required argument — no file-level default, no env lever.**

`fixtures/pe_run_cache_sync.sh`: add a 5th positional parameter `mode`; accept exactly
`--dry-run` or `--write`; anything else (including absent) → `printf` usage to stderr and
`exit 3`. Set `DRY_RUN=true|false` from it *after* sourcing and *before* the
`_direction_safety_excludes` call (current line order is already correct). Delete
`LEADV2_TEST_DRY_RUN` from the fixture entirely.

Contract:

| arg | meaning |
|---|---|
| `$1` | plugin_sync path |
| `$2` | canonical scripts root |
| `$3` | src/ |
| `$4` | dst |
| `$5` | `--dry-run` \| `--write` (REQUIRED; exit 3 otherwise) |

`test-drift-guard-quarantine-perimeter.sh`: pass `--write` at the real-run call site (:63-70) and
`--dry-run` at the dry-run call site (:107-113); drop `LEADV2_TEST_DRY_RUN=true`. Grep-confirm no
other caller of the fixture or of `LEADV2_TEST_DRY_RUN` exists (round-1 grep: only these two).
This mirrors the `--write` pattern round 1 already applied correctly in
`test-lane-truth-batch-01.sh`, which is why that suite is stable.

**(ii) Decompose the dry-run compound assertion into three separately-reported checks**
(target-unchanged / quarantine-empty / DRY_RUN line present). No assertion is weakened — one
tri-state check becomes three named checks, each able to fail on its own.

**(iii) Runner-level env scrub — the categorical fix.**

In `run_check()`, invoke each suite through a scrub prefix instead of bare `"$@"`:

- unset the state-carrying families before exec: `DRY_RUN`, every `LEADV2_*`, every `CLAUDE_*`
  except `CLAUDE_PROJECT_ROOT`-if-the-runner-needs-it, `GIT_DIR`, `GIT_WORK_TREE`,
  `GIT_INDEX_FILE`, `GIT_CONFIG*`, `PROJECT_ROOT`;
- keep `PATH`, `HOME`, `USER`, `SHELL`, `LANG`, `LC_*`, `TERM`, `PYTHONPATH`;
- give each suite its own `TMPDIR="$RUN_TMP/<suite-name>"`.

Implementation shape: build the `-u` list dynamically (`compgen -e | grep -E '^(LEADV2_|CLAUDE_)'`)
plus a fixed list, then `env "${scrub[@]}" TMPDIR=... "$@"`. Deliberately **not** `env -i`: a
whitelist-only environment would red suites that legitimately depend on inherited `PATH`/python
site paths, and this lane must not manufacture new reds.

Preserve one escape hatch: `LEADV2_CORE_OFFLINE_NO_SCRUB=1` skips the scrub, so a future debugger
can reproduce the leaky behaviour on purpose. Default is scrub-on.

**(iv) Ordering falsification.** Add `LEADV2_CORE_OFFLINE_REVERSE=1` to run the suite list in
reverse order. If 50/0 holds forward, reverse, and forward-again, order-dependence is disproven by
construction rather than by two identical runs. (Two forward back-to-back runs remain the stated
acceptance; reverse is the stronger extra evidence and is cheap.)

**(v) If (i)-(iii) do not make `test-no-work-terminal.sh` / `test-supervise-v2.sh` green twice,
diagnose them the same way** — find the live-state read (`$HOME` cache, real `docs/leadv2`, real
`git`), redirect it into the suite's temp root, and report the read in the terminal artifact.
No assertion weakening, no engine edit; if either suite exposes a real engine regression, cite
file:line and stop (per non-goals).

## 2. HIGH-1 — assert registration, not a comment

`hooks/leadv2-bash-pre-dispatch.sh:56-68` holds `MANIFEST` as a newline-list of
`script|trigger-regex` records, consumed at :110 by `while IFS='|' read -r SCRIPT TRIGGER`, and
:78 prints `$SCRIPT` to stderr when `LEADV2_DISPATCH_TRACE=1`. Both assertions below are therefore
available; implement **both** (belt and braces — one proves registration, the other proves
reachability):

**2a. Field-parsed MANIFEST assertion.** Extract the manifest block from the dispatcher and assert
a record whose **first `|`-field** equals `leadv2-block-fg-dispatch.sh`. Parse, do not substring-
grep: e.g. read the `MANIFEST='...'` block via `sed -n "/^MANIFEST='/,/'$/p"`, strip the
`MANIFEST='` prefix and trailing quote, then `awk -F'|' '$1=="leadv2-block-fg-dispatch.sh"'`.
A comment line can never satisfy this because comments are outside the extracted block and would
not have the guard name as field 1 of a record.

**2b. Trace assertion.** Run the dispatcher with `LEADV2_DISPATCH_TRACE=1` and a command that
matches the guard's trigger regex (`leadv2-dispatch-code.sh`, per the manifest record), against a
hermetic project root, and assert the guard name appears on stderr. This proves the guard is
*selected at runtime*, the property HIGH-1 says was never tested.

**2c. Mandatory falsification evidence** (mission acceptance): replace the manifest record at
`leadv2-bash-pre-dispatch.sh:60` with an unregistered entry → suite must go RED; restore; suite
green. Paste both tallies. Also re-run the round-1 falsification (blank the comment) to show it no
longer changes the verdict.

## 3. MEDIUM-1 — hermetic writes

**3a. Revert the journal pollution from the diff before committing:**
`git checkout -- docs/leadv2/tasks/dispatch-567ba028/journal.md docs/leadv2/tasks/dispatch-59ae8b51/journal.md`
(and any other tracked `docs/leadv2/**` file the round-1 runs dirtied). These are not lane writes.

**3b. Close the leak at its source.** `leadv2-journal.sh:14` resolves
`PROJECT_ROOT="${CLAUDE_PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel || pwd)}}"`
and writes `${PROJECT_ROOT}/docs/leadv2/tasks/<task-id>/journal.md`. Any invocation path in
`test-routing-enforcement-p1.sh` that reaches the journal *without* `CLAUDE_PROJECT_ROOT` in the
environment lands in the real repo. Fix in the suite (not the engine):

- export a suite-wide default at the top of the suite — `CLAUDE_PROJECT_ROOT`,
  `CLAUDE_PROJECT_DIR`, `PROJECT_ROOT`, `LEADV2_PROJECT_ROOT` all pointing at
  `${TMP_ROOT}/default-root` — so a call site that forgets the per-case prefix still lands in TMP;
- export `LEADV2_JOURNAL_BIN="${TMP_ROOT}/journal-shim.sh"` where the shim appends to
  `${TMP_ROOT}/journal/<task>.md`, for suites that only need the journal to be *observable*;
  keep the real `leadv2-journal.sh` on cases that assert real journal formatting (those cases must
  carry the explicit `CLAUDE_PROJECT_ROOT` prefix).

**3c. Hermeticity post-condition in the runner.** After each suite, compare
`git -C "$REPO_ROOT" status --porcelain -- docs/leadv2` against a snapshot taken before it; on a
delta print `[CORE-OFFLINE] HERMETIC-VIOLATION: <suite> dirtied <paths>`.
Severity rule: **FAIL** for the suites this lane owns (the 4 red ones + the routing suite);
**WARN** for the rest. Rationale: a lane must not manufacture reds in suites it did not touch — but
if any other suite trips the warn, list it verbatim in the terminal artifact as a follow-up finding.
Gate the whole check behind `LEADV2_CORE_OFFLINE_HERMETIC_GATE` (default `1`).
Untracked residue (`docs/leadv2/founder-status.md`, `status-snapshot.json`, `.broad-status-prev.json`,
`tasks/backlog-pump/`, `docs/handoff/**`) pre-dates this lane and is out of scope — check tracked
modifications only.

## 4. MEDIUM-2 — de-couple the Codex full-cycle suite from live quota

`leadv2-codex-session-runner.sh:497-505` gates every spawn through `codex_spawn_gate`, which reads
two **live** state surfaces:

| surface | resolver | test override |
|---|---|---|
| arm cooldown | `leadv2-arm-cooldown.sh:34` → `${LEADV2_ARM_COOLDOWN_DIR:-$HOME/.claude/cache/arm-cooldown}` | `LEADV2_ARM_COOLDOWN_DIR="${TMP}/arm-cooldown"` (empty dir) |
| codex circuit | `leadv2-codex-circuit.sh:17-24` → `LEADV2_CODEX_CIRCUIT_FILE`, else state-path-resolved `codex-circuit.json` | `LEADV2_CODEX_CIRCUIT_FILE="${TMP}/codex-circuit.json"` |

Design for `test-codex-session-runner.sh`:

1. Point both overrides into the suite's temp root. **Do not** use `CODEX_SKIP_QUOTA_GATE=1` as the
   primary lever — that bypasses the gate instead of making it deterministic, and would hide a real
   gate regression.
2. The circuit is **fail-closed on unknown** (`circuit-unknown` → refuse, quota-gate lib :62-63), so
   an absent file is not automatically safe: seed `${TMP}/codex-circuit.json` with a *closed* state
   document. Read the writer in `lib/leadv2-codex-circuit.sh` for the exact schema and the literal
   `codex_circuit_state` returns for closed; assert on that literal, not on a guess.
3. Make the stub falsifiable both ways — two cases:
   - closed circuit + empty cooldown → runner proceeds; log must NOT contain
     `refused by quota gate`;
   - seeded **open** circuit → runner refuses with `CODEX_REFUSED_QUOTA reason=circuit`.
   Case 2 is what proves the stub did not simply neutralise the gate.
4. Assert non-interference: the live `~/.claude/cache/arm-cooldown` mtime/content is unchanged
   after the suite (cheap, and it is the concrete form of "offline").
5. Re-establish the 4-red premise after hermetization: state, per suite, whether it is still red
   for the originally claimed reason. If hermetization alone turns one green, say so explicitly —
   a premise that dissolves under isolation is a finding, not a failure.

## 5. Runtime (MEDIUM-2 second half)

Suite 1 measured at 182–214s (~15s/dispatch). Do not claim "seconds". Either report the measured
wall-clock per suite in the terminal artifact, or bound the dominant waits with existing knobs
(`LEADV2_CODEX_FIRST_BYTE_SECS` already done in round 1; look for the analogous
launch/stall deadlines the dispatch wrapper honours) — bounding is optional, honest reporting is not.

## 6. Change map

| file | change |
|---|---|
| `plugins/leadv2/scripts/tests/fixtures/pe_run_cache_sync.sh` | required `$5` mode arg, exit 3 on missing/unknown, remove `LEADV2_TEST_DRY_RUN` |
| `plugins/leadv2/scripts/tests/test-drift-guard-quarantine-perimeter.sh` | explicit `--write` / `--dry-run` at both call sites; split the tri-part dry-run assertion into 3 named checks |
| `plugins/leadv2/scripts/tests/test-fg-dispatch-guard.sh` | case 20 → field-parsed MANIFEST assertion + `LEADV2_DISPATCH_TRACE=1` reachability assertion |
| `plugins/leadv2/scripts/tests/test-routing-enforcement-p1.sh` | suite-wide hermetic root exports + journal shim; keep round-1 dead-arm case |
| `plugins/leadv2/scripts/tests/test-codex-session-runner.sh` | cooldown-dir + circuit-file overrides, seeded closed circuit, open-circuit negative case, live-cache non-interference check |
| `plugins/leadv2/scripts/tests/run-core-offline.sh` | env scrub + per-suite `TMPDIR` in `run_check`, `LEADV2_CORE_OFFLINE_REVERSE`, `LEADV2_CORE_OFFLINE_NO_SCRUB`, hermeticity post-condition |
| `plugins/leadv2/scripts/tests/test-lane-truth-batch-01.sh` | keep round-1 `--write` fix as-is |
| `plugins/leadv2/scripts/tests/test-no-work-terminal.sh`, `test-supervise-v2.sh` | only if §1(v) diagnosis implicates them; isolation of the live-state read they perform |

## 7. Constraint checklist

1. **Env naming** — all new vars use the `LEADV2_` prefix: `LEADV2_CORE_OFFLINE_NO_SCRUB`,
   `LEADV2_CORE_OFFLINE_REVERSE`, `LEADV2_CORE_OFFLINE_HERMETIC_GATE`; consistent with the existing
   `LEADV2_CORE_OFFLINE_PROBE` (run-core-offline.sh:38). Reused overrides
   (`LEADV2_ARM_COOLDOWN_DIR`, `LEADV2_CODEX_CIRCUIT_FILE`, `LEADV2_JOURNAL_BIN`) are the engine's
   own documented knobs — no new semantics invented. `LEADV2_TEST_DRY_RUN` is **retired**; grep the
   tree to confirm zero remaining readers after the change.
2. **Paths** — every file in §6 exists on disk in the lane; `${TMP_ROOT}/journal-shim.sh` and the
   seeded `codex-circuit.json` are `(to-create)` inside `mktemp` roots only.
3. **`claude -p`** — this lane introduces none. `run-core-offline.sh` invokes `claude plugin validate`
   (:75-80), not `claude -p`; unchanged.
4. **Concurrent access** — the runner and any parallel lane both touch `~/.claude/cache/*` and the
   real `docs/leadv2/**`. The env scrub + TMP redirection is exactly what removes that race for the
   suites in scope; the hermeticity post-condition detects it for the rest. Note in the artifact
   that a *parallel* live dispatch during the runner pass can still flip a non-isolated suite —
   run the two back-to-back acceptance passes with no other lane dispatching.
5. **Config contradiction** — `DRY_RUN` semantics: after
   DRIFT-GUARD-ADVISES-BACKWARD-SYNC-01 (07d8c56) `leadv2-plugin-sync.sh` defaults to dry-run and
   requires `--write`. Both the fixture and `test-lane-truth-batch-01.sh` now express mode
   explicitly, so no test encodes the pre-07d8c56 default. Pre-existing contradiction to report,
   not fix (out of scope, already flagged by the critic): `leadv2-fanout.sh:85` still advises a
   `--write`-less sync.

## 8. Out of scope for the implementer

- Engine/product code: `leadv2-dispatch-code.sh`, `leadv2-plugin-sync.sh`,
  `leadv2-codex-session-runner.sh`, `leadv2-bash-pre-dispatch.sh` (read-only — the HIGH-1
  falsification mutates `:60` **temporarily** and must restore it byte-for-byte),
  `leadv2-dispatch-product-close.sh` core logic, `leadv2-review-run.sh` mission text.
- `test-lane-writes-scoping` C3/L12.
- `leadv2-fanout.sh:85` stale advice.
- Deleting/relocating `.claude/scripts/tests/` duplicates (separate open thread).
- Any weakening of an existing assertion, and any new `docs/leadv2` / `docs/handoff` file.

## 9. Risks

| risk | mitigation |
|---|---|
| Env scrub reds suites that relied on an inherited `LEADV2_*` knob | denylist-scrub (not `env -i`); run the full runner immediately after adding the scrub and before any other change, so a new red is attributable to the scrub alone; `LEADV2_CORE_OFFLINE_NO_SCRUB=1` A/B confirms |
| Hermeticity post-condition reds untouched suites | FAIL only for lane-owned suites, WARN + verbatim report for the rest |
| Seeded circuit JSON schema guessed wrong → gate silently refuses and the suite passes for the wrong reason | the open-circuit negative case (§4.3) fails loudly if the seed is not being read |
| Two back-to-back green runs still hide order-dependence | add the reverse-order run (§1(iv)) |
| A parallel live lane dirties `docs/leadv2` mid-run and the hermetic gate blames this lane | record `git status --porcelain` before the first acceptance run and diff against it; state in the artifact that no other lane was dispatching |
| `exit 3` on missing fixture mode surfaces as an opaque suite failure | fixture prints an explicit usage line to stderr naming the required 5th arg |

## acceptance:

```yaml
acceptance:
  authored_at: 2026-08-19T09:19:08Z
  items:
    - surface: log_line
      observable: >
        Two consecutive terminal runs of run-core-offline.sh each end with the line
        "[CORE-OFFLINE] suites passed=50 failed=0 missing=0 repo=<lane worktree path>",
        and both runs' full output is pasted in the terminal artifact.
    - surface: log_line
      observable: >
        A third run with the suite order reversed also ends with
        "suites passed=50 failed=0 missing=0".
    - surface: log_line
      observable: >
        With the manifest record for leadv2-block-fg-dispatch.sh replaced by an unregistered
        entry, test-fg-dispatch-guard.sh prints a FAIL line naming the missing manifest
        registration and its tally shows a non-zero failure count; with the record restored the
        same suite prints zero failures.
    - surface: file_artifact
      observable: >
        After a full runner pass, git status in the lane worktree lists no modified tracked file
        under docs/leadv2/ — in particular no journal.md under docs/leadv2/tasks/ and no
        active.yaml / bus.jsonl / merge-queue.jsonl / open-threads.md / questions entry.
    - surface: log_line
      observable: >
        The Codex full-cycle suite's output contains no "refused by quota gate" line, and its
        seeded-open-circuit case prints a refusal naming reason=circuit — identical in both
        back-to-back runs.
    - surface: log_line
      observable: >
        The terminal artifact shows a commit sha on branch worktree-e2e9d9b2 whose diff contains
        only the files listed in LANE_WRITES.
```

LANE_WRITES: plugins/leadv2/scripts/tests/run-core-offline.sh, plugins/leadv2/scripts/tests/fixtures/pe_run_cache_sync.sh, plugins/leadv2/scripts/tests/test-drift-guard-quarantine-perimeter.sh, plugins/leadv2/scripts/tests/test-fg-dispatch-guard.sh, plugins/leadv2/scripts/tests/test-routing-enforcement-p1.sh, plugins/leadv2/scripts/tests/test-lane-truth-batch-01.sh, plugins/leadv2/scripts/tests/test-codex-session-runner.sh, plugins/leadv2/scripts/tests/test-no-work-terminal.sh, plugins/leadv2/scripts/tests/test-supervise-v2.sh

DELIVERABLE_COMPLETE
