verdict: APPROVE
next_action: review_round_2

# CI-SUITES-ARE-MACOS-ONLY-01 / dispatch-395cf9b2 — resume after crash

## Starting state

`docs/handoff/RESUME-20260903/_shared.md` and `docs/handoff/dispatch-395cf9b2/context.yaml`
named in the mission did not exist on disk when this session started — proceeded from the
mission text and the branch's own git history instead. The branch already carried one commit
from a crashed prior session (`d5839637`, "portable mktemp across the 10-site census + fix the
guard itself") plus 6 real, uncommitted fixes sitting dirty in the working tree, discovered via
`git status`/`git diff`. Treated resuming and finishing that uncommitted work as the task, per
the mission's "продолжение после падения" framing.

## What was uncommitted and what I did with each file

1. `leadv2-dispatch-ledger.sh` — `liv_map="$(mktemp 2>/dev/null || mktemp "${TMPDIR:-/tmp}/liv.XXXXXX" 2>/dev/null || true)"`.
   Verified the double-failure empty-string case is handled downstream: line 1068's write is
   `2>/dev/null || true` (no-ops on empty path), lines 1116/1170 both guard with
   `[[ -n "${liv_map}" && -f "${liv_map}" ]]`. Correct, kept as-is.
2. `leadv2-lanes.sh` — hard error + exit 1 on mktemp failure for the ps-snapshot tmpfile. Correct,
   kept.
3. `leadv2-proof-lib.sh` — `proof_tmpdir()` now hard-fails with a message instead of silently
   invoking the BSD form. Correct, kept.
4. `leadv2-skill-proof.sh` — replaced the `${VAR:-$(mktemp -d -t ...)}` inline default (which had
   no error handling) with an explicit `if [[ -z ]]; then ... || { echo ...; exit 1; } fi` block.
   Correct, kept.
5. `leadv2-status-surface.5s.sh` — this is the file the *previous commit's own message* flagged as
   "Not fixed (outside LANE_WRITES)": `leadv2-status-surface.5s.sh:331` had the same unguarded
   `mktemp -t leadv2-ss-err`. The uncommitted diff fixes it AND, because this is a SwiftBar
   plugin that must never crash the menu bar, degrades to a formatted `⚠️ leadv2 status` /
   `mktemp failed` line instead of a hard exit. Correct, kept — this closes the gap the prior
   round explicitly left open.
6. `leadv2-lane-status-line-tail.sh` — **initially treated as scope creep and reverted.** This
   file has zero `mktemp` usage; the diff instead changes how `BASE` is parsed out of
   `PREV_CACHED` (`_flicker_sep`-suffix-match -> `${PREV_CACHED#* | }`-prefix-match). No test in
   the repo references `_flicker_sep` or `PREV_CACHED` by name, and CLAUDE.md is explicit about
   not carrying unrequested changes. Reverted it via `git checkout --` and ran the always-on
   status-surface suites to confirm nothing needed it.
   **That check proved me wrong**: `tests/test-status-surface-batch01.sh` T1 ("FLICKER — failed
   user command preserves previous BASE") went from 6 passed/0 failed to 5 passed/1 failed the
   moment the file was reverted, failing with a garbled `BASE` value. Restored the file from a
   `/tmp` backup taken before reverting, reran — 6/0 again. Concluded this fix is a genuine,
   load-bearing part of the crashed session's work (most likely surfaced by running the very
   suite this task cares about) and included it in the commit, documented in the commit message
   as restored-after-verification rather than silently folded in.

## New deliverable: plugins/leadv2/scripts/tests/test-mktemp-guard.sh

Acceptance required either a red-to-green suite or a new suite that catches the described defect
with a negative control (mutation into the function body, a baseline_rc/mutated_rc pair, a red
line), registered so `--scope changed` selects it.

No `leadv2-mutation-control.sh` script exists anywhere in this repo (checked via `find`) — the
mission text mentioning it appears to be boilerplate shared across sibling CI-suite lanes, not a
real entity here (6.6 unrecognized-entity rule: verified absent, did not invent a variant).
Built the mutation control directly into the new suite instead, following the existing convention
in `test-cache-truth.sh` (control_not_applied guard + explicit MUTANT file + baseline vs mutant
comparison).

Coverage (`SCRIPT_DIR`/`SCRIPTS_DIR`/`pass`/`fail` conventions copied from
`test-skill-proof-gate.sh`):
- R1: bare `mktemp -t name` (no XXX) → guard fires, exit 1.
- R2: `mktemp -d -t name` — **the actual incident pattern** — guard fires, exit 1. (This is the
  shape the pre-fix regex in `mktemp-guard.sh` silently missed; the commit message for
  `d5839637` documents this as one of the two real bugs found while wiring the guard in.)
- R3: portable form `mktemp -d "${TMPDIR:-/tmp}/name.XXXXXX"` → silent, exit 0.
- R4: `-t name.XXXXXX.json` (XXX present even with `-t`) → silent, exit 0.
- R5: guard does not trip a caller's `set -e` on the clean path — regression test for the
  *second* historic bug (`line=$(pipeline)` outside an `if` tripping `set -e` when grep finds
  nothing).
- R6 MUTATION CONTROL: reverts the guard's detection regex, via an exact python3 literal-line
  replace (not sed-on-a-regex, which would need its own fragile regex-of-a-regex given the real
  line is full of `[`, `]`, `(`, `)`, `\b`, `$`), to the historic pre-fix pattern that matched
  bare `mktemp -t` but never `mktemp -d -t`. Verifies the mutation actually applied
  (`control_not_applied` fail-loud path if the anchor line isn't found or the mutant is byte-
  identical to the real guard) before trusting the comparison. Runs the R2 incident fixture
  through both: `baseline_rc=1` (real, fixed guard catches it) vs `mutated_rc=0` (reverted guard
  goes blind on it) — this divergence is the required "red line" proof that the suite is
  sensitive to the actual defect, not just asserting prose.

Registered as `mktemp-guard.sh:plugins/leadv2/scripts/tests/test-mktemp-guard.sh` in
`tests/run-all.sh`'s `EXTRA_SUITE_MAP` (belt), and — because it's itself a new `test-*.sh` file —
self-selects under `--scope changed` via the existing "a changed test suite must select itself"
rule at `tests/run-all.sh:366-372` (suspenders). Read the actual `--scope changed` diff logic in
`tests/run-all.sh` end-to-end before relying on either path (line/anchor references above are
from the file as read this session).

## Verification (raw output)

### bash -n — every changed file, macOS host

```
OK plugins/leadv2/scripts/leadv2-dispatch-ledger.sh
OK plugins/leadv2/scripts/leadv2-lanes.sh
OK plugins/leadv2/scripts/leadv2-proof-lib.sh
OK plugins/leadv2/scripts/leadv2-skill-proof.sh
OK plugins/leadv2/scripts/leadv2-status-surface.5s.sh
OK plugins/leadv2/scripts/tests/test-mktemp-guard.sh
OK tests/run-all.sh
```
(`leadv2-lane-status-line-tail.sh` checked separately, also OK.)

### test-mktemp-guard.sh — macOS (bash 5, BSD mktemp)

```
[TEST] PASS: bash -n: mktemp-guard.sh
[TEST] PASS: R1: guard fires on bare 'mktemp -t name'
[TEST] PASS: R2: guard fires on 'mktemp -d -t name' (incident pattern)
[TEST] PASS: R3: guard is silent on the portable form
[TEST] PASS: R4: guard is silent on '-t name.XXXXXX.json'
[TEST] PASS: R5: guard does not trip caller's 'set -e' on the clean path
[TEST] R6 MUTATION CONTROL: baseline_rc=1 mutated_rc=0
[TEST] PASS: R6 MUTATION CONTROL: mutant (bare -t only regex) goes blind on 'mktemp -d -t' -- baseline_rc=1 mutated_rc=0, control proven red-capable
[TEST] ----
[TEST] PASS=7 FAIL=0
EXIT=0
```

### test-mktemp-guard.sh — Linux (Docker `python:3.12-slim`, non-root, GNU coreutils 9.7)

```
[TEST] PASS: bash -n: mktemp-guard.sh
[TEST] PASS: R1: guard fires on bare 'mktemp -t name'
[TEST] PASS: R2: guard fires on 'mktemp -d -t name' (incident pattern)
[TEST] PASS: R3: guard is silent on the portable form
[TEST] PASS: R4: guard is silent on '-t name.XXXXXX.json'
[TEST] PASS: R5: guard does not trip caller's 'set -e' on the clean path
[TEST] R6 MUTATION CONTROL: baseline_rc=1 mutated_rc=0
[TEST] PASS: R6 MUTATION CONTROL: mutant (bare -t only regex) goes blind on 'mktemp -d -t' -- baseline_rc=1 mutated_rc=0, control proven red-capable
[TEST] ----
[TEST] PASS=7 FAIL=0
MKTEMP_GUARD_RC=0
mktemp (GNU coreutils) 9.7
```

### Direct incident reproduction — Linux, real GNU mktemp (evidence for the whole census, not just the new suite)

```
--- BSD-only form on GNU (reproduces the incident) ---
rc=1 FIX=[mktemp: too few X's in template 'leadv2-batch01']
--- portable form (the fix) ---
rc=0 FIX2=[/tmp/leadv2-batch01.rL7mNB]
```

### Other affected suites — macOS

```
test-skill-proof-gate.sh:  PASS=16 FAIL=0, rc=0
test-close-chain.sh:       18 passed, 0 failed, rc=0
test-lane-close-loop.sh:   pass=9 fail=0, rc=0  (ALL GREEN)
test-leadv2-lanes.sh:      all PASS (rc=0), "founder lane view: 15 checks passed"
test-status-surface-single-lead.sh:  23 passed, 0 failed, rc=0
test-status-surface-fast-names.sh:   12 passed, 0 failed, rc=0
  (first attempt under heavy concurrent load: 11/1, "warm render too slow
  (wall 2s)" — a perf-threshold flake, not a real failure; reran clean)
test-status-surface-batch01.sh:      6 passed, 0 failed, rc=0
  (first attempt with lane-status-line-tail.sh reverted: 5/1, T1 FLICKER
  failed with a garbled BASE — this is what proved fix #6 above load-bearing)
```

### Other affected suites — Linux (Docker, same image)

```
test-skill-proof-gate.sh:  PASS=14 FAIL=0, rc=0
  (2 fewer than macOS's 16 — shellcheck is not installed in the container,
  so its 2 shellcheck assertions don't run; not a suite failure)
test-leadv2-lanes.sh:      all PASS, rc=0
```

## Finding left open, not fixed

`tests/test-status-surface-bash32.sh` T3 ("env -i minimal PATH ... renders lanes") intermittently
exceeds a 240-300s wrapper timeout when run as part of the full suite on this machine. Isolated
the exact command T3 runs:

```
env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin LEADV2_STATUS_SYNC=1 \
  /bin/bash plugins/leadv2/scripts/leadv2-status-surface.5s.sh
```

Run standalone: completes in **47s wall** (8.36s user + 2.65s system, 23% CPU — waiting, not
spinning), `rc=0`, real lane rows rendered. The `docs/leadv2/*.lock` files were already showing as
modified in `git status` before this session touched anything (see the git status block at the
top of the session), which is consistent with real contention from the ~15+ other concurrently
active leadv2 sessions on this host (visible in `[LEADV2_ACTIVE_OTHER_SESSIONS]`) rather than
anything in this diff. Per "never weaken a fixture to get green" / "an environment-sensitive
failure is a finding, not a test bug," left the test untouched and reporting this as a finding for
the lead rather than a defect to fix here.

## Files NOT touched

- `docs/leadv2/*`, `docs/LEAD_V2_STATE.md`, `docs/handoff/dispatch-nw*/**` — all showed as dirty
  in `git status` from the start of this session (other concurrent lanes writing shared runtime
  state), explicitly excluded from `git add`/commit per the DoD gate's rule (d) and the mission's
  writable-scope rule (state files are lead-owned).
- `docs/leadv2/.compact-freeze.md`, `docs/leadv2/questions` — untracked files present at session
  start, not created by this session, left alone.

## Commit

`43e8856b665a87a680d19c7220ac08d6f07c8cab` on `worktree-CI-SUITES-ARE-MACOS-ONLY-01`, 8 files
changed (the 6 fixes + `tests/run-all.sh` EXTRA_SUITE_MAP row + the new
`test-mktemp-guard.sh`), no runtime-state paths included.

DELIVERABLE_COMPLETE
