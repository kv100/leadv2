# RED-FIRST-SELF-INVALIDATES-01 — architect prepass (mechanism-closed design)

Prepass only. No product file is written by this role. Root: `/Users/kostiantyn.vlasenko/Projects/leadv2`
(appears in `git worktree list` as the main entry), HEAD `7de23af` on `main`.

---

## 0. Where the mission's framing is wrong — corrected against the code

The mission states: *"Run standalone the same suite on the same commit gives `pass=9 fail=0`. So the
difference is the harness context, not the product."*

Measured on `7de23af`, standalone:

```
$ timeout 180 bash plugins/leadv2/scripts/tests/test-parked-worker-resume.sh
[TEST] FAIL: contract red-first (pre=0 post=0)
[TEST] PASS: clean waiting result with unsatisfied deliverable classifies parked
... 7 more PASS ...
[TEST] RESULT: pass=8 fail=1
```

**Standalone fails identically.** There is no harness-vs-standalone difference. Design against
this: the defect is unconditional and history-driven, not context-driven. Anyone who fixes only
"the harness path" fixes nothing.

Root cause, exact: `test-parked-worker-resume.sh:15`

```bash
BASE="$(git -C "${REPO}" rev-parse HEAD^ 2>/dev/null || true)"
[[ -n "${BASE}" ]] || BASE="6fa4823"
```

`HEAD^` is a **floating** ref, not a pin. At authoring time HEAD was the fix commit, so `HEAD^` was
pre-fix. Today `HEAD^` = `b680643` = *the merge that landed the fix*:

```
$ git rev-parse --short HEAD^          -> b680643
$ git show HEAD^:plugins/leadv2/scripts/leadv2-helpers.sh | grep -c _LEADV2_FOREGROUND_CONTRACT_MISSION
2
```

So `contract_case "${PREFIX}"` returns 0, `pre=0`, and line 35's
`[[ ${pre} -ne 0 && ${post} -eq 0 ]]` can never hold again on any branch. The literal `6fa4823`
fallback is dead code — it only fires when `rev-parse HEAD^` *fails*, which it never does outside a
root commit.

---

## 1. CALLERS / CALLEES

### 1a. Callers of the suites in scope

| Caller | file:line | Notes |
|---|---|---|
| `run-core-offline.sh` SUITE_DEFS | `plugins/leadv2/scripts/tests/run-core-offline.sh:267` | `parked worker contract …` — the only registered caller of the parked suite |
| `run-core-offline.sh` SUITE_DEFS | `run-core-offline.sh:268` | `test-lane-diff-single-repo.sh` |
| `run-core-offline.sh` SUITE_DEFS | `run-core-offline.sh:308` | `test-report-only-gate.sh` (SERIAL) |
| Human / lane verify step | mission text | direct `bash <suite>` |
| `docs/handoff/ARM-NOTHING-02-mission.md:16` | doc | names `test-lane-diff-single-repo.sh` as a lane acceptance — a doc reference, not an executor |

**No product script invokes `run-core-offline.sh`.** `grep -rn "run-core-offline" plugins/leadv2/
--include=*.sh` outside the tests dir returns only `test-core-offline-root-arith.sh` and
`test-core-offline-shards-01.sh` (which exercise the runner itself) and
`plugins/leadv2/docs/skill-proof-dod.md:33`. The e2e gate reaches this suite only through the
human/lane path.

### 1b. The "independent copy nobody named" — checked, and it is NOT one

`~/.claude/plugins/local/leadv2/plugins/leadv2/scripts/tests/` looks like an independent copy
(`find -type f` counts 218 real files, 0 symlinks at that level). It is not: an ancestor is a
symlink into this repo, proven by the runner's own probe —

```
$ LEADV2_CORE_OFFLINE_PROBE=1 bash ~/.claude/plugins/local/leadv2/plugins/leadv2/scripts/tests/run-core-offline.sh
[CORE-OFFLINE] probe LOGICAL_DIR=/Users/…/.claude/plugins/local/leadv2/plugins/leadv2/scripts/tests
  REPO_ROOT=/Users/…/Projects/leadv2
  PLUGIN_ROOT=/Users/…/Projects/leadv2/plugins/leadv2
  TEST_DIR=/Users/…/Projects/leadv2/plugins/leadv2/scripts/tests
$ diff -q <cache>/test-parked-worker-resume.sh <repo>/…/test-parked-worker-resume.sh   -> IDENTICAL
```

`~/.claude/leadv2-shared/scripts/tests/test-parked-worker-resume.sh` is likewise a per-file symlink
into this repo. **One inode. No second execution path to fix.** The implementer does not need a
propagation step.

Consequence the implementer must know: `TEST_DIR` is derived from the **physical** location of
`run-core-offline.sh`. A *real* lane worktree holds a real checkout, so a lane running the runner
grades the lane's own tree. Only a *symlinked* entry (e.g. persona-engine's
`.claude/scripts/tests/run-core-offline.sh -> canonical`) resolves `TEST_DIR` back to this repo and
grades this repo. That asymmetry is pre-existing and out of scope, but it is why "run it from the
lane" and "run it from a foreign repo" are not the same act.

### 1c. Callees of `test-parked-worker-resume.sh`

| Callee | Where | Used for |
|---|---|---|
| `leadv2-helpers.sh` (grep only) | `:27` | `_LEADV2_FOREGROUND_CONTRACT_MISSION` presence |
| `leadv2-dispatch-code.sh` (awk-extract `_spawn_worker_body`) | `:26,:28-31` | four-arm coverage + ordering vs `_LEADV2_EVIDENCE_CONTRACT_MISSION` |
| `leadv2-lane-outcome.sh` | `:41,:53` | classifier assertions 2 and 3 |
| `lib/leadv2-parked-detect.sh` (`lv2_parked_text_file`) | `:47-48` | stream replay assertion |
| `leadv2-dispatch-product-close.sh` (awk-extract 6 fns incl. `pc_dwr_resume_once`) | `:59-62` | resume-once assertions 4/5 |
| `tests/test-dwr-resume.sh` | `:78` | positive control |

**Only assertion 1 (lines 13–35) is in scope.** Assertions 2–9 touch none of the changed code and
must be byte-identical after the change.

---

## 2. STATES AND RETURN CODES

### 2a. Today — `contract_case` and the assertion

| State | `pre` | `post` | Line 35 | User-visible consequence |
|---|---|---|---|---|
| archive extracted, baseline pre-fix | 1 | 0 | PASS | suite `pass=9 fail=0`; harness reports 2 failures |
| archive extracted, **baseline already has the fix** (today) | 0 | 0 | **FAIL** | suite `pass=8 fail=1`; harness `failed=3`; **every lane's e2e gate blocks on a suite that is red for a reason unrelated to product behaviour, so unrelated work does not land** |
| archive empty / tar failed (`\|\| true` swallows it) | 2 | 0 | FAIL | same block, but the log says `pre=2` and no one can tell an environment fault from a real regression |
| live tree genuinely broken | 0 or 1 | 1 or 2 | FAIL | correct fail — the one outcome this assertion exists for |

`contract_case` returns 2 only from its guard at `:25`; otherwise it returns the rc of the final
`[[ ]]`, i.e. 0 or 1. The `2` case is **not** distinguished at line 35 — an unextractable archive is
reported as a product regression.

### 2b. After — `rf_baseline_ref` (new helper)

| rc | State | Caller action | User-visible consequence |
|---|---|---|---|
| `0` | ref resolved **and** marker verified absent at that ref | run the pre pass; assert `pre != 0 && post == 0` | `PASS: red-first foreground contract …` — real evidence, on any branch, forever |
| `3` | unresolvable: shallow clone, marker never in history, marker's intro commit is the root commit, or `git` unusable | print `SKIP: red-first baseline unresolvable — <marker>`; count neither PASS nor FAIL; do **not** touch the exit code | the suite prints `pass=8 fail=0 skip=1` and a human reading the log sees the exact reason; the harness stays green and unrelated lanes land |
| `4` | operator override `LEADV2_TEST_BASELINE_REF` points at a ref that **does** contain the marker | print `SKIP: baseline <ref> already contains <marker> — red-first evidence would be vacuous`; same non-fatal accounting as rc 3 | the operator sees that their override defeated the check, instead of a green suite that proves nothing or a red suite that blames the product |

Terminal trace: rc 3 and rc 4 reach a `SKIP` branch that never sets `FAIL`, so `run-core-offline.sh`
scores the suite passed. That is deliberate — an environment or history problem must degrade the one
assertion it belongs to, never the harness. Compare today's `test-stop-gate.sh:346`, which does a
bare `exit 1` when extraction fails: an unreadable git object there takes down all of stop-gate's
cases, which is the defect shape this prepass is asked to name, not a safety feature.

---

## 3. CONFIGURATION BOUNDARIES

The mechanism reads exactly three inputs: the env var `LEADV2_TEST_BASELINE_REF`, the git object
store of `LEADV2_REPO`, and the marker string + pathspec passed by the calling suite.

### 3a. `LEADV2_TEST_BASELINE_REF`

| Boundary | Behaviour required |
|---|---|
| absent | fall through to pickaxe resolution (`${VAR:-}` idiom already used in 7 suites) |
| empty string | identical to absent — never `git archive ""` |
| valid ref, marker absent there | honoured verbatim, rc 0 |
| valid ref, **marker present** there | rc 4 → SKIP with the vacuity reason. Never silently accepted (that is precisely the bug), never a FAIL (the operator, not the product, is wrong) |
| malformed / nonexistent ref | `git rev-parse --verify "<ref>^{commit}"` fails → rc 3 → SKIP. **Never `exit 1`.** |
| ref valid in one suite's pathspec, meaningless in another's | each suite passes its own marker+path, so resolution is per-suite; a single global override that suits one suite degrades only the others to SKIP |
| very long / whitespace / shell-metachar value | always quoted at every expansion; passed to `git rev-parse --verify` before any use |

### 3b. Git object store

| Boundary | Behaviour required |
|---|---|
| no git binary / not a checkout | `LEADV2_REPO` empty → rc 3 → SKIP |
| shallow clone (`git rev-parse --is-shallow-repository` = `true`) | pickaxe can't reach the intro commit → rc 3 → SKIP, with `shallow` in the reason |
| marker's introducing commit is the repo root | `<sha>^` does not resolve → rc 3 → SKIP |
| marker introduced, reverted, re-introduced | `--reverse … \| head -1` takes the *first* introduction; the marker-absent verification at `<sha>^` is what makes this safe — if it is present, rc 3 rather than a false PASS |
| `git archive` succeeds but yields an empty tree | existing `[[ -f "${PREFIX}/leadv2-dispatch-code.sh" ]]` guard → treat as rc 3 SKIP, not FAIL |

### 3c. Marker + pathspec

| Boundary | Behaviour required |
|---|---|
| marker not present in the **live** tree | that is a genuine post-fix failure — FAIL, not SKIP. Order matters: check `post` first |
| marker contains regex metacharacters | use `git log -S<string>` (literal string pickaxe), never `-G` (regex) |
| pathspec no longer exists at the baseline ref | `git archive <ref> <path>` yields nothing → empty-tree guard → rc 3 SKIP |
| multiple markers per suite | helper takes one marker + one path; a suite needing two resolves the *earliest-verified* one and states which in its SKIP/PASS line |

---

## 4. COUNTEREXAMPLE — what still violates the invariant after every finding here is fixed

The invariant is: *a green red-first assertion means the guarded behaviour was demonstrably absent
before the fix and present after it.* After this design lands, three things can still violate it.

**(i) A pin can go vacuous without going red.** The helper verifies the marker is absent at the
baseline, so it cannot lie — but it degrades to SKIP, and a SKIP is invisible in
`run-core-offline.sh`'s `suites passed=N failed=M` summary. A suite whose red-first arm has silently
SKIPped for months reads exactly like one that is proving something. Mitigation, and it is part of
this design: the runner must surface a `skipped=` count alongside `passed=`/`failed=`, so a rising
skip count is visible without reading 60 suite logs.

**(ii) The marker is a proxy, not the behaviour.** `contract_case` greps for
`_LEADV2_FOREGROUND_CONTRACT_MISSION` and for `glm)`/`kimi)`/`sonnet)`/`codex)` inside an
awk-extracted `_spawn_worker_body`. A refactor that renames the function, changes the brace layout
the awk range depends on, or moves the four arms into a data table keeps the *behaviour* and breaks
the *grep* — which surfaces as a post-fix FAIL blaming a regression that did not happen. This is a
pre-existing property of the assertion, it is not introduced or removed by this change, and it is
the honest reason the assertion should stay narrow.

**(iii) The lane/main asymmetry.** Because `TEST_DIR` follows the runner's physical path, a
symlinked foreign entry grades this repo rather than the caller's. A lane that fixes a red-first
assertion and verifies through a symlinked entry sees main's result, not its own. Not caused by this
change; named here because it is the mechanism that made the mission's "standalone vs harness"
hypothesis plausible, and the implementer will otherwise re-derive it.

Everything else I checked — the plugin cache copy (§1b: one inode), the shared tree (symlink), the
other 8 assertions in the suite (no shared code with the changed lines) — came back clean.

---

## 5. Decision: option (a), pinned baseline, resolved by pickaxe

**Chosen: (a).** Rejected (b) "self-skip when the fix is an ancestor" because it converts every
red-first assertion into a permanent SKIP on `main` — the branch the product actually ships from —
so the mechanism would guard only lanes and prove nothing where it matters. (a) keeps the assertion
live on every branch forever.

The tree has already converged on (a) independently, seven times, by copy-paste. The best existing
instance is `test-stop-gate.sh:322-341`, whose `STOP-GATE-BASELINE-DRIFT-01` comment states the same
diagnosis this mission reaches and resolves it with a `-S` pickaxe on the introducing commit's
parent. **This design promotes that inline idiom to one shared helper and points the unfixed sites
at it.** No new concept is invented; a proven one is deduplicated.

The rc-3/rc-4 SKIP path is *not* option (b) in disguise: it fires only when history genuinely cannot
answer the question, and it always prints why. It is not "advisory without explanation".

---

## 6. Census — every red-first site, and what happens to it

Classified by whether the baseline is self-invalidating **and** whether a green pre-pass is fatal.

### Tier 1 — armed: floating/unguarded baseline **and** hard-fails on green-pre-fix → **FIX**

| File:line | Baseline today | Status |
|---|---|---|
| `tests/test-parked-worker-resume.sh:15` | `rev-parse HEAD^` (floating, no marker guard) | **Already red on `7de23af`.** Sole cause of the mission. |
| `tests/test-lane-root-not-a-worktree.sh:99` | `merge-base origin/main HEAD`, **no marker guard**; `:142` exits non-zero when `GREEN_PRE_FIX > 0` | **Armed, not yet fired.** `origin/main` = `1586ba1`, merge-base = `1586ba1`, and `git grep` confirms the `LANE-ROOT-NOT-A-WORKTREE` marker is absent there. The fix is local-only at `78bcb9b`. **It detonates the moment `78bcb9b` is pushed to `origin/main`** — same failure shape, same lane-wide block. Fixing it now is the difference between a pattern fixed and the same bug found again next week. |

### Tier 2 — self-healing: guarded pin already present, fatal-on-green is therefore safe → **LEAVE, documented**

| File | Guard | Pin |
|---|---|---|
| `tests/test-stop-gate.sh:322-341` | marker guard **+ `-S` pickaxe on intro commit** | reference implementation |
| `tests/test-claim-evidence-gate.sh:74-86` | 3-marker guard | `559cf15` |
| `tests/test-builder-selfcheck-gate.sh:259-269` | marker guard | `85ae886` |
| `tests/test-review-round-exhaustive.sh:496-503` | marker guard | `85ae886` |
| `tests/test-review-verdict-recovery.sh:169-175` | marker guard | `9e03dc0` |
| `tests/test-review-gate-scope-evidence.sh:229-…` | marker guard | (inline) |

These already behave correctly. Migrating six currently-green suites to the helper for uniformity is
a refactor with its own blast radius and **is an explicit non-goal of this lane** (§8). The census
lists them so the next reader does not re-audit them.

### Tier 3 — vacuous: baseline is `git archive HEAD`, i.e. already contains the fix; green-pre-fix is informational and the exit code ignores it → **FIX (one-line ref swap)**

| File:line | Green-pre-fix effect today |
|---|---|
| `tests/test-lane-writes-scoping.sh:513` | counted, printed, `:563` exit driven by post-fix only |
| `tests/test-lane-diff-single-repo.sh:273` | `GREEN-PRE-FIX (not evidence)` line, exit unaffected |
| `tests/test-landing-diff-scoping.sh:452` | same |
| `tests/test-report-only-gate.sh:421` | same |
| `tests/test-statusline-readable.sh:103` | `git archive HEAD -- <paths>` |

These do not lie about their exit code, but they no longer prove anything: on any committed tree the
"pre" extraction is the fixed tree. Repointing the ref restores the evidence and cannot change any
exit code, because none of them gate on `GREEN_PRE_FIX`.

**Carve-out:** `test-report-only-gate.sh:242` uses a *second*, differently-purposed ref
(`PRE_GATE_REF`) for a golden byte-for-byte output comparison. That is not a red-first baseline and
**must not be repointed.** Only line 421 changes in that file.

### Tier 4 — deliberately baseline-free by design → **DO NOT TOUCH**

| File | Why |
|---|---|
| `tests/test-e2e-foreign-failure.sh:8-30` | uses the product's own kill-switch (`LEADV2_E2E_OWNERSHIP=0`) as a git-history-independent pre-fix stand-in. Its header already states the exact lesson this mission is (re)learning. Correct as-is. |
| `tests/test-codex-doc-pointer.sh:13` | comment explaining why `git archive` was rejected there. |
| `tests/test-leadv2-codemap.sh:16` | `git show HEAD:` used for a flag-off-absent property, not a red-first baseline. |

**Total: 21 files mention red-first; 13 construct a baseline; 2 are armed, 5 are vacuous, 6 are
sound.**

---

## 7. Design — files, contracts, sequencing

### 7a. NEW `plugins/leadv2/scripts/lib/leadv2-red-first-baseline.sh`

Placed in the **existing** `scripts/lib/` (sibling of `lib/leadv2-parked-detect.sh`), *not* a new
`tests/lib/`. Rationale: `run-core-offline.sh` owns a suite-registration list
(`_CORE_OFFLINE_OWNED_SUITES`, `:134-145`) and a `syntax_all` sweep; adding a non-suite `.sh` under
`tests/` risks tripping registration/ownership checks. `scripts/lib/` is already the established
home for sourced helpers and is inside the `plugins/leadv2/scripts` pathspec every suite archives.

```
lv2_rf_baseline_ref <marker> <pathspec> [<pin-fallback-ref>]
  stdout: the resolved baseline ref (rc 0) or nothing
  stderr: nothing
  rc 0  resolved and verified marker-absent
  rc 3  unresolvable — reason on fd 3? no: reason echoed to stdout after the rc-3 marker line
  rc 4  operator override contains the marker (vacuous)
```

Resolution order: env override → `-S` pickaxe (`git log --reverse --format=%H -S<marker> -- <path> |
head -1`, then `<sha>^`) → pin-fallback arg. Every candidate passes the same two verifications
before it is returned: `git rev-parse --verify "<ref>^{commit}"` succeeds, and
`git grep -q -- <marker> <ref> -- <path>` returns non-zero (marker absent). Bash 3.2 only — no
`readlink -f`, no `mapfile`, no associative arrays (repo standing decision: *avoid Bash 4+
features*).

A second helper keeps callers honest:

```
lv2_rf_extract <ref> <dest> <pathspec…>   # git archive | tar -x, rc 3 on empty/failed extraction
```

This replaces the `2>/dev/null … || true` idiom that currently converts an extraction failure into a
product-regression FAIL.

### 7b. `tests/test-parked-worker-resume.sh` (Tier 1)

Replace lines 13–19 and line 35 only. Lines 20–32 (`contract_case`) and 37–81 (assertions 2–9)
unchanged.

```
source "${SCRIPT_DIR}/lib/leadv2-red-first-baseline.sh"
BASE="$(lv2_rf_baseline_ref '_LEADV2_FOREGROUND_CONTRACT_MISSION' \
        plugins/leadv2/scripts/leadv2-helpers.sh '6fa4823')"; rf_rc=$?
```

Then, at the assertion:
- `post != 0` → `bad` (real regression) — evaluated **first**.
- `rf_rc` 3 or 4 → `skip "red-first baseline unresolvable: <reason>"`, `SKIP=$((SKIP+1))`, neither
  PASS nor FAIL. Requires adding a `skip()` counter + a `skip=` field to the `RESULT:` line
  (mirrors `test-statusline-readable.sh:tail`, which already prints `pass= fail= skip=`).
- otherwise assert `pre != 0 && post == 0` exactly as today.

The 8 behavioural assertions and their wording are untouched; the assertion is not deleted and not
demoted.

### 7c. `tests/test-lane-root-not-a-worktree.sh` (Tier 1)

Line 99 becomes a `lv2_rf_baseline_ref 'LANE-ROOT-NOT-A-WORKTREE' plugins/leadv2/scripts` call. Its
`GREEN_PRE_FIX → exit 1` at `:142` **stays** — with a verified baseline, a green pre-pass once again
means what it says. rc 3/4 must route to a new SKIP bucket that does not feed `GREEN_PRE_FIX`,
otherwise an unresolvable baseline still exits 1.

### 7d. Tier-3 suites — one-line ref swap each

`git archive HEAD` → `git archive "$(lv2_rf_baseline_ref <marker> <path>)"`, with the rc-3 path
falling back to the current behaviour (skip the pre pass, print the reason). No exit-code logic
changes in any of the five. `test-report-only-gate.sh:242` `PRE_GATE_REF` is not touched.

### 7e. NEW `tests/test-red-first-baseline.sh`

The helper is now load-bearing for 7 suites and must have its own coverage: env override honoured;
override-containing-marker → rc 4; pickaxe resolves intro-commit parent; marker-present-at-candidate
→ rc 3 not a false 0; nonexistent ref → rc 3 not `exit 1`; shallow repo → rc 3. Fixtures use
`mktemp -d` + `git init` throwaway repos — never `reset --hard`, `clean`, or `stash` (this tree is
shared with live sessions).

### 7f. `run-core-offline.sh` — surface the skip count

Add `skipped=` to the summary line so §4(i) is observable. Additive; the existing
`suites passed=N failed=M` prefix is preserved so any log-scraper keeps working.

### 7g. Sequencing

1. Merge `main` into the lane branch (pre-approved by the mission — do not stop to ask).
2. Land 7a + 7e; run `test-red-first-baseline.sh` green **before** touching any suite.
3. 7b, verify standalone `pass=9 fail=0`.
4. 7c, verify standalone; confirm it is still green *and* now reports `RED-then-GREEN`, not
   `GREEN-PRE-FIX`.
5. 7d one file at a time, each verified standalone.
6. 7f last (touches the runner; do it when every suite is already green).
7. Full `run-core-offline.sh`, expect `failed=2`.

---

## 8. Non-goals — the implementer must ignore these

- The two known-foreign suites (deferred-GLM ladder V3-GLM-LADDER-01, fanout classifier/runner
  guard). Off-limits per mission.
- Assertions 2–9 of `test-parked-worker-resume.sh`. Not one character.
- Migrating the six Tier-2 suites to the helper (§6). Sound today; separate refactor.
- `test-report-only-gate.sh:242` `PRE_GATE_REF` golden comparison.
- Tier-4 suites.
- Merging to `main`. Commit on the lane branch; the lead lands it.
- The `TEST_DIR`-follows-physical-path asymmetry (§4 iii). Named, not fixed here.
- `.claude/scripts/tests/` de-duplication (open-threads item). Different blast radius.
- Any `reset --hard` / `clean` / `stash`.

---

## 9. Constraint checklist

1. **Env var naming** — `LEADV2_TEST_BASELINE_REF` already exists in 7 suites; reused verbatim. No
   new env var introduced. No `LEAD_V2_*` drift.
2. **File paths** — all cited paths verified on disk this session except two marked `(to-create)`:
   `plugins/leadv2/scripts/lib/leadv2-red-first-baseline.sh` and
   `plugins/leadv2/scripts/tests/test-red-first-baseline.sh`.
3. **`claude -p` commands** — none in this design.
4. **Concurrent access** — every suite extracts into its own `mktemp -d`; the helper is read-only
   against the git object store. Two suites running in parallel (the harness runs non-`SERIAL`
   suites concurrently) share only immutable git objects. No lock needed. The helper must not write
   any cache file — a shared cache would reintroduce a race.
5. **Config contradiction** — `LEADV2_TEST_BASELINE_REF` semantics across all 7 existing users are
   consistent ("archive this ref as the pre-fix tree"); the helper preserves that meaning and only
   adds the vacuity check (rc 4). No contradiction.

---

## acceptance:

```yaml
acceptance:
  - surface: log_line
    observable: >
      Running the parked-worker suite on a branch whose history already contains the
      WORKER-PARKED-ON-BG-01 fix, the last line of its output reads "pass=9 fail=0" and the
      "contract red-first" line reads PASS rather than FAIL.
    authored_at: 2026-08-23T13:45:00Z
  - surface: log_line
    observable: >
      The core offline harness summary names exactly two failing suites — the deferred-GLM ladder
      and the fanout classifier/runner guard — and the parked-worker suite is not among them.
    authored_at: 2026-08-23T13:45:00Z
  - surface: log_line
    observable: >
      With the parked-detect behaviour deliberately broken in a scratch copy, the suite's output
      reports a failure naming that behaviour, and reports pass again once the scratch copy is
      restored.
    authored_at: 2026-08-23T13:45:00Z
  - surface: log_line
    observable: >
      On a checkout where the pre-fix baseline cannot be determined from history, the suite prints
      a skip line stating the baseline could not be resolved and why, and still reports zero
      failures.
    authored_at: 2026-08-23T13:45:00Z
  - surface: file_artifact
    observable: >
      The task report lists every red-first site found in the test tree with a per-site disposition
      (fixed / left sound / left by design), including the lane-root suite that would have failed
      only after the current local commits reach origin/main.
    authored_at: 2026-08-23T13:45:00Z
```

LANE_WRITES: plugins/leadv2/scripts/lib/leadv2-red-first-baseline.sh, plugins/leadv2/scripts/tests/test-red-first-baseline.sh, plugins/leadv2/scripts/tests/test-parked-worker-resume.sh, plugins/leadv2/scripts/tests/test-lane-root-not-a-worktree.sh, plugins/leadv2/scripts/tests/test-lane-writes-scoping.sh, plugins/leadv2/scripts/tests/test-lane-diff-single-repo.sh, plugins/leadv2/scripts/tests/test-landing-diff-scoping.sh, plugins/leadv2/scripts/tests/test-report-only-gate.sh, plugins/leadv2/scripts/tests/test-statusline-readable.sh, plugins/leadv2/scripts/tests/run-core-offline.sh

DELIVERABLE_COMPLETE
