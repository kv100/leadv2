verdict: APPROVE
next_action: review_round_2

# SAFETY-PIN-SECOND-DOOR-01 — developer full report

Full analysis, evidence, and commands are in the lane's own DoD-gated
deliverable: `docs/handoff/SAFETY-PIN-SECOND-DOOR-01/report.md` (committed).
This file is a pointer + condensed trail for the orchestrator; do not
duplicate the pasted probe/test output here — read report.md for that.

## What I found (verdict)

The census's literal citation (`leadv2-admission-class.sh` in
`plugins/leadv2/scripts/` folding risk into class while a "route pin" reads
`RISK_TAGS`) does not exist as described. That admission-class file lives
under `plugins/leadv2/scripts/lib/`, and the "route pin reads RISK_TAGS"
description matches `leadv2-session-route.sh`, which `HEAVY-TIER-VS-SAFETY-OPUS-01`
already fixed. So the literal claim was an artifact of a worker describing
code it hadn't read carefully, exactly as the brief warned.

But the underlying shape — a judge-flagged safety task with no caller
`--safety`/`--risk-tags` escaping safety enforcement — was real by a
different, previously-unexamined path: `leadv2-dispatch-code.sh`'s own
`cmd_resolve` (the worker-arm resolver for code dispatch, a separate router
from `leadv2-session-route.sh`) had no `risk_class` concept at all. The
judge's `risk_class=safety_publish_payments` only escalated `ADMISSION_CLASS`
to Heavy via `lib/leadv2-admission-class.sh`'s map — it never reached the
`safety` local that gates `_build_candidate_chain`'s `require_trusted`
exclusion. Confirmed live (not from reading): dispatched the same scenario
resolve-only against `HEAD~1` (pre-fix) and `HEAD` (post-fix) — pre-fix shows
no `safety_pin_applied` line at all and freepool/glm-flash excluded only for
`reason=arm_not_capable_for_size` (an accident of Heavy-class size
eligibility, not a safety exclusion); post-fix shows `safety_pin_applied`
firing and freepool excluded for `reason=protected_path` unconditionally.
Full pasted transcript: report.md's "Evidence: live probe" section.

## Fix

`plugins/leadv2/scripts/leadv2-dispatch-code.sh` `cmd_resolve`: folds
`ADMISSION_RISK_CLASS` (new output of `_admission_classify`) into the local
`safety` flag unconditionally, before any config/env override read — mirrors
`HEAVY-TIER-VS-SAFETY-OPUS-01` round 2's placement for `CLAUDE_SAFETY_MODEL`,
outside the override surface. Never clears an explicit caller `--safety`.

`plugins/leadv2/scripts/lib/leadv2-admission-class.sh`: receipt gains an
optional 7th tab-delimited `risk_class` field (old receipts read back with
`risk_class=""`, never a hard failure — it's not in the required-keys check).

`arch` carve-out (`HEAVY-TIER-VS-SAFETY-OPUS-01`/fix-round-2.md) is untouched
by construction: that carve-out is entirely inside `leadv2-session-route.sh`'s
`RISK_TAGS` handling; this fix's signal is the judge's own 3-value
`risk_class` enum (`none`/`data`/`safety_publish_payments`), which has no
`arch` value, so no second `arch` rule exists to drift.

## Test coverage

New: `plugins/leadv2/scripts/tests/test-admission-safety-pin.sh`, registered
in `tests/run-all.sh` (self-selecting path + an explicit `EXTRA_SUITE_MAP`
row tying it to both `leadv2-admission-class` and `leadv2-dispatch-code`).
Covers: pin fires with judge-only signal and no caller flag (green);
`risk_class=none` stays silent (baseline/negative control); a mutated
throwaway copy with the fold-in stripped reopens the door (red, via
`leadv2-mutation-control.sh`, not hand-rolled). Also extended
`test-admission-class.sh` with a risk_class receipt round-trip assertion.

`test-session-route.sh` deliberately NOT touched — it owns
`leadv2-session-route.sh`'s tag-based routing only, no `risk_class` concept;
mirroring the brief's literal ask there would have put coverage in the wrong
file and hidden where the actual second door lives. Explained in the new
suite's own header comment and in report.md.

## Cross-platform note (not a regression, pre-existing plumbing)

The same fixed binary takes a different live enforcement path per platform
in this test scenario: macOS resolves via the T17 arbiter
(`arm_excluded ... reason=protected_path`); the Debian container's arbiter
falls back to the legacy v1 ladder (`leadv2-dispatch-code.sh:7574`'s
documented "fail-open on an arbiter fault" fallback) and resolves via
`rule=safety_gate_publish_payments`. Both are real, live-verified enforcement
of the same fix (and both correctly show NO enforcement on the mutated
copy). The new suite's assertion accepts either shape rather than hard-coding
one platform's path — not a weakened assertion, a correctly-scoped one. Root
cause of *why* the arbiter falls back only in the container was not
investigated (out of scope for this lane, pre-existing, does not block the
fix) — flagged in report.md's "What this still does not catch" as a possible
follow-up.

## Verification run (falsification set)

```
$ for f in plugins/leadv2/scripts/leadv2-dispatch-code.sh \
           plugins/leadv2/scripts/lib/leadv2-admission-class.sh \
           plugins/leadv2/scripts/tests/test-admission-class.sh \
           plugins/leadv2/scripts/tests/test-admission-safety-pin.sh \
           tests/run-all.sh; do bash -n "$f"; done
(all rc=0, no output)
```

Both suites, direct + narrow (never a full changed-scope sweep, per this
lane's own instruction — the prior round was killed by the e2e gate on
rc=124/timeout): macOS rc=0/0, Linux container (debian:stable-slim, bash 5 +
git + python3) rc=0/0. Full pasted output: report.md.

DoD gate itself, run standalone (not just claimed):
```
$ bash plugins/leadv2/scripts/lib/leadv2-dod-gate.sh "$(pwd)" \
    "$(pwd)/docs/handoff/SAFETY-PIN-SECOND-DOOR-01" "$DIFF_FILE" "$OUT_MD"
dod_pass check=report
dod_pass check=paste_evidence
dod_pass check=suite_registration
dod_pass check=runtime_state
dod_note check=unverified_claim line=127/129/170/177/189   # report-only, never fails the gate
$ echo $?
0
```

## Left alone / off-limits respected

`main`, `tests/known-red-suites.txt`, `test-session-route.sh` (explained
above), the `arch` carve-out. `docs/leadv2/*`, `docs/LEAD_V2_STATE.md`,
`docs/handoff/dispatch-nw*` show as modified in `git status` but are NOT
part of my diff — pre-existing dirty runtime state in this shared worktree
from concurrent lane activity; never staged or committed by this session
(verified: `git status --short` on `plugins/leadv2/`, `tests/`, and my
handoff dir is clean after each commit).

## Commits (lane branch, this session)

- `eb8a66ab` — the fix itself (dispatch-code.sh, admission-class.sh lib,
  test-admission-class.sh extension, run-all.sh registration, new suite).
- `49539610` — report.md.
- `a8569fa6` — mutation-control artifact (force-added: `docs/handoff/*/*`
  is gitignored by default), diff_hash verified to match a fresh
  `git diff <merge-base main HEAD> HEAD -- . ':(exclude,glob)**/mutation-control/**' | shasum -a 256`
  recomputation after all three commits.

DELIVERABLE_COMPLETE
