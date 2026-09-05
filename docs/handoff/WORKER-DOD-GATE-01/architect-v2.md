# WORKER-DOD-GATE-01 — architecture v2 (post-REDESIGN revision)

Deterministic bash definition-of-done gate: runs on a worker's committed lane BEFORE any
model review, on the PRODUCTION path (not only a flag-gated one), refuses the round on a
missing mechanical DoD item, zero model spend.

## §0. Critic resolution table

| CHALLENGE | Verdict addressed | What changed in v2 | Evidence command (cited) |
|---|---|---|---|
| 01 CRITICAL | gate inert in production | Single authoritative gate call moved INTO `leadv2-dispatch-product-close.sh`, inserted before the `LEADV2_REVIEW_ENGINE` branch splits (§2 step [2a]) — runs on both engine=0 (default) and engine=1 paths from one call site | `grep -n 'LEADV2_REVIEW_ENGINE' plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` → line 2756, default `${LEADV2_REVIEW_ENGINE:-0}`; insertion point verified at line 2738-2756 (this task's own read, §8) |
| 02 CRITICAL | 3/8 LANE_WRITES rows fail scoper | `lib/` path fixed (already v1); `plugins/leadv2/prompts/**` row DELETED (superseded by CHALLENGE-17 fix); `docs/handoff/WORKER-DOD-GATE-01/` trailing slash stripped to `docs/handoff/WORKER-DOD-GATE-01`; `_lv2_epilogue_path_in_scope` normalized to strip trailing `/`, `/**`, `/*` before compare (defensive, benefits sibling briefs too) | `grep -n '_lv2_epilogue_path_in_scope' -A9 plugins/leadv2/scripts/lib/leadv2-worker-epilogue.sh` → quoted `case "${path}" in "${lw}"\|"${lw}"/*` confirmed at lines 48-57 |
| 03 CRITICAL | checks read wrong `${HANDOFF}` | dod-gate call site computes `TASK_DIR="${ROOT}/docs/handoff/${FOUNDER_TASK_ID}"` directly at the new pre-branch call in dispatch-product-close.sh (FOUNDER_TASK_ID already a positional param there); review-run.sh gets a NEW `--task-dir` arg for its own defense-in-depth call, never assumes `${HANDOFF}` = task dir | `grep -n 'FOUNDER_TASK_ID=' plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` → `FOUNDER_TASK_ID="${7:-}"` at line 23, in scope at the review section |
| 04 CRITICAL | check (a) refuses 37/37 | regex rewritten to `^#{2,3}[[:space:]].*[Ee]vidence` (case-insensitive, non-anchored); check is conditional on `grep -qi 'report\.md' "${TASK_DIR}/brief.md"` — skipped (not failed) when the brief never asked for one; calibration fixture freezes the 37-report corpus with a 0-false-refusal bar | critic's own run: `grep -h -iE '^#{1,3}[[:space:]].*evidence' docs/handoff/*/report.md` shows real headings are lowercase `evidence` and have trailing parentheticals — both now matched |
| 05 CRITICAL | `git archive` lying-green mutation runner | rewritten §5: (1) baseline-green-first gate, non-green baseline → exit 2 `control_not_applied reason=baseline_not_green`, never `ok`; (2) snapshot the WORKING tree (`git ls-files -co --exclude-standard` + rsync/tar), not `git archive HEAD`; (3) scratch tree gets `git init -q && git add -A && git commit -qm base` for a real git identity, still never `git worktree add` | critic's repro: `git archive HEAD \| tar -x` → no `.git` → `run-all.sh --scope changed` rc=2 "root_escape"; fixed by init+commit in scratch (mirrors `leadv2-suite-falsifiable.sh:29-30`'s rc=2 contract) |
| 06 HIGH | `--dry-run` stateful, poisons selection | `--dry-run` addition to `tests/run-all.sh` DROPPED entirely. Check (c) resolves suite registration IN-PROCESS inside `lib/leadv2-dod-gate.sh` by reading `EXTRA_SUITE_MAP` + the stem convention directly, no shell-out, no state write | `sed -n '316,324p' tests/run-all.sh` (critic's evidence) shows the state write precedes the execution loop — removed as a dependency entirely rather than patched around |
| 07 HIGH | (a)/(b)/(e) gameable by report text | check (b)'s mutation sub-check now requires an ARTIFACT file `${TASK_DIR}/mutation-control/<run-id>.txt` with a `diff_hash` matching the round's `diff_hash` (sha256 of DIFF_FILE) — not a grep for a prose sentinel; check (e) demoted to report-only (never blocking, see CHALLENGE-14) | `sed -n '592,599p' plugins/leadv2/scripts/leadv2-review-run.sh` — `_review_diff_hash()` sha256(DIFF_FILE) pattern reused verbatim |
| 08 HIGH | not portable, check (c) explodes elsewhere | check (c)'s in-process resolution (CHALLENGE-06 fix) makes portability trivial: `tests/run-all.sh` absent → `dod_skip check=suite_registration reason=no_run_all`; no shell-out means no flag-probe needed at all | `grep -c 'dry-run' /Users/kostiantyn.vlasenko/Projects/persona-engine/tests/run-all.sh` → 0 (critic's evidence, now moot since no flag is added) |
| 09 HIGH | soft tier has no reader | `leadv2-lane-outcome.sh` extended to read `worker_dod=` from progress.log/meta.yaml and append `dod=fail:<checks>` to its own status line output — named reader, added to LANE_WRITES | `grep -rn 'progress.log' plugins/leadv2/scripts/leadv2-lane-outcome.sh` (critic's evidence) confirms it already appends to that file; new read added at the same call site |
| 10 HIGH | Option A drops brief item 3 | Option C adopted explicitly (not deferred): shared retry hook `lv2_dod_retry_or_finalize()` added to `lib/leadv2-worker-epilogue.sh` (already shared by all 4 wrappers), each wrapper implements an ≤8-line `retry_hook_fn` feeding failure text into its OWN existing inner turn-loop — no recursive `--resume-lane`, so R5 does not apply | `grep -rn 'leadv2_worker_commit_epilogue' plugins/leadv2/scripts/{glm,kimi,freepool}-coder.sh plugins/leadv2/scripts/claude-subsession.sh` — confirms all 4 already call the SAME shared lib function today, one insertion point extends to all 4 |
| 11 HIGH | write-set collisions understated | `leadv2-review-run.sh` edit reduced to a single `source`-guarded line (mirrors the existing `_REVIEW_REROUTE_NOTE_SH` conditional-source idiom already in the file); `prompts/**` overlap removed by CHALLENGE-17's fix; `tests/run-all.sh` and `plugins/leadv2/scripts/tests/` overlaps named explicitly and raised to HIGH; `dod_*` reason enum handshake requested from REVIEW-SENTINELS-LANGUAGE-01 in report.md, not silently assumed compliant | `head -3 docs/handoff/REVIEW-SENTINELS-LANGUAGE-01/brief.md \| tail -1` (critic's evidence) — LANE_WRITES overlap confirmed on 3 paths, now 3 (prompts/** removed) |
| 12 MEDIUM | (c)/(d) use `main`, not `DIFF_FILE` | both checks now read `DIFF_FILE` exclusively (the round's authoritative diff, already resolved by the caller); standalone invocation without a diff file is `dod_skip`, never falls back to a bare `main` | `sed -n '1314,1316p' plugins/leadv2/scripts/leadv2-review-run.sh` — falsifiability gate's own `${DIFF_FILE}`-only pattern adopted verbatim |
| 13 MEDIUM | exit 8 mislabels ledger cause | NEW exit code 10 reserved exclusively for DoD-undetermined → `_dl_note dead review_dod_blocked`; exit 8 (`review_roundcap`) untouched; exit 7 (`review_verdict_fail`) kept for dod hard-fail (uncontested by critic) | `sed -n '2775,2777p' plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` (critic's evidence) — case statement now editable since the file is in LANE_WRITES (CHALLENGE-01 fix) |
| 14 MEDIUM | check (e) 19% false-refusal, duplicates model rule | check (e) is report-only, writes to `dod-gate.md` only, NEVER contributes to `rc` | critic's own measurement: `check_e_would_refuse=7` of 37 — accepted as advisory-only signal |
| 15 MEDIUM | test coverage short of brief demand | plan step 8 enumerates one negative control per check (a-e), the review-run/product-close refusal path, every rc=2/`dod_skip` path per check, and all 3 `mutation-control` exit-2 sub-reasons — each named, each required to RUN red before `report.md` is written | brief item 4's literal text quoted in plan step 8 |
| 16 LOW | check (b) heuristic unfalsifiable | corpus + numeric bar stated: the 37-report snapshot + their brief.md paste-lines, target ≤15% false-refusal rate, measured and recorded in `report.md`; threshold documented as a tunable, never silently changed | critic's own corpus (`docs/handoff/*/report.md`, 37 files) adopted as the calibration fixture |
| 17 LOW | `prompts/**` wiring unverified | `plugins/leadv2/prompts/**` DROPPED from LANE_WRITES; new readonly string `_LEADV2_DOD_GATE_CONTRACT_MISSION` added to `plugins/leadv2/scripts/leadv2-helpers.sh`, same pattern/file as the proven `_LEADV2_EVIDENCE_CONTRACT_MISSION` | `sed -n '55,70p' plugins/leadv2/scripts/leadv2-helpers.sh` — confirmed readonly-string precedent at lines 62-66, reused verbatim |

## 1. Layers affected

| Layer | Files | Nature of change |
|---|---|---|
| Production review gate (HARD, unconditional) | `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` | **NEW** — additive block before the `LEADV2_REVIEW_ENGINE` branch splits; this is the fix for CHALLENGE-01 and requires extending LANE_WRITES (was off-limits in v1) |
| Review engine (defense-in-depth) | `plugins/leadv2/scripts/leadv2-review-run.sh` | additive, single `source`-guarded line, mirrors falsifiability gate's neighborhood |
| Worker finalize + retry | `plugins/leadv2/scripts/lib/leadv2-worker-epilogue.sh` | additive: soft DoD probe (unchanged from v1) PLUS new `lv2_dod_retry_or_finalize()` shared retry contract (Option C) |
| Coder wrappers (retry hooks) | `plugins/leadv2/scripts/glm-coder.sh`, `kimi-coder.sh`, `freepool-coder.sh`, `plugins/leadv2/scripts/claude-subsession.sh` | **NEW**, small (≤8 lines each): implement `retry_hook_fn` feeding DoD failure text into each wrapper's own existing turn loop |
| New library | `plugins/leadv2/scripts/lib/leadv2-dod-gate.sh` (to-create) | 5 checks (a hard: report; b hard: paste+mutation-artifact; c hard: suite registration, in-process; d hard: runtime-state; e soft: claims), callable standalone or from either gate layer |
| New tool | `plugins/leadv2/scripts/leadv2-mutation-control.sh` (to-create) | scratch-tree mutation runner, baseline-green-gated, working-tree snapshot |
| Worker-facing contract text | `plugins/leadv2/scripts/leadv2-helpers.sh` | **NEW** readonly string `_LEADV2_DOD_GATE_CONTRACT_MISSION`, same pattern as `_LEADV2_EVIDENCE_CONTRACT_MISSION` (replaces the `prompts/**` row) |
| Soft-signal reader | `plugins/leadv2/scripts/leadv2-lane-outcome.sh` | **NEW** — reads `worker_dod=` and surfaces `dod=fail:<checks>` on its status line |
| Ledger cause | `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` (same file as row 1) | **NEW** case-statement arm `10) _dl_note dead review_dod_blocked` |
| Tests | `plugins/leadv2/scripts/tests/test-worker-dod-gate.sh` (to-create) | fixture-per-check + mutation-control cases + refusal-path + rc=2 paths |
| Test scope registry | `tests/run-all.sh` | additive `EXTRA_SUITE_MAP` rows only — no `--dry-run` flag (dropped, CHALLENGE-06) |
| Not touched | `lib/leadv2-land.sh` | confirmed absent; extension point noted, not fabricated |
| Not touched | REVIEW-SENTINELS-LANGUAGE-01's parser file itself | this task requests a `dod_*` reason-enum handshake via `report.md`, does not edit the parser |

DB / Supabase / migrations: **N/A.** Entirely plugin-tooling bash.

## 2. Data flow (numbered)

```
worker turn(s) run in lane worktree
        |
        v
[1] leadv2_worker_commit_epilogue() (lib/leadv2-worker-epilogue.sh) — UNCHANGED from v1
        - auto-commits LANE_WRITES-scoped dirty files
        |
        v
[1a] NEW: lv2_dod_retry_or_finalize() (lib/leadv2-worker-epilogue.sh), called by each
     coder wrapper right after [1]
        - runs lib/leadv2-dod-gate.sh (hard mode) against the just-committed HEAD
        - PASS -> writes worker_dod=pass to progress.log, returns 0
        - FAIL, attempt < LEADV2_DOD_GATE_MAX_RETRIES:-2 -> calls the wrapper's own
          retry_hook_fn with the gate's reason lines, increments
          ${TASK_DIR}/.dod-attempt, returns 0 (wrapper loops for one more worker turn
          using ITS OWN existing continuation mechanism -- no recursive dispatch)
        - FAIL, attempts exhausted -> writes worker_dod=fail:<checks> to progress.log,
          returns 0 (wrapper proceeds to its normal finalize/exit; this is a SOFT
          signal only -- the HARD refusal happens at [2a])
        |
        v
[2] leadv2-dispatch-product-close.sh
        - builder-selfcheck (existing, unchanged) -> selfcheck.md
        - _stamp_active_phase / phase-record "review" (existing, unchanged, ~line 2735-2738)
        |
        v
[2a] NEW: lv2_dod_gate_run() called DIRECTLY here, BEFORE the LEADV2_REVIEW_ENGINE
     branch (line 2756) -- runs unconditionally regardless of the flag's value
        - TASK_DIR="${ROOT}/docs/handoff/${FOUNDER_TASK_ID}" (FOUNDER_TASK_ID already
          a positional param at this script's line 23)
        - reads DIFF_FILE (the round's authoritative diff, already computed upstream
          as ${diff_file} for the existing pool-resolve/engine call)
        - PASS (rc=0) -> falls through, unchanged, into whichever branch
          LEADV2_REVIEW_ENGINE selects today (engine=1 -> review-run.sh; engine=0,
          the production default -> the existing inline review body) -- THIS is the
          fix for CHALLENGE-01: the gate now runs on the production path regardless
          of the flag
        - FAIL (rc=1) -> writes review-gate.md (status: fail, reason: dod_<check>) to
          TASK_DIR, `_dl_note dead review_dod_fail`, `_stamp_review_terminal fail`,
          exit 7 -- the engine is never invoked, the reviewer pool is never resolved
        - UNDETERMINED (rc=2) -> status: blocked, `_dl_note dead review_dod_blocked`
          (NEW ledger cause, exit 10 -- see CHALLENGE-13), never bucketed under
          review_roundcap
        |
        v
[3] (only reached on DoD PASS) leadv2-review-run.sh, engine=1 path ONLY:
    - re-runs lib/leadv2-dod-gate.sh a SECOND time as defense-in-depth (single
      source-guarded line, same neighborhood as the falsifiability gate,
      after its closing `done < <(...)` at ~line 1318, before
      "# Step 2: pool resolve." at line 1319) -- covers direct/standalone
      review-run.sh invocations that bypass dispatch-product-close.sh entirely
      (tests, future callers); redundant-but-safe on the normal path since [2a]
      already passed
        |
        v
[4] dispatch-product-close.sh's existing case statement (engine=1 path) OR the
    unmodified inline review body (engine=0, production default) proceeds exactly
    as today -- neither is edited beyond the new case-10 arm
```

## 3. Capability census — what already exists and is reused

| Existing primitive | File:line | Reused for |
|---|---|---|
| `LEADV2_REVIEW_ENGINE` flag branch, default 0 | `leadv2-dispatch-product-close.sh:2756` | Confirms both branches must be preceded by one shared gate call ([2a]) rather than duplicated inside each branch |
| `FOUNDER_TASK_ID="${7:-}"` | `leadv2-dispatch-product-close.sh:23` | Resolves the task's real handoff dir at the call site — no new arg-threading needed on the production path (CHALLENGE-03) |
| `_review_diff_hash()` sha256(DIFF_FILE) pattern | `leadv2-review-run.sh:592-599` | Adopted verbatim for the mutation-control artifact's `diff_hash` field and for binding check (b)'s sub-check to the round |
| Falsifiability gate shape (refuse before pool resolve, `status: fail`/`reason:`, exit 7/8, reads `${DIFF_FILE}` not `main`) | `leadv2-review-run.sh:1264-1318` | Exact shape mirrored for both the [2a] hard gate and the [3] defense-in-depth block; its `${DIFF_FILE}`-only sourcing (CHALLENGE-12) is copied, not `git diff main HEAD` |
| `leadv2-suite-falsifiable.sh` exit-code convention (0/1/2/3) + rc=2 "already red at baseline, never a pass" doctrine | `leadv2-suite-falsifiable.sh:23-30` | Adopted verbatim for `lib/leadv2-dod-gate.sh` AND for `leadv2-mutation-control.sh`'s NEW baseline-green-first gate (CHALLENGE-05) |
| `mktemp -d` + `trap 'rm -rf "${WORK}"' EXIT` | `leadv2-suite-falsifiable.sh:62-64` | Adopted for `leadv2-mutation-control.sh`'s scratch tree |
| `_lv2_epilogue_path_in_scope()` quoted-case scoper | `lib/leadv2-worker-epilogue.sh:48-57` | Normalized in v2 to strip trailing `/`, `/**`, `/*` before the case match (CHALLENGE-02) |
| `leadv2_worker_commit_epilogue()` shared call site across all 4 coder wrappers | `glm-coder.sh:1793`, `kimi-coder.sh:1583`, `freepool-coder.sh:1826`, `claude-subsession.sh:1128,1287` | Confirms one new function in the SAME shared lib (`lv2_dod_retry_or_finalize`) reaches all 4 wrappers from one edit point; only the wrapper-local `retry_hook_fn` body differs per wrapper |
| `_REVIEW_REROUTE_NOTE_SH` conditional-source idiom | `leadv2-dispatch-product-close.sh` (review body, `_REVIEW_REROUTE_NOTE_SH` block) | Mirrored for review-run.sh's [3] block to keep the diff to a single conditional-source line — reduces the REVIEW-SENTINELS-LANGUAGE-01 collision surface (CHALLENGE-11) |
| `_LEADV2_EVIDENCE_CONTRACT_MISSION` readonly string | `leadv2-helpers.sh:62-66` | Pattern copied verbatim for `_LEADV2_DOD_GATE_CONTRACT_MISSION` (CHALLENGE-17), replacing the unwired `prompts/**` row |
| `EXTRA_SUITE_MAP="<stem>:<suite>"` block format | `tests/run-all.sh:100-105` | Read IN-PROCESS by `lib/leadv2-dod-gate.sh` check (c) — no shell-out, no `--dry-run` needed (CHALLENGE-06/08) |
| `leadv2-dispatch-product-close.sh` exit-code case statement (0/6/7/8/9/`*`) | `leadv2-dispatch-product-close.sh:2775-2777` | Gets ONE new arm, `10) review_dod_blocked`, since the file is now in LANE_WRITES (CHALLENGE-13); 7/8/9/`*` untouched |
| `leadv2-lane-outcome.sh` progress.log append pattern | `leadv2-lane-outcome.sh:19,192,195` | Extended (read side) to surface `worker_dod=` as the soft tier's named reader (CHALLENGE-09) |
| Memory: "never `git worktree add`/prune for scratch state" (2026-08-22 lesson) | founder-lesson | Still honored: `leadv2-mutation-control.sh` uses a plain `mktemp -d` + `git init` in the scratch dir, never `git worktree add` |

## 4. Check list — `lib/leadv2-dod-gate.sh`

Function signature:
```
lv2_dod_gate_run <repo_root> <task_dir> <diff_file> <out_md>
# exit 0 = pass (hard checks a-d), 1 = fail (reason: line set), 2 = undetermined, 3 = usage error
# check (e) NEVER affects the exit code -- report-only, written to <out_md> regardless
```

| Check | Mode | Reads | Exact refusal condition | Negative control (fixture) |
|---|---|---|---|---|
| **(a) report exists+committed+headed** | HARD, conditional | `${TASK_DIR}/report.md`; `git -C ROOT show HEAD:docs/handoff/<task>/report.md`; `${TASK_DIR}/brief.md` | Skip entirely (`dod_skip check=report_not_required`) unless `grep -qi 'report\.md' "${TASK_DIR}/brief.md"`. When required: file missing, OR absent at HEAD, OR no line matching `^#{2,3}[[:space:]].*[Ee]vidence` (case-insensitive, non-anchored) → `dod_fail check=report_missing_or_unheaded` | fixture repo, report.md deleted → red; heading changed to `## Round 4 evidence (reconciliation commit)` (real-world shape) → GREEN under new regex; brief without "report.md" mention + no report.md → `dod_skip`, not red |
| **(b) paste-lines answered** | HARD | `${TASK_DIR}/brief.md` lines matching `/[Pp]aste/`; `${TASK_DIR}/report.md` fenced blocks + nearest preceding heading | token-overlap ≥50% (tunable, calibrated against the 37-report corpus, target ≤15% false-refusal — CHALLENGE-16) → `dod_fail check=paste_evidence_missing`. **Sub-check** (mutation lines only): requires the artifact `${TASK_DIR}/mutation-control/<run-id>.txt` to exist AND its `diff_hash` field to equal `sha256(DIFF_FILE)` → missing/mismatched → `dod_fail check=mutation_control_not_via_runner` | fixture: no fenced block → red; block present, no mutation-control artifact → red for sub-check; artifact present but `diff_hash` from a STALE round → red; artifact matching current diff_hash → green |
| **(c) new suites registered** | HARD, portable | `DIFF_FILE` filtered to the falsifiability gate's own suite-path regex (`review-run.sh:1318`); `tests/run-all.sh`'s `EXTRA_SUITE_MAP` block + stem convention, read IN-PROCESS (no shell-out) | any added suite path absent from BOTH the stem-match set and `EXTRA_SUITE_MAP` values → `dod_fail check=suite_unregistered suite=<path>`. `tests/run-all.sh` absent in this repo → `dod_skip check=suite_registration reason=no_run_all` | fixture diff adds a suite with no entry → red; add EXTRA_SUITE_MAP row → green; simulate repo with no `tests/run-all.sh` → `dod_skip` |
| **(d) no runtime-state paths in diff** | HARD, portable | `DIFF_FILE` only, never `main`/`git diff main HEAD` | any path matches `^(docs/leadv2/\|docs/LEAD_V2_STATE\.md$\|docs/handoff/dispatch-nw)` → `dod_fail check=runtime_state_in_diff paths=<csv>`. Extension: source `lib/leadv2-land.sh`'s path-list function if that file exists (confirmed absent today) | fixture diff touching `docs/leadv2/x.yaml` → red; diff without it → green; `DIFF_FILE` unreadable → rc=2 `dod_skip check=runtime_state_undetermined` |
| **(e) external claims carry evidence** | SOFT, report-only | `${TASK_DIR}/report.md`, ±2-line window | no `evidence:`/`UNVERIFIED` within window → written to `dod-gate.md` as `dod_note check=unverified_claim line=<n>`, **never sets rc≠0** | fixture with no evidence line → note appears in dod-gate.md, `lv2_dod_gate_run`'s rc is still 0 for this check alone |

Every hard-check refusal line: `dod_fail check=<name> <key=value ...>` — all failing checks listed, not just the first.

## 5. `leadv2-mutation-control.sh` — contract (v2, rewritten)

```
leadv2-mutation-control.sh <suite> <file> <sed-or-patch> <diff_hash>
# exit 0 = mutation applied, suite went red as required (ok, artifact written)
# exit 1 = mutant_survived -- suite stayed green despite the mutation
# exit 2 = control_not_applied -- reason= baseline_not_green | anchor_count | noop_edit
# exit 3 = usage error
```

Mechanism:
1. `scratch="$(mktemp -d ...)"`, `trap 'rm -rf "${scratch}"' EXIT` — same idiom as
   `leadv2-suite-falsifiable.sh:62-64`.
2. Snapshot the **working tree**, not `HEAD`: `git -C "${ROOT}" ls-files -co
   --exclude-standard -z | xargs -0 tar -cf - -C "${ROOT}" 2>/dev/null | tar -xf -
   -C "${scratch}"` — captures uncommitted suite/mutation-target files the worker is
   still iterating on (fixes CHALLENGE-05's second defect: `git archive HEAD` is
   committed-only).
3. Give the scratch tree a git identity so the 114/310 git-dependent suites run for
   the right reason: `git -C "${scratch}" init -q && git -C "${scratch}" add -A &&
   git -C "${scratch}" -c user.email=dod@local -c user.name=dod commit -qm base`.
   This is a fresh, un-tracked repo — never `git worktree add`, so it registers
   nothing in `.git/worktrees/` and is prune-safe (2026-08-22 lesson still honored).
4. **Baseline-green gate (NEW):** run the target suite UNMUTATED in `${scratch}`
   first. Non-zero rc → exit 2 `control_not_applied reason=baseline_not_green` —
   never `ok`. This is the direct fix for CHALLENGE-05: a scratch tree that cannot
   even run green is `undetermined`, never a false accusation or a false "ok".
5. Anchor check: `grep -c <anchor-pattern>` on the scratch file's ORIGINAL content
   must equal exactly 1 — else exit 2 `control_not_applied reason=anchor_count`. For
   a unified-diff patch: `patch -p1 --dry-run` first, nonzero → same.
6. Apply the mutation; `cmp -s` before/after — identical → exit 2
   `control_not_applied reason=noop_edit`.
7. Run the suite again (mutated). Exit 0 (still green) → mutant_survived: exit 1 with
   the suite's own last output lines. Non-zero → write
   `${TASK_DIR}/mutation-control/<run-id>.txt` with `suite=`, `file=`, `anchor=`,
   `baseline_rc=0`, `mutated_rc=<n>`, `red_line=<first failing assertion>`,
   `diff_hash=<the round's diff_hash, passed in as arg 4>`; print `MUTATION-CONTROL
   ok suite=<path> file=<path> red_line=<line> diff_hash=<hash>`; exit 0.
8. Confirm post-cleanup: `git -C ROOT status --porcelain` empty (proves the mutation
   never touched the lane) — asserted in the test suite, not by the tool itself.

## 6. `tests/run-all.sh` — required change (v2: reduced scope)

No `--dry-run` flag (dropped — CHALLENGE-06/08). The only change to this file is the
**append** of two `EXTRA_SUITE_MAP` rows (§8) registering
`test-worker-dod-gate.sh` against both new scripts. `lib/leadv2-dod-gate.sh` parses
the `EXTRA_SUITE_MAP="..."` block and the stem convention directly from the file's
text — read-only, no state file, no execution, portable to any repo whether or not
it has `tests/run-all.sh` at all (absent → `dod_skip`).

## 7. Retry mechanism — Option C adopted (resolves CHALLENGE-10)

**Decision: Option C, with LANE_WRITES extended to the 4 coder wrappers.** Not
deferred to the lead — the mission explicitly asks for "Option C with extended
LANE_WRITES or a written descope," and Option C is buildable without the
re-entrancy risk (R5) that sank Option B, because it reuses each wrapper's OWN
existing inner turn-loop instead of a recursive `--resume-lane` dispatch.

Contract, added to `lib/leadv2-worker-epilogue.sh` (already shared by all 4
wrappers, per §3's confirmed call sites):
```
lv2_dod_retry_or_finalize <run_dir> <cwd_dir> <task_dir> <retry_hook_fn>
# retry_hook_fn: name of a wrapper-local bash function, signature
#   <retry_hook_fn> "<feedback text: DoD gate failing check reason lines>"
# Contract for retry_hook_fn: feed the text as the NEXT TURN to the SAME worker
# session, using the wrapper's own existing continuation/loop mechanism. Must
# return before this function proceeds -- lv2_dod_retry_or_finalize does not
# itself invoke any model or dispatch process.
```
Behavior: runs `lib/leadv2-dod-gate.sh` (hard mode) against the just-committed
HEAD. PASS → `worker_dod=pass`, return 0. FAIL with
`${task_dir}/.dod-attempt` < `LEADV2_DOD_GATE_MAX_RETRIES:-2` → increments the
counter, calls `retry_hook_fn` with the gate's reason lines, returns 0 (wrapper
gets one more worker turn). FAIL with attempts exhausted → writes
`worker_dod=fail:<checks>` (unchanged soft signal), returns 0 — the wrapper
proceeds to its normal exit; the ACTUAL round refusal and `complete_with_dod_fail`
happen at the hard gate ([2a] in §2), never here.

Each wrapper implements its own ≤8-line `retry_hook_fn` (e.g. `_glm_dod_retry_feed`
in `glm-coder.sh`) that appends the feedback text into whatever mechanism that
wrapper already uses to give the worker "one more turn" (all four are multi-turn
coder wrappers that already loop until the worker emits a terminal marker).

**Risk R9 (new):** this design's discovery budget did not read all 4 wrappers'
internal turn-loop implementations to confirm each already exposes a clean
re-prompt point. The implementer must verify this per-wrapper before wiring — if a
wrapper's loop is NOT re-enterable mid-flight, that wrapper's `retry_hook_fn`
degrades gracefully to a no-op (soft signal only, same as today), never a crash or
a silent skip of the hard gate.

## 8. Wiring — file:line

| Hook | File:line | Shape |
|---|---|---|
| **Hard gate (production, NEW)** | `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh`, inserted after the review-phase-record block (~line 2738) and BEFORE `if [[ "${LEADV2_REVIEW_ENGINE:-0}" == "1" ]]` (line 2756) | `TASK_DIR="${ROOT}/docs/handoff/${FOUNDER_TASK_ID}"`; `bash "${SCRIPT_DIR}/lib/leadv2-dod-gate.sh" "${ROOT}" "${TASK_DIR}" "${diff_file}" "${TASK_DIR}/dod-gate.md"`; rc 0 falls through unchanged; rc 1 → write review-gate.md, `_dl_note dead review_dod_fail`, `_stamp_review_terminal fail`, exit 7; rc 2 → `_dl_note dead review_dod_blocked`, `_stamp_review_terminal blocked`, exit 10 |
| **New ledger cause arm** | `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh`, case statement at line 2775-2777 | append `10) _dl_note dead review_dod_blocked "rc=2"; _stamp_review_terminal blocked ;;` |
| **Defense-in-depth (engine=1 only)** | `plugins/leadv2/scripts/leadv2-review-run.sh`, single conditional-source line after the falsifiability block's closing `done < <(...)` (~line 1318), before `# Step 2: pool resolve.` (line 1319) | `[[ -f "${_DOD_GATE_SH:=${SCRIPT_DIR}/lib/leadv2-dod-gate.sh}" ]] && { bash "${_DOD_GATE_SH}" "${ROOT}" "${TASK_DIR:-${HANDOFF}}" "${DIFF_FILE}" "${HANDOFF}/dod-gate.md" \|\| ...write+exit as above... ; }` — new `--task-dir` arg parsed alongside `--task/--root/--handoff/--diff/--author`; when absent, falls back to `${HANDOFF}` with an explicit `dod_skip check=no_task_dir` note, never a silent assumption |
| **Retry hooks** | `lib/leadv2-worker-epilogue.sh` (new `lv2_dod_retry_or_finalize`); `glm-coder.sh`/`kimi-coder.sh`/`freepool-coder.sh`/`claude-subsession.sh` (new `retry_hook_fn` each, called right after the existing `leadv2_worker_commit_epilogue` call sites at `glm-coder.sh:1793`, `kimi-coder.sh:1583`, `freepool-coder.sh:1826`, `claude-subsession.sh:1128,1287`) | see §7 |
| **Soft-signal reader** | `plugins/leadv2/scripts/leadv2-lane-outcome.sh` | reads `worker_dod=` from progress.log, appends `dod=fail:<checks>` to its status output |
| **Worker-facing contract text** | `plugins/leadv2/scripts/leadv2-helpers.sh`, adjacent to `_LEADV2_EVIDENCE_CONTRACT_MISSION` (lines 62-66) | new readonly `_LEADV2_DOD_GATE_CONTRACT_MISSION` string describing the mutation-control contract + DoD checks, consumed by whichever caller already concatenates the evidence-contract string into worker mission text |
| **Suite registration** | `tests/run-all.sh`, `EXTRA_SUITE_MAP` block (~line 100-105) | append `leadv2-dod-gate.sh:plugins/leadv2/scripts/tests/test-worker-dod-gate.sh` and `leadv2-mutation-control.sh:plugins/leadv2/scripts/tests/test-worker-dod-gate.sh` |

## 9. Output contract — English sentinels

`review-gate.md` (unchanged schema):
```
status: fail
reason: dod_<check>
check: <a|b|c|d short name>
detail: <one line>

<human-readable explanation>
```
`status: blocked` for rc=2/undetermined (exit 10 now, not 8).

`dod-gate.md`: one line per check (a-e), including check (e)'s report-only
`dod_note` lines, written regardless of overall verdict.

**Sentinel handshake request (CHALLENGE-11):** the `dod_*` reason enum —
`dod_report_missing_or_unheaded`, `dod_paste_evidence_missing`,
`dod_mutation_control_not_via_runner`, `dod_suite_unregistered`,
`dod_runtime_state_in_diff`, `dod_skip`/`dod_note` (never a `status:` value) — is
listed in this task's `report.md` as an explicit registration request to
REVIEW-SENTINELS-LANGUAGE-01's parser. This task does not edit that parser (still
out of LANE_WRITES); it is a coordination artifact, not an assumption of
compliance.

`worker_dod=pass|fail:<checks>` in progress.log/meta.yaml — unchanged from v1,
now with `leadv2-lane-outcome.sh` as its named reader (§1, CHALLENGE-09).

## 10. Plan steps

1. **Fix LANE_WRITES and the epilogue scoper normalization.** Reads:
   `docs/handoff/WORKER-DOD-GATE-01/brief.md`, `lib/leadv2-worker-epilogue.sh:48-57`.
   Writes: the task's context.yaml/mission with the corrected 14-row LANE_WRITES
   list (§11's exact rows — `lib/` path, no `prompts/**`, no trailing slash on the
   handoff dir, plus `leadv2-dispatch-product-close.sh`, `leadv2-helpers.sh`,
   `leadv2-lane-outcome.sh`, and the 4 coder wrappers); `lib/leadv2-worker-epilogue.sh`
   itself (normalize `_lv2_epilogue_path_in_scope` to strip trailing `/`, `/**`,
   `/*`). Acceptance (observable): re-running the critic's `/tmp/dodtest.sh`-style
   probe against all 14 rows returns `IN_SCOPE` for every one, including this task's
   own `report.md` path and its own epilogue edit — zero `FOREIGN` rows, printed and
   pasted into report.md.

2. **Add `lib/leadv2-dod-gate.sh` with checks a-e per §4.** Reads: this document §4,
   `leadv2-suite-falsifiable.sh` (exit-code/mktemp conventions), `tests/run-all.sh`
   lines 100-105 (EXTRA_SUITE_MAP block format for in-process check-c parsing).
   Writes: `plugins/leadv2/scripts/lib/leadv2-dod-gate.sh` (new,
   `lv2_dod_gate_run` per §4's signature). Acceptance (observable): against a
   fixture missing report.md with a brief that demands one, returns rc=1 with
   `dod_fail check=report_missing_or_unheaded`; against the SAME fixture with a
   brief that never mentions report.md, returns `dod_skip` for check (a) and rc=0
   overall if no other check fires; against a fully-compliant fixture, rc=0; every
   invocation completes under 5s (timed, printed in the suite's own output).

3. **Rewrite `leadv2-mutation-control.sh` per §5.** Reads: §5's full mechanism spec,
   `leadv2-suite-falsifiable.sh`'s scratch-dir idiom. Writes:
   `plugins/leadv2/scripts/leadv2-mutation-control.sh` (new). Acceptance
   (observable): run against a fixture suite with a DELIBERATELY red-baseline suite
   (setup crashes) → exit 2 `control_not_applied reason=baseline_not_green`; against
   a green-baseline suite + anchor absent → exit 2 `reason=anchor_count`; against a
   green-baseline suite + valid anchor + a mutation the suite's own assertions
   don't cover → exit 1 `mutant_survived`; against a green-baseline suite + valid
   anchor + a mutation the suite DOES cover → exit 0 with `MUTATION-CONTROL ok
   ... diff_hash=<hash>` and the artifact file written under
   `${TASK_DIR}/mutation-control/`. All four RUN, all four pasted with `$?` and
   stdout. Confirm `git -C ROOT status --porcelain` is empty after every run.

4. **Wire the hard gate into `leadv2-dispatch-product-close.sh` (NEW, resolves
   CHALLENGE-01).** Reads: `leadv2-dispatch-product-close.sh:2735-2779` (exact
   insertion neighborhood, this document's §8). Writes:
   `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` — new block BEFORE line
   2756's `if [[ "${LEADV2_REVIEW_ENGINE:-0}" == "1" ]]`, plus the new case-10 arm at
   line ~2777. Acceptance (observable): run the lane's product-close path with
   `LEADV2_REVIEW_ENGINE` UNSET (the production default) against a fixture diff that
   violates check (d) — confirm `review-gate.md` is written with `status: fail
   reason: dod_runtime_state_in_diff` and the process exits 7 WITHOUT ever printing
   any `review_security`/`resolve_review_pool_call`/`REVIEW_ENGINE` log line (grep
   the run's own stderr for their absence) — proves the gate fires on the flag's
   default value, not only when `LEADV2_REVIEW_ENGINE=1`. Repeat with
   `LEADV2_REVIEW_ENGINE=1` set — same refusal, same exit 7, before the engine binary
   is even invoked.

5. **Wire the defense-in-depth block into `leadv2-review-run.sh`.** Reads:
   `leadv2-review-run.sh:1230-1330` (falsifiability gate neighborhood), §8's exact
   single-line shape. Writes: `plugins/leadv2/scripts/leadv2-review-run.sh` (one
   conditional-source line, new `--task-dir` arg in the parser at line ~68-76).
   Acceptance (observable): invoking `leadv2-review-run.sh` directly (bypassing
   dispatch-product-close.sh) with `--task-dir` omitted against a DoD-violating
   fixture → `dod_skip check=no_task_dir` note plus fallback to `${HANDOFF}`-scoped
   checks only (never a crash, never a silent pass); with `--task-dir` supplied →
   full check set runs, `status: fail reason: dod_<check>` written before any
   pool-resolve log line, exit 7.

6. **Wire the retry contract into `lib/leadv2-worker-epilogue.sh` and all 4 coder
   wrappers.** Reads: §7's exact contract, the confirmed call sites at
   `glm-coder.sh:1793`, `kimi-coder.sh:1583`, `freepool-coder.sh:1826`,
   `claude-subsession.sh:1128,1287`. Writes: `lib/leadv2-worker-epilogue.sh` (new
   `lv2_dod_retry_or_finalize`), all 4 wrapper files (new `retry_hook_fn` each, called
   right after the existing epilogue call). Acceptance (observable): against a
   fixture worker session with a DoD-failing commit, each wrapper's retry_hook_fn is
   invoked exactly once (log line asserted), `.dod-attempt` increments to 1, and the
   wrapper's OWN inner loop receives the feedback text (verified by grepping that
   wrapper's own log/transcript for the fed-back reason line) — captured for at
   least glm-coder.sh and claude-subsession.sh as the two most-used arms; the other
   two documented with the SAME assertion shape if their inner loop is confirmed
   re-enterable (R9), else explicitly marked no-op with a comment citing R9.

7. **Add the readonly contract string to `leadv2-helpers.sh`.** Reads:
   `leadv2-helpers.sh:55-70` (exact precedent). Writes:
   `plugins/leadv2/scripts/leadv2-helpers.sh` (new
   `_LEADV2_DOD_GATE_CONTRACT_MISSION` readonly string, same neighborhood as
   `_LEADV2_EVIDENCE_CONTRACT_MISSION`). Acceptance (observable): a worker mission
   assembled through the SAME call site that already includes the evidence-contract
   string now also contains the DoD-gate contract text verbatim — grep the
   assembled mission file for both strings' presence in the same output.

8. **Add `leadv2-lane-outcome.sh` as the soft-tier's reader.** Reads:
   `leadv2-lane-outcome.sh:19,192,195` (progress.log append pattern). Writes:
   `plugins/leadv2/scripts/leadv2-lane-outcome.sh` (new read of `worker_dod=` and
   appended `dod=fail:<checks>` field on its status output). Acceptance
   (observable): run it against a fixture `progress.log` containing
   `worker_dod=fail:paste_evidence_missing` — the status line output gains
   `dod=fail:paste_evidence_missing`; against a `worker_dod=pass` fixture — no
   change to the existing output (regression check).

9. **Build `test-worker-dod-gate.sh` and register it.** Reads: brief.md item 4,
   §4's negative-control column, §5's 4 mutation-control cases, §6's EXTRA_SUITE_MAP
   format. Writes: `plugins/leadv2/scripts/tests/test-worker-dod-gate.sh` (fixtures:
   one red+green pair for checks a-d, one report-only assertion for check e, the 4
   mutation-control exit-code cases from plan step 3, a refusal-path case asserting
   dispatch-product-close.sh exits 7 before any pool-resolve log line with
   `LEADV2_REVIEW_ENGINE` both unset and =1, an rc=2/`dod_skip` case per hard check
   simulating an unreadable/missing input, and a portability case simulating a repo
   with no `tests/run-all.sh`), `tests/run-all.sh` (append the two EXTRA_SUITE_MAP
   rows). Acceptance (observable): `leadv2-suite-falsifiable.sh
   test-worker-dod-gate.sh` exits 0 (verdict: falsifiable); EVERY negative control
   listed above is individually RUN and its red result pasted (not asserted from
   memory) — this is the literal brief item 4 + CHALLENGE-15 requirement; a diff
   touching only `leadv2-mutation-control.sh` causes `tests/run-all.sh --scope
   changed` to list `test-worker-dod-gate.sh` (proves the EXTRA_SUITE_MAP row
   resolves, using the file's EXISTING stateful `--scope changed`, not a new
   `--dry-run`, and run exactly once per verification to avoid CHALLENGE-06's
   state-poisoning trap).

10. **Write `report.md` for THIS task, running its own gate against itself, plus the
    37-report calibration and the sentinel handshake request.** Reads: all artifacts
    above, the 37-report corpus (`docs/handoff/*/report.md`). Writes:
    `docs/handoff/WORKER-DOD-GATE-01/report.md` with a `## Round N evidence` heading
    (lowercase, matching real convention), the cause-row table, the check(a)/(b)
    calibration numbers against the 37-report corpus (target: 0 false refusals for
    (a), ≤15% for (b)), the `dod_*` sentinel-enum handshake request to
    REVIEW-SENTINELS-LANGUAGE-01, and an explicit "what this gate does NOT catch"
    section. Acceptance (observable): running `lib/leadv2-dod-gate.sh` against THIS
    task's own committed diff and report.md returns rc=0 — the invocation and its
    stdout pasted as the closing proof.

## 11. Off-limits (for the implementing agent to ignore/not touch)

- REVIEW-SENTINELS-LANGUAGE-01's own parser/contract file — consume via the
  handshake request in report.md (§9), never edit or duplicate.
- `lib/leadv2-land.sh` — does not exist yet; check (d)'s runtime-state list stays
  hardcoded until that task lands.
- Any model call inside the gate itself — bash + grep + git only, under 5s.
- `leadv2-dispatch-code.sh`'s `--resume-lane` re-entry mechanism — Option C
  deliberately avoids it (that was Option B's rejected mechanism, R5).
- Any coder wrapper's internals BEYOND the ≤8-line `retry_hook_fn` addition — no
  refactor of the wrappers' own turn-loop implementation, only a hook into it.

## 12. Risks

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| R1 | (resolved v1→v2, kept for history) LANE_WRITES path mismatch on the epilogue file | RESOLVED | §11 row 1, plan step 1 |
| R2 | mutation-control scratch tree registering in `.git/worktrees/` | RESOLVED (v1 already avoided `git worktree add`; v2 keeps it, adds `git init` inside the already-isolated scratch dir, which registers nothing external) | §5 step 3 |
| R5 | Option B's recursive `--resume-lane` re-entrancy | AVOIDED BY DESIGN | Option C (§7) never calls dispatch-code.sh recursively |
| R7 | `tests/run-all.sh`/`leadv2-review-run.sh`/`plugins/leadv2/scripts/tests/` write-set overlap with REVIEW-SENTINELS-LANGUAGE-01 and TESTS-POLLUTE-REAL-JOURNAL-01 | HIGH (raised from LOW per CHALLENGE-11) | review-run.sh edit reduced to one conditional-source line; `prompts/**` overlap eliminated; sentinel enum handshaked via report.md, not silently assumed; rebase-before-commit discipline still required, named explicitly to the lead for serialization |
| R8 | Check (e)'s external-claim regex is a fixed list, will miss unseen claim shapes | MEDIUM (unchanged from v1) | living-list posture, extend on human catch; NEVER promoted to blocking without a fresh false-positive measurement |
| R9 | (NEW) retry_hook_fn assumes each of the 4 coder wrappers exposes a re-enterable inner turn loop — not verified for all 4 within this design's discovery budget | HIGH | plan step 6 requires per-wrapper verification before wiring; a non-re-enterable wrapper's hook degrades to no-op (soft signal only), never a crash or a silent skip of the [2a] hard gate, which is independent of this mechanism entirely |
| R10 | (NEW) check (b)'s 50%-token-overlap heuristic, even calibrated, remains a heuristic — a legitimately-answered paste-line in unusual wording could still false-refuse | MEDIUM | numeric bar (≤15% on the 37-report corpus) stated and measured at ship time (plan step 10); if exceeded, the threshold is a documented tunable to adjust, not a silent workaround |
| R11 | (NEW) exit code 10 is a new value in `leadv2-dispatch-product-close.sh`'s case statement — any external tooling that pattern-matches exit codes 0/6/7/8/9 exhaustively (not via `*`) would treat 10 as unhandled | LOW | the existing `*` catch-all already exists as a backstop for any code not explicitly matched; 10 is added as an explicit arm specifically so it does NOT fall into that catch-all's misleading `review_engine_error` label |

## 13. Mandatory constraint checklist — results

1. **Env var naming.** `LEADV2_DOD_GATE_MAX_RETRIES` (unchanged from v1) — no
   drift from `LEADV2_*` convention. PASS.
2. **File paths.** All 14 LANE_WRITES rows (§10 step 1, §11) existence-checked or
   marked to-create; the 3 CHALLENGE-02 defects fixed; `lib/leadv2-land.sh`
   confirmed absent, treated as extension point. DONE.
3. **`claude -p` commands.** None — bash/grep/git only. N/A.
4. **Concurrent access.** `tests/run-all.sh` EXTRA_SUITE_MAP append is a known,
   pre-existing race, now explicitly raised to HIGH (R7) with the collision set
   named; mutation-control scratch tree is per-invocation `mktemp -d`, no shared
   state; the 4 coder-wrapper edits are each localized to that wrapper's own file,
   no cross-wrapper shared mutable state introduced. DONE.
5. **Config contradiction check.** `LEADV2_REVIEW_ENGINE`'s documented production
   value (0) no longer contradicts the plan's acceptance — the hard gate now runs
   regardless of this flag's value (§2, §8); grep re-run confirms the flag's
   semantics are otherwise unchanged (still governs ONLY which of the two
   post-gate branches executes, never whether the gate itself runs). PASS.

## Contradiction scan (pre-finalize, mandatory)

- **Env-var names vs settings:** `LEADV2_DOD_GATE_MAX_RETRIES` — no prior usage,
  consistent naming. `LEADV2_REVIEW_ENGINE` semantics preserved (still branches
  engine=1 vs inline body; no longer branches whether the DoD gate runs at all).
  None found.
- **Flag semantics vs other usages:** exit code 10 is NEW, not a reuse of an
  existing code with a different meaning (fixes CHALLENGE-13's exit-8 mislabel);
  exit 7 kept for dod hard-fail (uncontested); `DIFF_FILE`-only sourcing removes
  the `main`-vs-actual-base contradiction (CHALLENGE-12). None outstanding.
- **Path existence:** all 14 LANE_WRITES rows verified against the live tree or
  marked to-create (§10 step 1); `plugins/leadv2/prompts/**` removed entirely
  (was unverified-wiring, CHALLENGE-17); `lib/leadv2-land.sh` confirmed absent.
  None outstanding.
- **Self-contradiction within the plan:** v1's contradiction (§11 off-limits vs.
  §14 acceptance requiring edits to dispatch-product-close.sh) is RESOLVED — that
  file is now explicitly in LANE_WRITES (§1, §11's off-limits list no longer
  includes it). The 4 coder wrappers are likewise moved from off-limits to
  in-scope, with the scope explicitly narrowed (§11: "≤8-line retry_hook_fn only,
  no wrapper-internals refactor").

## 14. Acceptance (top-level)

**Surface:** `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` refuses a
round with `review-gate.md` `status: fail`/`reason: dod_<check>` and exit 7 (or
`status: blocked`/exit 10 for undetermined), BEFORE the `LEADV2_REVIEW_ENGINE`
branch is even evaluated — so the refusal fires identically whether the flag is
unset (production default), 0, or 1 — whenever a worker's committed lane is
missing report.md/its evidence heading (when required), has an unanswered "paste"
instruction or an ungrounded mutation-control claim, adds an unregistered test
suite, or carries a runtime-state path in its diff.

**Human-observable line:** running the product-close path against a fixture lane
built to violate exactly one of checks (a)-(d), with `LEADV2_REVIEW_ENGINE`
UNSET, prints a `review_gate task=<x> status=fail round=0 reason=dod_<check>`
decision line and produces zero calls to any reviewer model or the review engine
binary (verifiable by the absence of any `resolve_review_pool_call`/engine-invocation
log line in the same run) — the round is refused for the price of one bash
invocation, on the path production actually takes, not a 30-45 minute model round.

DELIVERABLE_COMPLETE
