REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=0 high=1 medium=4 low=5

# critic — dispatch-02f41cdd (CI-RUNS-THE-SUITES-01, rounds 2+3)

Diff reviewed: `docs/handoff/dispatch-02f41cdd/review.diff` (242 lines, 4 files:
`.gate-seen`, `.github/workflows/test-suites.yml`, `docs/LEAD_V2_STATE.md`,
`tests/run-all.sh`). Lane worktree: `.claude/worktrees/CI-RUNS-THE-SUITES-01`
@ `63471fd6`. Base already contains round 1 (`tests/ci-gate.sh`,
`tests/known-red-suites.txt`, `tests/known-red-guard.sh`) — those are context,
not under review, but I read them because round 3 changes their contract.

## What I verified as correct (so the FAIL is not read as a blanket rejection)

- `tests/run-all.sh` is `set -uo pipefail` with **no** `-e`
  (`tests/run-all.sh:14`), so replacing `if bash "${suite}"; then` with
  `bash …; rc=$?` is safe. No early-exit regression.
- `run-core-offline.sh` really does emit the label the new parser greps for:
  `printf -- '[CORE-OFFLINE] FAILED: %s\n' "$name"`
  (`plugins/leadv2/scripts/tests/run-core-offline.sh:289,302`). The allow-list
  key format `core:<label>` matches the 15 entries in
  `tests/known-red-suites.txt`.
- The allow-list stripping expression in the new `is_known_red()` is
  byte-identical to `is_allowlisted()` in `tests/ci-gate.sh:38-42`, so the two
  consumers cannot disagree on parsing. Good.
- Fail-closed path is real: wrapper fails with zero parsed `FAILED:` lines →
  `KNOWN_NAMES` and `UNEXPECTED_NAMES` both empty → `classified=0` → `[FAIL]` +
  `Failures (blocking)`. Matches the comment at `tests/run-all.sh:137-140`.
- `ci-gate.sh` is not broken by round 3: it only reads `RUN_RC` for the `==2`
  usage check, never parses the `run-all: …` summary line, and its second loop
  already `continue`s past the core-offline wrapper — so the wrapper no longer
  printing `[FAIL]` when everything is allow-listed changes nothing for it.
  The transcript is `cat`-ed verbatim, so ci-gate still sees every
  `[CORE-OFFLINE] FAILED:` line.
- The workflow's central platform claim — "the bash32 suite SKIPs cleanly on
  non-Darwin" — is true: `tests/test-status-surface-bash32.sh:41-44` does
  `[[ "$(uname -s)" != "Darwin" ]] && echo SKIP && exit 0`.

## HIGH

### H1 — the ubuntu-latest migration is unvalidated, and at least one core-offline suite is provably BSD-only → CI is red from birth on the first PR
`.github/workflows/test-suites.yml:39` (and `:79` for the nightly job)

The justification in the diff is: *"The suite tree is written bash-3.2-safe (no
Bash 4+ features — standing repo decision), so bash 5 on ubuntu is a superset."*
That reasoning covers the **shell dialect** and says nothing about the
**userland**. macOS ships BSD `stat`/`date`; ubuntu-latest ships GNU coreutils.
The repo knows this — nearly every call site carries an explicit fallback:

```
tests/test-provider-quota-gate.sh:102
  touch -t "$(date -r "$old_ts" +%Y%m%d%H%M.%S 2>/dev/null \
              || date -d "@${old_ts}" +%Y%m%d%H%M.%S)" …
tests/test-pulse-empty-board.sh:481-482
  … date -j -f … 2>/dev/null || TZ=Europe/Kyiv date -d … +%s
```

`test-plugin-reliability-01.sh` is the one that does **not**:

```
plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh:358-359
  local old_ts=$(( $(date +%s) - 120 ))
  touch -t "$(date -r "$old_ts" +%Y%m%d%H%M.%S)" "$meta" 2>/dev/null || true
```

BSD `date -r <epoch>` = "interpret this integer as an epoch". GNU `date -r` is
`--reference=FILE`, so on ubuntu it stats a file literally named `1756800000`,
fails, and prints nothing; `touch -t ""` then fails and is swallowed by
`|| true`. The file's mtime stays *now*. The very next assertion is:

```
plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh:372-376
  if [[ -z "$status" && -z "$pid" && $_meta_age_s -ge 30 ]]; then
    ok "old meta (>30s) + empty status → dead-eligible"
  else
    fail "old meta + empty status not dead-eligible (age=${_meta_age_s})"
```

→ `age=0` → `fail`. Probe, on this macOS host, showing the two dialects are
mutually exclusive (so the fallback is load-bearing, not decorative):

```
$ date -r 1756800000 +%Y%m%d%H%M.%S      # BSD (macOS)
202509021100.00                          # rc=0
$ date -d "@1756800000" +%Y%m%d%H%M.%S   # GNU form, on macOS
date: illegal option -- d
```

UNVERIFIED-ON-LINUX: I could not execute the GNU branch — this reviewer host is
Darwin only and the diff ships no Linux run. The claim rests on GNU coreutils'
documented `-r, --reference=FILE` semantics plus the in-repo corroboration that
every *other* call site in this tree pairs `date -r <epoch>` with an explicit
`date -d "@…"` fallback. Whichever way that resolves, the diff itself contains
no artifact proving the tree runs on Linux.

Blast radius: that suite is registered in the curated set —
`run-core-offline.sh:394`, label `plugin reliability (process liveness + role
fallback + prepass/reorder signals)` — and it is **not** one of the 15 entries
in `tests/known-red-suites.txt`. So the first PR run produces
`[CORE-OFFLINE] FAILED: plugin reliability …` → `ci-gate.sh` classifies it
`UNEXPECTED` → `exit 1` → the job is red. That is precisely the outcome the
allow-list was built to prevent ("this file exists so the CI job can be green
from birth"), and it will be red on a suite that is green on every developer
machine, which is the worst kind of red to debug. `known-red-guard.sh`
additionally forbids *widening* the list, so the cheap unblock is closed by
design.

Also note `tests/known-red-suites.txt` was measured on macOS (its header says
so). Its 15 entries are a macOS baseline being applied to a Linux run — the
list is neither necessary nor sufficient for the new platform, and nothing in
the diff re-derives it.

Minimum to clear H1 (any one): (a) keep `changed-scope` on `macos-latest` until
a Linux baseline exists; (b) land the one-line GNU fallback in
`test-plugin-reliability-01.sh:359` **and** produce one real ubuntu run
(`workflow_dispatch` on a scratch branch) as the artifact; (c) merge with
`continue-on-error: true` on the ubuntu job for one cycle and re-derive the
allow-list from its output. What is not acceptable is merging a platform switch
whose only evidence is a macOS stopwatch.

## MEDIUM

### M1 — the core-offline transcript is buffered, so a timeout destroys the only diagnostics
`tests/run-all.sh:161-164`

```
suite_log="$(mktemp …)"
bash "${suite}" >"${suite_log}" 2>&1
rc=$?
cat "${suite_log}"
```

Nothing is printed for the ~23 min the wrapper runs, and the `cat` only happens
if the wrapper returns. If `timeout-minutes: 45` fires — the single most likely
outcome on an unmeasured new runner (see H1) — the job is SIGKILLed, the temp
file dies with the runner, and the log shows a 45-minute silence with zero
suite names. The stated need is only to *classify* the labels, which `tee`
satisfies while keeping the stream live; `pipefail` is already set at line 14,
so `bash "${suite}" 2>&1 | tee "${suite_log}"; rc=$?` preserves the suite's exit
code. Compare `ci-gate.sh`, which buffers deliberately but is the outer wrapper
with nothing above it to lose.

### M2 — `path:` allow-list entries are silently ignored by run-all.sh, so ci-gate and the lane gate diverge again
`tests/run-all.sh:141-147, 188-215` vs `tests/known-red-suites.txt` header

The allow-list documents two key forms: `core:<label>` and
`path:<repo-relative suite path>` "for a suite that fails at the top level of
tests/run-all.sh". `is_known_red` is only ever called with `core:${name}`
(line 192) — the top-level `[FAIL]` path at lines 216-218 never consults the
list. `ci-gate.sh:60-76` *does* honour `path:`. So the first `path:` entry
anyone adds will make CI green while `run-all.sh` still exits 1 and still emits
`Failures (blocking)` → the lane still blocks. That is the exact
ci-gate-vs-lane split round 3 was written to close, reintroduced for the other
half of the format. This is latent today (zero `path:` entries) but it is
reachable the moment `--scope changed` stem-matches a suite outside the curated
set — which is the normal case for this job, not an exotic one.

### M3 — the expensive job is the one without `cancel-in-progress`
`.github/workflows/test-suites.yml:46-50` vs `:58-64`

`changed-scope` (ubuntu, 1x billing) gets `concurrency` +
`cancel-in-progress: true` with the rationale "a stale push to the same PR
branch must not stack runs". `bash32-darwin` (macOS, 10x billing) gets neither,
and it also has no `if:`, so it runs on push, PR, schedule *and*
workflow_dispatch. The stated cost rationale for this whole round argues for
the opposite priority: three quick pushes to a PR branch stack three macOS jobs
and cancel two ubuntu ones. Add the same concurrency block (distinct group key)
to `bash32-darwin`.

### M4 — `docs/LEAD_V2_STATE.md` is unrelated shared state carried in a CI diff
`docs/LEAD_V2_STATE.md:4-107` in the diff

The change deletes 8 live session rows and replaces them with one
(`dispatch-9289462d`), plus `Sessions: 8 / 3 max` → `1 / 3 max`. This is
lead-owned shared state, explicitly listed as never-write for lane workers
(subagent protocol §9), it has nothing to do with wiring CI, and committing it
from a lane snapshots one moment and can clobber rows other live lanes own —
the repo currently reports 17 other active sessions. Drop it from the commit
(`git restore` / pathspec-scoped `git add`).

## LOW

- **L1 — `.gate-seen`**: a new empty file at repo root
  (`review.diff:1-3`, mode 100644, `e69de29b` = empty blob). `grep -rn
  "gate-seen"` across `*.sh`/`*.yml`/`*.py`/`.gitignore` in the worktree returns
  nothing — it is referenced by no code and ignored by no rule. Stray artifact;
  delete it or add a `.gitignore` entry.
- **L2 — `KNOWN` counts wrappers, not suites**: `KNOWN=$((KNOWN + 1))`
  (`tests/run-all.sh:203`) increments once per *wrapper*, so with all 15 nested
  reds allow-listed the summary reads `1 known-red`. The per-name
  `    - core:<n>` lines above it are correct; the headline number is not. Use
  `${#KNOWN_NAMES[@]}`.
- **L3 — allow-list header is now stale**: `tests/known-red-suites.txt` still
  says "tests/ci-gate.sh treats any failing suite on this list as a known
  issue". After round 3 the second consumer is `tests/run-all.sh`, which means
  the list now also governs the **lane close gate** (`run-all.sh` is what
  `leadv2-dispatch-product-close.sh` / `leadv2-phase8-e2e-gate.sh` execute — see
  its own header, lines 2-4). That is a materially wider authority than the file
  documents, and the file's header is the contract a future editor reads.
- **L4 — allow-list re-parsed per failing label**: `is_known_red`
  (`tests/run-all.sh:144-147`) re-reads the file and spawns `grep`+`sed`+`grep`
  in a process substitution on every call — 45 processes for the current 15-red
  baseline. Hoist the normalised list into a variable once.
- **L5 — no trap on the temp file**: `tests/run-all.sh:161`'s `mktemp` is
  removed on both the pass path (line 180) and the classify path (line 211), but
  a Ctrl-C / SIGTERM between them leaks it. `ci-gate.sh:21-22` sets
  `trap 'rm -f "${LOG}"' EXIT` for the same pattern; match it.

## Verdict rationale

FAIL on H1 alone. M1-M4 are all mechanical and cheap; H1 is the one that needs
either a platform artifact or a narrower change. The round-3 `run-all.sh`
classification logic is, on its own, correct and well-guarded — my objection is
to shipping it together with an unmeasured runner swap, because if H1 lands the
first thing it will do is prove the allow-list wrong on a platform it was never
measured on.

DELIVERABLE_COMPLETE
