# Round-2 VERIFY-ONLY review — b579f97 (CLAIM-EVIDENCE-GATE-01 round 2)

Worktree: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/d784b987`
Commit under review: `b579f97` — `fix(review): CLAIM-EVIDENCE-GATE-01 round 2 …`
Round-1 findings verified against: `docs/handoff/dispatch-2e675c98-review/critic.full.md`
Mode: verification-only. No new lens sweep. Every verdict below is an executed probe, not prose.

## REVIEW_VERDICT: PASS_WITH_NITS
## REVIEW_FINDINGS: critical=0 high=0 medium=1 low=4
Round-1 status: **H1 FIXED · H2 FIXED · M1 FIXED · M2 FIXED · M3 FIXED · M4 MOOT · M5 FIXED ·
L1 FIXED · L2 FIXED · L3 NOT FIXED · L4 FIXED · L5 FIXED**

---

## 1. Round-1 finding-by-finding verification

### H1 — SKILL.md never reached the worker prefix → **FIXED (proved on a rendered artifact)**

Independent probe (my own, not the suite's), scratch PROJECT_ROOT with `.claude/agents/critic.md`
and **deliberately no** `.claude/skills/leadv2-subagent-protocol/SKILL.md`, `CLAUDE_PLUGIN_ROOT`
unset so the fallback logic itself is exercised:

```
$ ( unset CLAUDE_PLUGIN_ROOT; PROJECT_ROOT=$R LEADV2_DRY_RUN=1 \
    bash .../claude-subsession.sh --role critic --model sonnet --task-id CEGVERIFY \
    --mission-file $M --wait ) 2>&1
[claude-subsession] stable prefix file reused for critic (...)
[claude-subsession] prefix path: /tmp/leadv2-cache/prefix-critic.c7fbabf17664a3658105e58e19b01fcf.md
[DRY_RUN] subsession spawn: role=critic model=sonnet task=CEGVERIFY

$ wc -c  <prefix>                                            18258      (round 1: 6707)
$ grep -c 'EVIDENCE CONTRACT' <prefix>                       1
$ grep -c 'Evidence contract for external-system claims'     1          (round 1: 0)
$ grep -c 'UNVERIFIED:' <prefix>                             2
```

The §11 heading now lands in the rendered claude-arm prefix. Live-repo precondition re-confirmed —
the repo-local path is still absent everywhere, so the plugin-root arm is the one actually doing
the work in production:

```
ABSENT  persona-engine   ABSENT  m3-market   ABSENT  respiro-ios
plugins/leadv2/skills/leadv2-subagent-protocol/SKILL.md  16391 bytes, §11 at line 186
```

**Missing file WARNs instead of silently emptying** — probed by pointing `CLAUDE_PLUGIN_ROOT` at an
empty dir so BOTH resolution arms miss:

```
[claude-subsession] WARN: subagent-protocol SKILL.md not resolvable (tried
  /tmp/ceg-h1w.../.claude/skills/leadv2-subagent-protocol/SKILL.md,
  /tmp/ceg-empty.../skills/leadv2-subagent-protocol/SKILL.md)
  — prefix will omit the protocol reference
prefix bytes=2181   EVIDENCE CONTRACT: 1
```

Warn on stderr, fail-open on content (worker still spawns with the operative bullets). That is the
behaviour round 1 demanded. Both halves of H1 discharged.

### H2 — contract absent from the glm/kimi/codex writing side → **FIXED (rendered mission, pin still first)**

Independent live dispatch (my own stub harness, `--worktree` so `WORKTREE_PIN_LINE` is non-empty),
capturing the exact string handed to the GLM launcher's `bg`:

```
dispatch_rc=0
--- rendered mission, first 6 lines ---
WORKTREE PIN: all edits go in /private/tmp/ceg-h2.AMDiBp/target/.claude/worktrees/LANE-01; do NOT …

EVIDENCE CONTRACT: every factual claim you write about an external system or API (endpoint behavi…

H2 probe verify contract injection ordering

line1_is_pin=1   line3_is_contract=1   EVIDENCE_CONTRACT_count=1   UNVERIFIED_count=1
```

Pin line is line 1, contract line 3, mission body line 5 — exactly the ordering the lead reordered
for. No duplication (the glm-coder idempotence guard fires).

Placement suite at this commit:

```
$ bash plugins/leadv2/scripts/tests/test-lane-placement-pin.sh   → RC=0
[LANE-PLACEMENT-01] passed=24 failed=0
```

That suite asserts pin-first with `head -1` at four call sites (`:175, :206, :354, :361`) and
asserts pin-absent on shared-tree dispatch (`:394`), so "pin stays first" is pinned by rendered
artifacts, not by reading.

Codex/kimi arms verified structurally against the real source (the suite's own documented
compromise, and I re-derived it rather than trusting it):

```
$ awk 'NR>2533 && NR<2760 && /^\s*(local )?mission=/'  leadv2-dispatch-code.sh   → (no output)
2546  GLM_BIN   bg   "${mission}"
2586  KIMI_BIN  bg   "${mission}"
2710  CODEX_BIN task "${mission}"
```

Injection at `:2528-2532`, `case "${arm}" in` at `:2534` — no `mission=` reassignment between the
two, so all four arms consume the mutated variable. `sig8` is a **positional parameter** of
`_spawn_worker_body` (`:2513 local arm="$1" mission="$2" sig8="$3"`), computed by the caller, so the
injection provably cannot move sig8 or defeat the dedup ledger — the diff's own comment claim holds.

Refusal parsing is unaffected by the new stderr line: `refusal_reason` (`:2472-2510`) matches only
`LEADV2_DISPATCH_REFUSED:`, `[glm-quota-gate] REROUTE`, and one legacy lock-busy string.

### M1 — rendered-artifact case in the suite → **FIXED** (with one integrity nit, see N1)

`test-claim-evidence-gate.sh` now carries C7 (rendered claude prefix) and C8 (rendered GLM dispatch
mission), both real invocations, plus C9 (three-site marker drift pin). Executed at this commit:

```
$ bash plugins/leadv2/scripts/tests/test-claim-evidence-gate.sh ; echo RC=$?
… (25 lines) …
[TEST] RED-then-GREEN: rendered-prefix-h1 (pre_rc=1 -> post_rc=0)
[TEST] PASS: C7 companion -- DRY_RUN marker present, no real claude CLI launched
[TEST] RED-then-GREEN: dispatch-mission-glm-h2 (pre_rc=1 -> post_rc=0)
[TEST] PASS: C8 codex structural -- injection precedes arm case, codex consumes the same ${mission}

Results: 25 passed(red->green), 0 failed, 0 green-pre-fix, 0 could-not-run
RC=0
```

25 / 0 / 0 as claimed. Registered in the aggregate runner (`run-core-offline.sh:227`).

### M2 — bash 3.2 `set -u` on the empty `ERRORS` expansion → **FIXED**

```
$ /bin/bash --version | head -1
GNU bash, version 3.2.57(1)-release (arm64-apple-darwin25)
$ /bin/bash -c 'set -uo pipefail; E=(); printf -- "FAIL: %s\n" "${E[@]+"${E[@]}"}"; echo rc=$?'
FAIL:
rc=0
```

`:478` now uses the safe idiom. And the diagnostic half is fixed too — the whole suite run under
system bash 3.2 with a forced self-nullifying baseline no longer aborts and no longer goes red with
an empty reason:

```
$ LEADV2_TEST_BASELINE_REF=HEAD /bin/bash .../test-claim-evidence-gate.sh ; echo RC=$?
Results: 21 passed(red->green), 0 failed, 4 green-pre-fix, 0 could-not-run
FAIL: preamble-evidence-contract: GREEN-PRE-FIX (baseline already passes, pre_rc=0)
FAIL: exhaustive-five-lenses: GREEN-PRE-FIX (baseline already passes, pre_rc=0)
FAIL: C9: GREEN-PRE-FIX -- baseline already carries the canonical marker
FAIL: dispatch-mission-glm-h2: GREEN-PRE-FIX (baseline already passes, pre_rc=0)
RC=1
```

Every red now names its cause (`run_case:131`).

### M3 — duplicated `512ecda` hunk → **FIXED**

```
$ git merge-base --is-ancestor 512ecda HEAD ; echo rc=$?      rc=0    (round 1: rc=1)
$ git merge-base origin/main HEAD                             512ecda…
$ git show --name-only b579f97   → claude-subsession.sh, glm-coder.sh,
                                    leadv2-dispatch-code.sh, leadv2-helpers.sh,
                                    tests/test-claim-evidence-gate.sh      (no test-supervise-v2.sh)
$ git show --name-only d486160   → …, skills/leadv2-subagent-protocol/SKILL.md
                                    (no test-supervise-v2.sh either — dropped on rebase)
$ git diff origin/main HEAD -- plugins/leadv2/scripts/tests/test-supervise-v2.sh   → (empty)
```

Lane rebased, duplicate dropped, that file now byte-identical to `origin/main`. Note for the lead:
`origin/main` has since advanced by one commit (`7daf57f`, TURN-CAP-GATE deletion) that this lane
does not contain — a normal pre-merge fast-forward, not a finding.

### M4 — lens 5 applied to the diff itself → **MOOT for this commit**

The two untagged macOS/`ps`-semantics claims lived in the `test-supervise-v2.sh` hunk that M3
removed; they now reach `main` only via `512ecda`, which is outside this commit. I re-applied lens 5
to the round-2 diff:

```
$ git show b579f97 | grep -E '^\+.*(macOS|Apple|kernel|Instagram|Threads|Supabase|HTTP|rate limit)'
→ only the four copies of the contract text itself
```

No external-system claims in the added lines. Every added claim is about this repo's own scripts,
and I verified the load-bearing ones (all true except one arithmetic slip, N4):

| Claim in a new comment | Verdict |
|---|---|
| `CLAUDE_PLUGIN_ROOT` already read in helpers / dispatch-code / session-route / deploy-merge / self-spawn | TRUE — all 5 files exist, grep counts 5/1/2/3/6 |
| repo-local SKILL.md absent under all three live roots | TRUE (probe above) |
| dispatch parses the sonnet handle from stdout only, never stderr | TRUE — `:2632` redirects `2>"${errf}"` |
| `build_cached_prefix()` runs before the DRY_RUN chokepoint | TRUE — prefix materialised under `LEADV2_DRY_RUN=1` |
| merge-base `512ecda` carries none of the three markers | TRUE — `git grep` count 0/0/0 |
| test-lane-placement-pin's v1-router-defaults-to-glm shape | TRUE — `setup_env:132-134` |
| "a ~1.4k-line helpers file" | **FALSE — 2594 lines** (N4) |

### M5 — preamble overstated the BLOCKING consequence → **FIXED**

`claude-subsession.sh:246` now reads `… and round-1 reviewers treat one that drives a decision as
BLOCKING.` Matches `SKILL.md` §11 and matches the actual enforcement (round-1 exhaustive branch
only, C3 still pins verify_only purity).

### L1 — dangling protocol pointer → **FIXED**

`:247` — `See full protocol: the protocol reference appended below
(plugins/leadv2/skills/leadv2-subagent-protocol/SKILL.md).` No longer points a worker at a path it
cannot open; the body is genuinely appended below (H1 probe, 18258 bytes).

### L2 — terminal baseline fallback `HEAD` → **FIXED**

`:81` and `:86` both resolve to `559cf15`. The `HEAD` fallback is gone.

### L3 — C4 quote/backtick guard does not cover the sibling `FIVE lenses` line → **NOT FIXED**

```
$ grep -n 'exhaustive_new_lines=' test-claim-evidence-gate.sh
162: exhaustive_new_lines="$(grep -E 'claims-without-evidence|Claims-without-evidence rule' …)"
$ grep -n 'FIVE lenses' leadv2-review-run.sh
704:    printf 'Review this diff through FIVE lenses:\n'
```

The pattern was never widened to `FIVE lenses|claims-without-evidence`. Line 704's content happens
to contain no quote or backtick today, so this is a latent guard gap, not a live defect. Round 2 did
add three sibling guards for the new files (helpers / glm-coder / dispatch-code), which is why this
stays Low. Carried as N3 below.

### L4 — baseline self-nullification guard checked one file → **FIXED**

`:77-83` now requires all three markers (`claims-without-evidence` in `leadv2-review-run.sh`,
`EVIDENCE CONTRACT` and `UNVERIFIED:` in `claude-subsession.sh`) before demoting to the pinned floor.

### L5 — scratch dirs leaked on FATAL / interrupt → **FIXED**

`:34-42` — `CLEANUP_PATHS` array + `trap _cleanup EXIT INT TERM`, with the bash-3.2-safe
`"${CLEANUP_PATHS[@]+"${CLEANUP_PATHS[@]}"}"` expansion. `PREFIX_DIR`, `c6_stub_dir`, `c6_root`, and
the C7-companion scratch files are all registered.

L6 / L7 were informational-only in round 1 and required no change.

---

## 2. New findings introduced by round 2

### MEDIUM

#### N1 — C7's red-first leg is vacuous: it is red at baseline for a harness reason, not for a missing fix
**Category:** test integrity / lying-green-adjacent
**File:** `plugins/leadv2/scripts/tests/test-claim-evidence-gate.sh:290-345` (`case_c7_rendered_prefix`
via `run_case`), interacting with `:87` (`git archive "${REF}" plugins/leadv2/scripts`)

`run_case` runs each case twice: once against `PREFIX_SCRIPTS` (a `git archive` extraction of the
baseline) and once against `SCRIPT_DIR`. The archive extracts **only** `plugins/leadv2/scripts`, so
`plugins/leadv2/skills/` does not exist in the extraction, so the plugin-root fallback that H1 added
can never resolve there. I proved the pre-leg is red even with a **fully fixed** script:

```
$ git archive HEAD plugins/leadv2/scripts | tar -x -C $D
archive contains skills/ dir?                      : NO
archive claude-subsession.sh HAS the H1 fix?       : 4 hits on skill_file_plugin
$ ( unset CLAUDE_PLUGIN_ROOT; PROJECT_ROOT=$R LEADV2_DRY_RUN=1 \
    bash $D/plugins/leadv2/scripts/claude-subsession.sh --role critic … --wait )
[claude-subsession] WARN: subagent-protocol SKILL.md not resolvable (tried
  /tmp/c7root…/.claude/skills/…, /tmp/c7red…/plugins/leadv2/scripts/../skills/…)
sec11_heading_in_prefix = 0        ← post-fix code, still fails the C7 assertion
```

So `[TEST] RED-then-GREEN: rendered-prefix-h1 (pre_rc=1 -> post_rc=0)` is not evidence that the fix
is what turned it green — the pre-leg is structurally red regardless. This is precisely the shape
the repo's own pre-build checklist names ("a test must FAIL against the pre-patch file — *measure
it, don't assume*"). It is Medium, not High, because the **green** leg is a genuine rendered-artifact
assertion against the real tree — a future revert of the plugin-root fallback WOULD turn C7 red,
which is the direction that matters, and that is what M1 asked for. The claim in the commit subject
("rendered-prefix probe green") is true; the implied red-first strength is not.

**Required fix (either):** (a) extend the archive to `plugins/leadv2/scripts plugins/leadv2/skills`
so the baseline extraction is a faithful plugin root and C7's pre-leg measures the fix; or (b) take
C7 out of `run_case`, run it once against `SCRIPT_DIR`, and label it non-red-first exactly as C6 is
labelled at `:236-240` — do not print `RED-then-GREEN` for it. Option (a) is preferable: it also
makes any future C7-shaped case honest.

### LOW

#### N2 — the claude/sonnet arm now receives the contract twice, contradicting the code's own comment
**Category:** redundancy / comment-vs-behaviour contradiction
**File:** `plugins/leadv2/scripts/leadv2-dispatch-code.sh:2519-2532` vs `:2616-2632`

The comment says "prepend the evidence-contract text to every **non-claude** arm's mission", but the
injection sits above `case "${arm}" in` and is unconditional, so the `sonnet` arm's `${mfile}`
(`:2618`) also carries it — on top of `SHARED_PROTOCOL_BOILERPLATE:246`, which already carries the
identical sentence in the cached prefix. Sonnet-arm workers see the paragraph twice. Harmless for
behaviour, ~500 wasted tokens per sonnet dispatch, and the comment is now false.
**Fix:** either move the injection inside the case for glm/kimi/codex, or reword the comment to
"every arm; the claude arm gets it twice by design because the prefix is cached separately".

#### N3 — L3 carried forward: `FIVE lenses` line still outside the quote/backtick guard
**File:** `plugins/leadv2/scripts/tests/test-claim-evidence-gate.sh:162`
As analysed under L3 above. **Fix:** `grep -E 'FIVE lenses|claims-without-evidence|Claims-without-evidence rule'`.

#### N4 — evidence-free sizing claim in the new glm-coder.sh comment is wrong by ~1.9×
**File:** `plugins/leadv2/scripts/glm-coder.sh:112-119`
> "glm-coder.sh sources no shared lib today; a ~1.4k-line helpers file would be a larger blast
> radius than the drift it removes"

```
$ wc -l plugins/leadv2/scripts/leadv2-helpers.sh
    2594
```

The number is wrong (the conclusion survives — 2594 is *more* blast radius, not less — so this is a
Low, not a correctness break). It is still an unverified factual claim used to justify a design
decision, in the very commit that ships the rule against exactly that. **Fix:** correct to `2.6k`.

#### N5 — two escape hatches the new "not an env var, not a config knob" comment denies
**Files:** `plugins/leadv2/scripts/leadv2-helpers.sh:52-66`; `plugins/leadv2/scripts/glm-coder.sh:242-246`
and `:1640-1646`; `plugins/leadv2/scripts/leadv2-dispatch-code.sh:2530-2531`

Three small holes, each individually Low:
1. `if [[ -z "${_LEADV2_EVIDENCE_CONTRACT_MISSION:-}" ]]; then readonly … fi` — the double-source
   guard also means **any pre-set environment value silently wins**, so the contract text *is*
   externally overridable, contradicting the comment "Not an env var, not exported, not a config
   knob". C9 pins the three source files, not the runtime value.
2. glm-coder's idempotence guard is a substring test on `EVIDENCE CONTRACT:`. A direct
   `glm-coder.sh bg` whose mission text merely *mentions* the string (e.g. a lane tasked with
   working on this very feature) silently gets no contract. Dispatched lanes are unaffected
   (dispatch-code prepends unconditionally).
3. The dispatch-code fallback literal at `:2531` is a **fourth, divergent** copy of the contract,
   shorter than the canonical sentence and not covered by C9's byte-identity pin. It only fires if
   `leadv2-helpers.sh` failed to source, which is also when `log_err` availability is least certain.

**Fix:** drop the `-z` guard in favour of a plain `readonly` with `2>/dev/null || true` (or a
sourced-once sentinel), and either delete the divergent fallback literal (hard-fail instead) or add
it to C9's pin.

---

## 3. Raw probe output

### Type checkers

The diff contains **no Python and no TypeScript** — five bash files only, so `mypy --strict` and
`npx tsc --noEmit` are not applicable. The equivalent static gate is `bash -n` on both bash
generations plus `shellcheck -S warning`, run on all five changed files:

```
=== bash -n (bash5 + /bin/bash 3.2) ===
plugins/leadv2/scripts/claude-subsession.sh                bash5:OK bash3.2:OK
plugins/leadv2/scripts/glm-coder.sh                        bash5:OK bash3.2:OK
plugins/leadv2/scripts/leadv2-dispatch-code.sh             bash5:OK bash3.2:OK
plugins/leadv2/scripts/leadv2-helpers.sh                   bash5:OK bash3.2:OK
plugins/leadv2/scripts/tests/test-claim-evidence-gate.sh   bash5:OK bash3.2:OK

=== shellcheck -S warning (version 0.11.0) ===
--- plugins/leadv2/scripts/claude-subsession.sh (rc=0) ---
(clean)
--- plugins/leadv2/scripts/glm-coder.sh (rc=1) ---
line 92:  readonly SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename …)"
          SC2155 (warning): Declare and assign separately to avoid masking return values.
--- plugins/leadv2/scripts/leadv2-dispatch-code.sh (rc=1) ---
line 365:  SC1090  can't follow non-constant source
line 387:  SC1090  can't follow non-constant source
line 1371: SC2046  Quote this to prevent word splitting
line 1377: SC2097/SC2098  assignment only seen by the forked process
line 2435: SC2097  assignment only seen by the forked process
line 2444: SC2098  expansion will not see the mentioned assignment
line 3550: SC1010  Use semicolon or linefeed before 'done'
line 3603: SC1010  Use semicolon or linefeed before 'done'
--- plugins/leadv2/scripts/leadv2-helpers.sh (rc=1) ---
line 647:  SC2155   local base=$(basename "$d")
line 953:  SC2155   local pid=$(cat "$LEADV2_LOCK")
line 965:  SC2155   local dpid=$(cat /tmp/leadv2-daemon.pid)
line 1553: SC1090   source "$_LEADV2_REGISTRY"
line 1988: SC2154   _env_file is referenced but not assigned
--- plugins/leadv2/scripts/tests/test-claim-evidence-gate.sh (rc=0) ---
(clean)
```

**Every shellcheck warning is on a pre-existing line.** Changed-hunk ranges from
`git show b579f97 --unified=0`: claude-subsession 246, 279-357; glm-coder 112-124, 241-246,
1640-1646; dispatch-code 2519-2532; helpers 52-66; test file 4-478. None of the warned lines
(92, 365, 387, 1371, 1377, 2435, 2444, 3550, 3603, 647, 953, 965, 1553, 1988) falls inside a new
hunk. The two files whose new content is largest — `claude-subsession.sh` and the test — are
shellcheck-clean at rc=0.

### `test-claim-evidence-gate.sh` (executed, this commit)

```
[TEST] PASS: bash -n claude-subsession.sh
[TEST] PASS: /bin/bash -n claude-subsession.sh (bash 3.2 syntax)
[TEST] PASS: bash -n leadv2-review-run.sh
[TEST] PASS: /bin/bash -n leadv2-review-run.sh (bash 3.2 syntax)
[TEST] PASS: bash -n leadv2-helpers.sh
[TEST] PASS: /bin/bash -n leadv2-helpers.sh (bash 3.2 syntax)
[TEST] PASS: bash -n leadv2-dispatch-code.sh
[TEST] PASS: /bin/bash -n leadv2-dispatch-code.sh (bash 3.2 syntax)
[TEST] PASS: bash -n glm-coder.sh
[TEST] PASS: /bin/bash -n glm-coder.sh (bash 3.2 syntax)
[TEST] RED-then-GREEN: preamble-evidence-contract (pre_rc=1 -> post_rc=0)
[TEST] RED-then-GREEN: exhaustive-five-lenses (pre_rc=1 -> post_rc=0)
[TEST] PASS: verify_only branch does not contain claims-without-evidence
[TEST] PASS: exhaustive branch new text has no quote/backtick
[TEST] PASS: preamble evidence bullets have no quote/backtick
[TEST] PASS: leadv2-helpers.sh mission contract has no backtick
[TEST] PASS: glm-coder.sh evidence preamble has no quote/backtick
[TEST] PASS: leadv2-dispatch-code.sh injection lines have no backtick
[TEST] PASS: C9 canonical marker sentence identical (count=1) in all three sites
[TEST] PASS: C9 marker absent from baseline (red-first confirmed)
[TEST] PASS: rendered round-1 mission contains claims-without-evidence lens
[TEST] RED-then-GREEN: rendered-prefix-h1 (pre_rc=1 -> post_rc=0)          ← see N1
[TEST] PASS: C7 companion -- DRY_RUN marker present, no real claude CLI launched
[TEST] RED-then-GREEN: dispatch-mission-glm-h2 (pre_rc=1 -> post_rc=0)
[TEST] PASS: C8 codex structural -- injection precedes arm case, codex consumes the same ${mission}

Results: 25 passed(red->green), 0 failed, 0 green-pre-fix, 0 could-not-run
RC=0
```

### `test-lane-placement-pin.sh` (executed, this commit)

```
[LANE-PLACEMENT-01] passed=24 failed=0
RC=0
```

### `run-core-offline.sh` — forward and reverse (executed, this commit)

```
[CORE-OFFLINE] suites passed=53 failed=0 missing=0 repo=…/.claude/worktrees/d784b987
FWD_RC=0

LEADV2_CORE_OFFLINE_REVERSE=1
[CORE-OFFLINE] suites passed=53 failed=0 missing=0 repo=…/.claude/worktrees/d784b987
REV_RC=0
```

53/0 both directions, independently reconfirmed at `b579f97` — the lead's claim holds.

---

## 4. Pre-finalize contradiction scan

| Check | Result |
|---|---|
| New env vars introduced? | **None.** `_LEADV2_EVIDENCE_CONTRACT_MISSION` is a plain shell readonly, not exported (`grep -c 'export _LEADV2_EVIDENCE'` = 0). `CLAUDE_PLUGIN_ROOT` pre-exists in 5 named scripts — verified, counts 5/1/2/3/6. Caveat: the `-z` guard makes it environment-overridable in practice → N5. |
| Env-var names vs settings | `LEADV2_DRY_RUN`, `LEADV2_TEST_BASELINE_REF`, `LEADV2_DISPATCH_GLM_BIN`, `LEADV2_STUB_MISSION_OUT`, `LEADV2_ROUTER_V2`, `LEADV2_CORE_OFFLINE_REVERSE` — all pre-existing and used with existing semantics. No renames. |
| Flag semantics vs other usages | No flags added or changed. `REVIEW_MODE`/`REVIEW_ROUND` untouched; `leadv2-review-run.sh` is not in this commit at all. |
| Path existence: `plugins/leadv2/skills/leadv2-subagent-protocol/SKILL.md` (now referenced at `claude-subsession.sh:247`) | **EXISTS** — 16391 bytes, §11 at line 186. Round-1's contradiction is resolved. |
| Path existence: repo-local `.claude/skills/leadv2-subagent-protocol/SKILL.md` in 3 live repos | Still absent in all three — but now a *first-choice* override, not the only path, and its absence WARNs. Not a contradiction any more. |
| Path existence: 5 scripts named in the `CLAUDE_PLUGIN_ROOT` comment | All 5 exist and all 5 read the var. |
| `512ecda` relationship to this branch | **Resolved** — ancestor (rc=0), duplicate hunk gone, `test-supervise-v2.sh` identical to `origin/main`. |
| `origin/main` vs HEAD | `origin/main` is one commit ahead (`7daf57f`). Normal pre-merge FF, not a finding. |
| `leadv2-dispatch-product-close.sh` touched? | **No.** Absent from `git show --name-only`. |
| sig8 / dedup ledger integrity vs the new prepend | **Safe** — `sig8` is `$3` of `_spawn_worker_body`, computed by the caller before the prepend. |
| New stderr line vs handle/refusal parsing | **Safe** — sonnet handle read from stdout (`2>"${errf}"`); `refusal_reason` matches only explicit markers. |
| Contract text quote/backtick safety (flows into codex argv + double-quoted strings) | **Safe** — C9 + three new guards; verified no `"` or `` ` `` in any of the four copies. |
| C9 marker byte-identity across the three sites | Passes; but a **fourth** divergent copy exists at `leadv2-dispatch-code.sh:2531` outside the pin → N5.3. |
| Numeric claim in a new comment ("~1.4k-line helpers") | **CONTRADICTION — 2594 lines.** Raised as N4. |
| Comment claim "every **non-claude** arm's mission" vs unconditional placement | **CONTRADICTION** — the sonnet arm gets it too. Raised as N2. |
| Test registered in every runner that needs it | One registry only (`run-core-offline.sh:227`); `test-lane-placement-pin.sh` also registered and green. No census gap. |

Contradiction scan output: **three contradictions found (N2, N4, N5.1), all Low.**

---

## 5. Verdict

**PASS_WITH_NITS** — both round-1 High findings are genuinely closed against rendered artifacts, not
prose. H1: the §11 body now lands in the real cached prefix (18258 bytes, heading present) and a
double-miss WARNs on stderr instead of emptying silently. H2: a live GLM dispatch shows pin line
first, contract second, mission third, exactly once, with the codex/kimi arms provably consuming the
same mutated `${mission}` and `sig8` provably untouched. M1/M2/M3/M5 and L1/L2/L4/L5 all verified
fixed by execution; M4 is moot because the offending hunk was rebased away. All three suites are
green at this commit (25/0, 24/0, 53/0 forward and reverse), `bash -n` passes under both bash
generations, and no shellcheck warning falls on a line this commit wrote.

Nothing here blocks the commit. The one Medium (N1) is a truthfulness defect in the *test's* red-first
label rather than in the shipped behaviour — the assertion it makes is real and will catch a revert;
it just cannot prove it was red for the right reason. Fix N1 before the next lane builds a C7-shaped
case on top of it, and fold N2-N5 into the same touch-up.

DELIVERABLE_COMPLETE
