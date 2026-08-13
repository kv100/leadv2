# M-8 fix round 1 — architect prepass (scoped implementation design)

Worktree: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/99f0fe0f`, branch
`worktree-99f0fe0f`. No new worktree. No re-architecture. The design and the test suite stand;
this is a defect-repair scope.

## 0. Ground truth measured on THIS machine (2026-08-03T15:46Z, darwin 25.5.0)

```
$ echo "[$(date +%s%3N 2>/dev/null || echo FALLBACK)]"; echo "rc=$?"
[17857718873N]
rc=0
$ command -v gdate  -> /opt/homebrew/bin/gdate
$ perl -MTime::HiRes=time -e 'printf "%d", time*1000'  -> 1785771887212
$ command -v shellcheck -> /opt/homebrew/bin/shellcheck
```

BSD `date` emits the epoch seconds followed by a literal `N` **and exits 0** — confirmed, not
assumed. The `||` fallback in `execute_proof` is therefore dead code.

Current suite result (`bash plugins/leadv2/scripts/tests/test-skill-proof-gate.sh`):
5 FAIL — shellcheck(gate), (a), (b), (c-REFUSED-message), (e)×2.

Direct reproduction of case (a):

```
$ bash plugins/leadv2/scripts/leadv2-skill-proof.sh run --skills-dir .../fixtures/skill-proof/valid-pass
leadv2-skill-proof.sh: line 227: 17857719263N: value too great for base (error token is "17857719263N")
REAL_RC=0
```

No table is printed at all. `bash -x` shows the last two trace lines:

```
+ end_ms=17857719423N
leadv2-skill-proof.sh: line 227: 17857719423N: value too great for base ...
+ exit 0
```

**This is the whole of F3.** The arithmetic error at line 227 is a fatal shell error; bash
unwinds out of `do_run` past the `do_run || exit $?` guard and the script terminates on a
trailing `exit 0`. Every run — pass, fail, mixed — dies at the same point and reports success.
F1 is not merely "masking" F3; on current evidence F1 *is* F3. The developer must re-measure
after fixing F1 before asserting a third bug exists.

## 1. Root causes and the change per cause

### F1 — non-portable millisecond clock (CRITICAL, root of F3)

`plugins/leadv2/scripts/leadv2-skill-proof.sh:218` and `:226`
`start_ms=$(date +%s%3N 2>/dev/null || python3 -c ...)` — the fallback can never fire because
BSD `date` succeeds.

**Change.** Introduce a single `now_ms()` helper in the gate (not in `leadv2-proof-lib.sh` —
that lib is sourced by PROOF.sh files and has a different audience). Contract: prints a
decimal integer of milliseconds since epoch, on any host, or prints nothing.

Selection must be by **validating the output**, never by exit status:

| order | source | accept when |
|---|---|---|
| 1 | `date +%s%3N` | output matches `^[0-9]+$` (GNU/Linux host) |
| 2 | `perl -MTime::HiRes=time -e '...'` | output matches `^[0-9]+$` (verified present here) |
| 3 | `python3 -c 'import time;print(int(time.time()*1000))'` | output matches `^[0-9]+$` |
| 4 | `date +%s` × 1000 | always (second resolution, degraded but never wrong) |

Do **not** reach for `gdate`: it exists on this box via homebrew but is absent on a clean macOS
and on CI, so depending on it re-creates the same class of defect one hop away.

**Defence in depth.** Even with `now_ms()`, `PROOF_DURATION_MS` must never be able to abort the
run. Guard the subtraction: if either endpoint fails the `^[0-9]+$` shape, set
`PROOF_DURATION_MS=0` and continue. A broken clock is a cosmetic loss (the TIME column), never
a gate failure.

**House rule this violates** (record it in the fix): GNU `date` flags — `--date=`, `%N`,
`-d` — are Linux-only; this repo is developed on macOS. Any new `date` use must be shape-checked
or restricted to POSIX `%s` / `-u +%Y-%m-%dT%H:%M:%SZ`.

### F2 — `case "$1"` under `set -u` with no arguments

The mission's reported line 539 fault is currently *shadowed* by the `[[ $# -eq 0 ]]` branch at
`:534`, which routes a bare invocation to `do_run`. That branch is a patch, not the fix: it
duplicates the `do_run || exit $?; exit 0` tail (`:535-536` and `:556-557`) and leaves the
unguarded `case "$1"` one edit away from regressing.

**Change.** Delete the `$# -eq 0` special case and the duplicated tail. Parse with
`case "${1:-run}" in` plus an explicit default arm that does **not** consume the argument, so
`leadv2-skill-proof.sh`, `... run`, and `... --only X` all converge on the same single
`do_run` call site. One entry point, one exit path.

### F3 — exit code always 0 (the lying-green defect, reproduced inside the gate)

Cause established above: fatal-error unwind terminating on a trailing `exit 0`.

**Change (two parts).**

1. Fix F1 + F2. Expect (a)/(b)/(e) to go green on that alone. Re-run and re-measure before
   concluding anything further.
2. **Add a completion sentinel** — this is the one structural addition this round should make,
   because it converts "the gate crashed" from *silent success* into *loud failure*, which is
   the exact invariant M-8 exists to enforce:
   - `RUN_COMPLETED=0` at top scope; `do_run` sets `RUN_COMPLETED=1` on the line immediately
     before its final `return`.
   - `trap '_final' EXIT`, where `_final` captures `$?` and, if the status is 0 while
     `RUN_COMPLETED != 1` and the subcommand is `run`, exits **2** (usage/internal error, per
     the header's documented code table) instead of 0.
   - The trap must not disturb `validate` (0/2/3) or `list` (0) — gate it on the resolved
     subcommand.

   Exit-code contract after the fix (unchanged from the file header, now actually enforced):
   `0` all GREEN · `1` ≥1 RED (no-proof / failed / invalid / never-run) · `2` usage or internal
   abort · `3` `validate` refusal.

### F4 — shellcheck on `leadv2-skill-proof.sh`

Findings today (`shellcheck -f gcc`):

| line | code | finding | disposition |
|---|---|---|---|
| 315 | SC2034 | `exit_code` assigned, never read | **delete the variable** — dead since the state JSON uses `${rc:-0}` |
| 540 | SC2034 | `SUBCOMMAND` assigned, never read | resolve by *using* it: the F3 trap gates on it, and the arg-parse rewrite reads it |
| 541 | SC2317 | `do_validate` arm reported unreachable | artefact of the `exit $?` chain; disappears with the F2 single-exit-path rewrite |

No `# shellcheck disable` is warranted for any of these three. If the rewrite surfaces a new
finding that genuinely needs suppression, it carries an inline comment stating *why* the
checker is wrong — a bare disable is a review block.

### F5 — case (c) "validate should print a REFUSED message" is a **harness** bug, not a gate bug

`test-skill-proof-gate.sh:20` sets `set -euo pipefail`. Line 122 is
`if bash "$GATE" validate ... 2>&1 | grep -qi 'REFUSED'; then`. The gate correctly exits **3**;
under `pipefail` the pipeline's status is 3 regardless of `grep`, so the `if` is false and the
assertion fails even though the message is printed and correct. Sibling assertion (c)-1 already
proves exit 3, and the gate already prints
`[SKILL-PROOF] REFUSED <path> — <rule>: <reason>` at `:525`.

**Change.** Fix the *test*, minimally and visibly:
`out=$(bash "$GATE" validate ... 2>&1) || true` then `grep -qi 'REFUSED' <<<"$out"`.

This is the only permitted edit to the test suite this round, and it must be called out
explicitly in `M8-RESULT.md` with the pipefail explanation. Do **not** weaken any other
assertion, do not relax expected exit codes, do not touch fixtures. Loosening a test to reach
green is the failure mode this whole task exists to prevent; if any *other* assertion resists,
report BLOCKED rather than edit it.

## 2. Files

| path | action |
|---|---|
| `plugins/leadv2/scripts/leadv2-skill-proof.sh` | `now_ms()` + shape-guarded duration (F1); arg-parse rewrite, single exit path (F2); `RUN_COMPLETED` sentinel + EXIT trap (F3); shellcheck cleanup (F4) |
| `plugins/leadv2/scripts/tests/test-skill-proof-gate.sh` | one-line pipefail fix at the (c) REFUSED assertion only (F5) |
| `plugins/leadv2/docs/skill-proof-dod.md` | note the portable-clock rule and the enforced exit-code table |
| `M8-RESULT.md` (repo root, to-create) | PASS/FAIL/BLOCKED per item, changed paths, commit SHA, raw command output |

Not written, but touched at runtime and worth confirming ignored:
`plugins/leadv2/state/skill-proof-state.json` (`LEADV2_SKILL_PROOF_STATE` overrides it; check the
new `plugins/leadv2/.gitignore` covers it so the gate run does not dirty the tree).

## 3. Verification sequence (run in this order; paste raw output for each)

1. `shellcheck plugins/leadv2/scripts/leadv2-skill-proof.sh` → clean.
2. `bash plugins/leadv2/scripts/tests/test-skill-proof-gate.sh` → all PASS, exit 0.
3. `bash plugins/leadv2/scripts/leadv2-skill-proof.sh; echo "rc=$?"` (bare, no subcommand) on the
   real skills tree → table, `green=3`, remainder `RED-NO-PROOF`, **`rc=1`**.
4. **The acceptance item never yet demonstrated — the proof must be able to go red.**
   Break `leadv2-memory-gc`'s batched-verdict path in the skill it proves, run
   `bash plugins/leadv2/skills/leadv2-memory-gc/PROOF.sh` → `[PROOF-FAIL] …`, non-zero.
   Restore via `git checkout --` (never a hand-retype), re-run → exit 0.
   Paste all four outputs. A proof that stays green against broken code is worthless.
   Confirm `git status` is clean of the temporary break before committing.
5. `bash plugins/leadv2/scripts/tests/run-core-offline.sh` → no worse than main (22/0).
   `test-no-work-terminal.sh` is known load-flaky under the full parallel run: if it alone
   fails, re-run it in isolation and report both results rather than chasing it.
6. Commit in this worktree. Record the SHA in `M8-RESULT.md`.

## 4. Risks

| risk | mitigation |
|---|---|
| Developer "fixes" F3 by adding `|| exit 1` sprinkles instead of the sentinel | The sentinel is one variable + one trap; require it in review. Sprinkles leave the crash path silent. |
| `perl` absent on some target host | Tier 4 (`date +%s` × 1000) always succeeds; duration degrades to second resolution, gate verdict unaffected. |
| Fixing shellcheck by suppression | Each of the three findings has a real fix above. Any `disable` needs an inline justification or it blocks. |
| The (c) test edit read as test-weakening | It strictly *strengthens* observability (asserts the message, previously unassertable). Explain pipefail in `M8-RESULT.md`. |
| Break/restore of `leadv2-memory-gc` accidentally committed | Restore with `git checkout --`, then `git status --short` before `git add`; the reviewer checks the diff contains no memory-gc change. |
| Gate run dirties the worktree via the state file | Verify `.gitignore` coverage, or export `LEADV2_SKILL_PROOF_STATE` to a tmp path for step 3. |
| A third bug hides behind F1 | Step 2 is re-measured *after* F1/F2, not predicted. If (a)/(b)/(e) still fail, diagnose fresh with `bash -x` — do not assume. |

## 5. Non-goals (explicitly out of scope)

- No new worktree; no branch change.
- No change to the tautology rules T1/T2/T5/T8 or to `validate_proof` semantics.
- No change to `leadv2-proof-lib.sh` (it already passes shellcheck and is the wrong home for
  `now_ms`).
- No new PROOF.sh files, no change to what the three existing proofs assert (the break/restore
  in step 4 is temporary and must end restored).
- No `--json` output mode, no CI wiring, no state-schema change.
- No edits under `docs/leadv2/` or `docs/handoff/`.
- No test-suite edits beyond the single (c) pipefail line.

## 6. Acceptance

```
acceptance:
  - surface: rendered_line
    observable: >
      Running the gate with no arguments on the real skills tree prints the bordered
      SKILL/STATUS/TIME/REASON table followed by a summary line reading
      "green=3 red=<n> (no-proof=<n> failed=0 invalid=0 never-run=0) skills=<n>",
      with three skills shown as GREEN and every remaining skill as RED-NO-PROOF, and the
      shell's next prompt reports a non-zero exit status.
    authored_at: 2026-08-03T15:46:22Z
  - surface: rendered_line
    observable: >
      The gate test suite prints a PASS line for every case a through g including
      "shellcheck: leadv2-skill-proof.sh", with no FAIL line anywhere in the output, and
      terminates with exit status 0.
    authored_at: 2026-08-03T15:46:22Z
  - surface: log_line
    observable: >
      With the leadv2-memory-gc batched-verdict path deliberately broken, that skill's PROOF.sh
      prints a line beginning "[PROOF-FAIL]" naming the failed assertion and exits non-zero;
      after the break is reverted the same PROOF.sh prints no [PROOF-FAIL] line and exits 0.
    authored_at: 2026-08-03T15:46:22Z
  - surface: rendered_line
    observable: >
      No line of gate output anywhere contains the text "value too great for base", and no line
      contains "unbound variable".
    authored_at: 2026-08-03T15:46:22Z
  - surface: rendered_line
    observable: >
      run-core-offline.sh prints a final tally of 22 passed and 0 failed, matching main; if
      test-no-work-terminal.sh is the sole failure it is shown passing in an isolated re-run.
    authored_at: 2026-08-03T15:46:22Z
  - surface: file_artifact
    observable: >
      M8-RESULT.md exists at the worktree root and shows, for each of F1 through F5 and each
      verification step, a PASS/FAIL/BLOCKED verdict, the changed paths, the commit SHA, and the
      verbatim pasted output of the command that produced the verdict.
    authored_at: 2026-08-03T15:46:22Z
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-skill-proof.sh, plugins/leadv2/scripts/tests/test-skill-proof-gate.sh, plugins/leadv2/docs/skill-proof-dod.md, M8-RESULT.md

DELIVERABLE_COMPLETE
