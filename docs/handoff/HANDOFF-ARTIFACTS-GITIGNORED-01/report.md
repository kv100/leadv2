# HANDOFF-ARTIFACTS-GITIGNORED-01 — report

## What changed

`.gitignore` kept the blanket `docs/handoff/*/*` rule (HANDOFF-AND-STATE-NOISE-01,
2026-08-21) but added three negation lines directly under it:

```
docs/handoff/*/*
!docs/handoff/*/report.md
!docs/handoff/*/brief*.md
!docs/handoff/*/round*-red
```

Everything under `docs/handoff/<id>/` still default-ignores (per-run scratch:
`*.stream.jsonl`, `costs.yaml`, `sessions.map`, `.cost-flush.lock`, `*.log`,
`architect-prepass.md.sig`, `context.yaml`, deliverable `*.full.md`/`*.summary.md`,
etc. — hundreds of distinct names, none of them the evidence this task is about).
Un-ignored, and therefore addable with a plain `git add <file>` (no `-f`):

- `report.md` — the lane's closing report (this file)
- `brief*.md` — the brief the lane was given (matches `brief.md`)
- `round*-red` — any `roundN-red/` directory and everything inside it (the only
  durable evidence a negative control went RED)

Kept ignored deliberately: `*.summary.md`/`*.full.md` subagent deliverables,
`context.yaml`, `mission.md`/`lane-mission.md`, stream logs, session maps, locks,
stamps, regenerated `review.diff`. The task's "at minimum" list names exactly
`report.md`, the brief, and `roundN-red/`; widening the allowlist further is a
separate, reviewable call (same reasoning HANDOFF-AND-STATE-NOISE-01 gave for
leaving the 291 already-tracked task journals alone).

`tests/run-all.sh` gained:
- an `EXTRA_SUITE_MAP` row: `gitignore:plugins/leadv2/scripts/tests/test-handoff-artifacts-tracked.sh`
- a synthetic `stem="gitignore"` branch in the `--scope changed` loop, since
  `.gitignore` isn't a `plugins/leadv2/scripts/*.sh` file and the existing loop only
  ever computed a stem from that glob. Proven live (see below): with `.gitignore`
  as the only uncommitted change relative to `HEAD`, sourcing `run-all.sh`'s
  selection logic (lines 1–165, unmodified) and printing `${SUITES[@]}` shows
  `test-handoff-artifacts-tracked.sh` selected alongside the always-on suites.

## Second-order fix confirmed

Because `docs/handoff/*/*` previously ignored everything, deleting a tracked
proof artifact was invisible in `git status`. With the allowlist in place, a
committed `round1-red/output.txt` that gets `rm`'d shows `D
docs/handoff/<id>/round1-red/output.txt` in `git status --short` (acceptance
check 4, GREEN — see test output below).

## Test suite

`plugins/leadv2/scripts/tests/test-handoff-artifacts-tracked.sh` — builds fixture
repos in `mktemp -d` (never the real repo), copies the **real** `.gitignore` from
repo root into each fixture (the file under claim, not a reimplementation), and
asserts on `git check-ignore` / `git add` / `git status` behaviour only — no grep
against `.gitignore` text.

1. `roundN-red/` artifact stages with plain `git add` (no `-f`)
2. `report.md` + `brief.md` stage with plain `git add` (no `-f`)
3. a transient `dispatch.log` stays `check-ignore`d and `git add` no-ops on it
4. deleting a tracked proof artifact shows `D ...` in `git status --short`
5. RED control — strips every `!docs/handoff/*/...` negation line (reproducing
   the pre-fix blanket ignore) and asserts check 1 now fails, proving the
   suite's assertions actually move the exit code

### GREEN (current, fixed .gitignore)

```
PASS: 1: roundN-red/ artifact staged by plain git add (no -f)
PASS: 2: report.md + brief.md staged by plain git add (no -f)
PASS: 3a: transient dispatch.log still matched by check-ignore
PASS: 3b: plain git add is a no-op on ignored dispatch.log
PASS: 4: deleting a tracked proof artifact shows in git status
PASS: RED control: pre-fix blanket-ignore mutation blocks roundN-red git add (control fires, exit code moves)
test-handoff-artifacts-tracked: 6 passed, 0 failed
EXIT=0
```
Verified identically under `/bin/bash` (macOS system bash 3.2.57) and Homebrew bash.

### RED (mutation INSIDE the file under claim: real repo `.gitignore` with the
### three `!docs/handoff/*/...` lines stripped, reverted immediately after)

```
FAIL: 1: roundN-red/ artifact not staged (git add said: ...ignored by one of your .gitignore files...)
FAIL: 2: report.md/brief.md not staged (git add said: ...ignored...)
PASS: 3a: transient dispatch.log still matched by check-ignore
PASS: 3b: plain git add is a no-op on ignored dispatch.log
FAIL: 4: deletion of tracked proof artifact not visible (git status: ?? .gitignore)
PASS: RED control: pre-fix blanket-ignore mutation blocks roundN-red git add (control fires, exit code moves)
test-handoff-artifacts-tracked: 3 passed, 3 failed
EXIT=1
```
Reverted; `git diff --stat -- .gitignore` after revert showed only the intended
12-line addition (no residue from the mutate/revert cycle).

### `--scope changed` selection proof

With `.gitignore` as the sole file differing from `HEAD`, sourcing `tests/run-all.sh`'s
own selection logic (unmodified lines 1–165) and printing the resulting `SUITES`
array:

```
SELECTED:
  .../plugins/leadv2/scripts/tests/run-core-offline.sh
  .../tests/test-status-surface-bash32.sh
  .../tests/test-status-surface-single-lead.sh
  .../tests/test-status-surface-fast-names.sh
  .../plugins/leadv2/scripts/tests/test-handoff-artifacts-tracked.sh
```
The always-on suite (`run-core-offline.sh`, 111 files) makes a full `tests/run-all.sh
--scope changed` run take well over 10 minutes end-to-end in this sandbox, so the
selection step was verified by sourcing the file's own (unedited) selection code
rather than waiting out the full run; `bash -n` and a direct standalone run of the
new suite (above) cover execution correctness.

## Left alone

- No change to any `docs/leadv2/*` or `docs/handoff/dispatch-*/` runtime state files
  that appeared modified in `git status` during this session (concurrent lane/orchestrator
  activity, outside `LANE_WRITES`).
- Did not widen the allowlist beyond `report.md` / `brief*.md` / `round*-red` — see
  "What changed" above for why.
