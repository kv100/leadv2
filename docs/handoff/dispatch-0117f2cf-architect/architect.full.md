# architect — dispatch-0117f2cf (REVIEW-ROUND1-EXHAUSTIVE-01, round-2 finisher)

Design only. No implementation in this deliverable.

## 0. Where the code actually is (read this first)

The round-1 work is **uncommitted** and lives in the lane worktree, not on `main`:

| item | value |
|---|---|
| lane worktree | `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/2a2a3fb5` |
| lane branch | `worktree-2a2a3fb5` (at `85ae886`, identical to `main`) |
| dirty files | `plugins/leadv2/scripts/leadv2-review-run.sh` (+188), `plugins/leadv2/scripts/tests/run-core-offline.sh` (+1), `plugins/leadv2/skills/leadv2-review/SKILL.md` (+5/-2), untracked `plugins/leadv2/scripts/tests/test-review-round-exhaustive.sh` (297 lines) |

`main` has **none** of this (grep for `_review_round_context` on `main` → 0 hits). All work in this
lane must happen inside the lane worktree and commit on `worktree-2a2a3fb5`.

Two junk untracked files exist in `plugins/leadv2/scripts/tests/` — literally named
`bash test-review-round-exhaustive.sh > ` and `cp test-review-round-exhaustive.sh ` (mangled shell
commands materialised as filenames). **Delete them; never `git add` them.**

Also dirty in the lane worktree but **out of scope**: `docs/leadv2/tasks/dispatch-567ba028/journal.md`,
`docs/leadv2/tasks/dispatch-59ae8b51/journal.md`. Commit must be path-scoped to the four LANE_WRITES
files — do not `git commit -a`.

## 1. Layer / surface map

Single layer: the dispatch-side review runner (Bash) plus its offline test suite. No DB, no
migration, no Python contract, no product path.

| surface | file | current lines | role |
|---|---|---|---|
| round detection | `plugins/leadv2/scripts/leadv2-review-run.sh` §5b | 451–606 | hash, prior-findings body, round context, contract text |
| call site | same | 696–701 | `diff_hash=` → `_review_round_context` → `_review_build_contract` → `emit decision review_round …` |
| sidecar write (fail path) | same | 1013–1014 | `round=`/`diff=` → `.review-round.state` |
| sidecar write (pass path) | same | 1027–1028 | identical block, duplicated |
| tests | `plugins/leadv2/scripts/tests/test-review-round-exhaustive.sh` | 1–297 (T1–T7) | offline suite, T7 = red-first baseline |
| registration | `plugins/leadv2/scripts/tests/run-core-offline.sh` | +1 | suite registry |
| doc | `plugins/leadv2/skills/leadv2-review/SKILL.md` | +5/-2 | operator-visible mode description |

## 2. Data flow after the fix (numbered)

1. `diff_hash="$(_review_diff_hash)"` — now also sets `REVIEW_DIFF_HASH_OK` (1/0) and echoes any
   `shasum` stderr to this process's stderr.
2. `_review_round_context` parses `.review-round.state` → `sidecar_round`, `sidecar_diff`.
   `sidecar_round` is numeric-validated (`^[0-9]+$`, and `<= 999`); anything else → treated as absent.
3. Live gate `review-gate.md` `status:` read → `is_real_verdict` (pass|fail).
4. **Snapshot refresh** (only when `is_real_verdict=1` and `sidecar_round` valid): copy live
   `review-gate.md` → `review-gate.round<sidecar_round>.md` and `review-findings.json` →
   `review-findings.round<sidecar_round>.json` **whenever the destination is missing OR differs**
   (`cmp -s`). Never delete/rename the live gate.
5. **Prior round resolution**: `prior_round = max(sidecar_round, highest existing snapshot round)`,
   where the highest snapshot round is scanned from `review-gate.round<N>.md` and
   `review-findings.round<N>.json` filenames.
6. **Monotonic round** (mode-independent, before any mode branching): if a real prior verdict exists
   and `prior_round` is valid → `REVIEW_ROUND=$((prior_round + 1))`. Otherwise `REVIEW_ROUND=1`.
7. **Findings body**: `_review_prior_findings_body "${prior_round}"` — sourced from the *highest*
   snapshot, with a last-resort fallback to `FINDING:` lines in the live `review-gate.md`.
   Returns `count=<N>` as its **first stdout line**, then the capped body.
8. **Mode**: `verify_only` **only if** all of (real prior verdict) ∧ (`REVIEW_DIFF_HASH_OK=1`) ∧
   (diff hash differs from `sidecar_diff`) ∧ (**body non-empty**). Any missing axis → `exhaustive`
   at the already-incremented `REVIEW_ROUND`.
9. `_review_build_contract` prints `EXHAUSTIVE ROUND ${REVIEW_ROUND}` (no longer hardcoded `1`) or
   `VERIFICATION-ONLY ROUND ${REVIEW_ROUND}`.
10. `emit decision "review_round … prior_findings=${PRIOR_FINDINGS_COUNT}"` — count now real.
11. Sidecar write goes through **one** shared helper used by both former call sites; it writes
    `round=max(REVIEW_ROUND, sidecar_round)` and **skips the write entirely** when
    `REVIEW_DIFF_HASH_OK=0`.

## 3. Interface contracts

| symbol | signature | contract change |
|---|---|---|
| `_review_diff_hash` | `() -> stdout hash` | sets `REVIEW_DIFF_HASH_OK=0/1`; `shasum` stderr forwarded to stderr, no longer swallowed |
| `_review_prior_findings_body` | `(round) -> stdout` | **line 1 is `count=<int>`**, remainder is the body (may be empty). `PRIOR_FINDINGS_COUNT` is no longer a cross-subshell side channel |
| `_review_highest_snapshot_round` *(new)* | `() -> stdout int` | max `N` over `review-gate.round<N>.md` / `review-findings.round<N>.json`; `0` when none |
| `_review_round_context` | `() -> rc 0 always` | sets `REVIEW_ROUND` (monotonic), `REVIEW_MODE`, `PRIOR_FINDINGS_BODY`, `PRIOR_FINDINGS_COUNT` |
| `_review_state_write` *(new)* | `() -> rc 0 always` | atomic tmp+mv; clamps round; no-op when `REVIEW_DIFF_HASH_OK=0`. Replaces the duplicated blocks at 1013 and 1027 |
| `_review_build_contract` | `() -> stdout` | exhaustive header now carries the real round; four verbatim contract lines unchanged (downstream parsers unaffected) |

Parent-side parse of the count sentinel (exact, `set -u`-safe):

```
_raw="$(_review_prior_findings_body "${prior_round}")"
_first="${_raw%%$'\n'*}"
if [[ "${_first}" == count=* ]]; then
  PRIOR_FINDINGS_COUNT="${_first#count=}"
  [[ "${_raw}" == *$'\n'* ]] && findings_body="${_raw#*$'\n'}" || findings_body=""
else
  PRIOR_FINDINGS_COUNT=0; findings_body=""
fi
[[ "${PRIOR_FINDINGS_COUNT}" =~ ^[0-9]+$ ]] || PRIOR_FINDINGS_COUNT=0
```

The sentinel must never reach `_review_build_contract` — `PRIOR_FINDINGS_BODY` carries the stripped
body only. A test asserts `count=` never appears in the generated mission file.

## 4. Operator hatch (`LEADV2_REVIEW_ROUND`) — post-fix semantics

| value | round | mode |
|---|---|---|
| `1` | `1` | `exhaustive` (explicit force; kept as the test seam) |
| `2` | `max(2, prior_round+1)` | `verify_only` **only if** the prior-findings body is non-empty; empty body → `exhaustive` (H3) |
| unset / other | per §2 | per §2 |

The `=1` force still writes a lower round than the sidecar in principle — that regression is absorbed
by the clamp in `_review_state_write`, so on-disk round never decreases.

## 5. Per-finding fix map

| id | file:line (lane worktree) | fix |
|---|---|---|
| H1a | `leadv2-review-run.sh:520,572,1013,1027` | monotonic `REVIEW_ROUND` computed before mode branching; single clamped state writer |
| H1b | `:540–543` | `[[ -f ]] \|\| cp` → `cmp -s … \|\| cp -f` (refresh on divergence), for gate **and** findings json |
| H1c | `:562` / `:591` | findings from highest snapshot; exhaustive header prints the real round |
| H2 | `:465,495,553,562,701` | `count=` first-line sentinel + parent-side parse |
| H3 | `:551–555,563` | empty body ⇒ exhaustive on **both** the forced-2 path and the organic verify_only path |
| H4 | `test-review-round-exhaustive.sh` | new T8–T13, all folded into the T7 red-first check |
| M1 | `:451–454,1013,1027` | log `shasum` stderr; empty hash ⇒ exhaustive + no sidecar write |
| M2 | `:527,572` | `^[0-9]+$` guard on `sidecar_round` (and on the parsed count) |
| L1 | `run-core-offline.sh`, `SKILL.md` | suite-count claim 51/50 → 52 |
| L2 | `test-…:T1` | replace tautological `grep -q 'correctness'` with `EXHAUSTIVE ROUND` + `Census rule:` |
| L3 | `test-…:267–274` | baseline resolution: probe merge-base, fall back to pinned `85ae886`; if the pinned tree *also* contains `_review_round_context`, **`fail` loudly** instead of silently passing |

## 6. Test plan (H4) — every case red-first against baseline `85ae886`

| test | asserts |
|---|---|
| T8 | journal `review_round` line reports `prior_findings=<N>` matching the snapshot's finding count (non-zero) |
| T9 | forced `=1` → exhaustive/round 1; forced `=2` + empty body → exhaustive; forced `=2` + body → verify_only |
| T10 | H1 repro: r1 fail → fix → r2 verify_only → re-review **unchanged** diff → fix. Sidecar rounds non-decreasing (`1,2,2,3`); round-3 mission carries round-2 findings, not round-1 |
| T11 | 45 synthetic findings → 40 body lines + cap notice, `count=45`; a 400-char desc truncated to 300 |
| T12 | missing/unreadable `DIFF_FILE` → exhaustive, **no** `.review-round.state` written, stderr non-empty |
| T13 | `round=abc` sidecar → no `set -u` abort, rc 0, exhaustive round 1 |
| T7 (extended) | T8–T13 all fail against the pinned baseline tree |

Regression suites that must stay green: body-persist 13/0, arm-no-verdict 15/0, silence-gate 15/0.
Static: `bash -n` under bash 5 **and** bash 3.2; `shellcheck` rc=0.

## 7. Risks & mitigations

| risk | mitigation |
|---|---|
| Sentinel line leaks into mission text → reviewer sees `count=12` | dedicated assertion in T8 that the generated mission file contains no `count=` line |
| Snapshot overwrite destroys the only copy of an earlier round's findings | snapshots are keyed by round; overwrite only ever targets the round the live gate belongs to. Live gate is never renamed or removed |
| Monotonic round grows unbounded across a long lane | round is display/branching only; cap validation at `<= 999` on read prevents corrupt-value arithmetic |
| Bash 3.2: `${_raw%%$'\n'*}` and `cmp -s` | both are 3.2-safe; `mapfile`/`readarray`/`declare -A` remain forbidden — keep the existing `while read` idiom |
| `set -u` abort inside an "rc always 0" function | every new variable initialised at function top; numeric guards before all arithmetic |
| Parallel worktrees share one git dir; `git archive` in T7 reads the repo, not the worktree | keep `git -C "${LEADV2_REPO}"`; tests extract into `PREFIX_DIR` (mktemp), never into the worktree |
| `.review-round.state` concurrent write | already tmp+mv atomic; the single writer helper preserves it |
| Committing unrelated dirty journals | path-scoped `git add` of exactly the four LANE_WRITES files |

## 8. Constraint checklist

1. **Env naming** — `LEADV2_REVIEW_ROUND`, `LEADV2_TEST_BASELINE_REF`, `LEADV2_REPO` all `LEADV2_*`. No new env var introduced. ✅
2. **Paths** — all listed paths exist in the lane worktree; `_review_highest_snapshot_round` and
   `_review_state_write` marked *(new)*. ✅
3. **`claude -p`** — none added or modified by this change. ✅ (n/a)
4. **Concurrent access** — `.review-round.state` and the round snapshots are the only shared mutable
   files; single atomic writer, snapshots keyed by round. ✅
5. **Config contradiction** — `LEADV2_REVIEW_ROUND` semantics change (empty body no longer forces
   verify_only). Only consumer is §5b of this script plus the tests; `SKILL.md` text must be updated
   in the same commit or the doc contradicts the code. ✅ (SKILL.md is in LANE_WRITES)

## 9. Non-goals

- No product-close, arm-selection, pool, quota, or dispatch-routing changes.
- No change to the four verbatim contract lines or to `parse_review_verdict` /
  `leadv2-review-findings.sh`.
- No new env vars, no new sidecar file formats, no migration of existing `.review-round.state` files
  (a legacy/corrupt file degrades to exhaustive round 1 by design).
- No merge to `main`, no rebase, no worktree cleanup, no touching the other lanes' dirty journals.
- No fix for the pre-existing duplicate-worktree sprawl or the two junk filenames beyond deleting them.

## acceptance:

```yaml
acceptance:
  authored_at: 2026-08-19T10:22:29Z
  items:
    - surface: file_artifact
      observable: >
        Running the critic's five-step repro (fail → fix → verify → re-review the unchanged diff →
        fix) inside the lane worktree, the contents of
        docs/handoff/dispatch-<id>/.review-round.state read round=1, then round=2, then round=2,
        then round=3 — the number a person reads in that file never gets smaller than the one
        before it.
    - surface: rendered_line
      observable: >
        After that same repro, the first line of the generated review mission file reads
        "EXHAUSTIVE ROUND 3" or "VERIFICATION-ONLY ROUND 3" — a person no longer sees the word
        ROUND followed by 1 on the third pass.
    - surface: rendered_line
      observable: >
        In the round-3 mission file, the "Prior findings:" section lists the finding descriptions
        that were recorded in round 2, and none of the round-1 descriptions that were already
        fixed. No line anywhere in that file begins with "count=".
    - surface: log_line
      observable: >
        The task journal's review_round decision line shows prior_findings= followed by the same
        number of findings a person can count in the prior round's gate file, instead of always
        showing prior_findings=0.
    - surface: rendered_line
      observable: >
        With the operator hatch set to round 2 in a fresh handoff that has no recorded prior
        findings, the mission file a person opens is the exhaustive one — it names the four lenses
        and the census rule — rather than a verification-only page with an empty prior-findings
        list.
    - surface: file_artifact
      observable: >
        When the diff file is missing, no .review-round.state file appears in the handoff
        directory afterwards, and the run's stderr shows a shasum failure message instead of
        silence.
    - surface: log_line
      observable: >
        The offline suite output shows the new round-regression, forced-mode, cap, empty-hash and
        corrupt-sidecar tests reported as failing against the pinned baseline tree and passing
        against the working tree, with body-persist 13/0, arm-no-verdict 15/0 and silence-gate
        15/0 all still green.
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-review-run.sh, plugins/leadv2/scripts/tests/test-review-round-exhaustive.sh, plugins/leadv2/scripts/tests/run-core-offline.sh, plugins/leadv2/skills/leadv2-review/SKILL.md

DELIVERABLE_COMPLETE
