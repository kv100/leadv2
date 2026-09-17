# REDSUITE-D-CODEX-F3-ADOPTION-AND-RETIRED-IDLE-GUARD-01 — lane report

Boundary: macOS Darwin 25.6.0, branch `worktree-d7d40fc0754c`, suites run alone (no concurrent
core-offline runners observed), per-suite ceiling 400s per the mission, actual walls 10–16s.
Baseline measured by the lead on main, 2026-09-15: suite 1 rc=1, suite 2 rc=1.
Lane HEAD before this session's commit: `86c5f5f5` (f3 fixture fix, landed 2026-09-15 19:54 by an
earlier session of this same lane — see Suite 1).

---

## Suite 1 — `plugins/leadv2/scripts/tests/test-codex-quota-guardrails.sh`

### Reproduction

Command (from the lane worktree root, today):

```
bash plugins/leadv2/scripts/tests/test-codex-quota-guardrails.sh
```

**Does not reproduce red at lane HEAD `86c5f5f5`: rc=0, pass=29 fail=0, wall 9.7s** — including
`PASS: f3 gate unavailable → exit 2, no spawn`. Commit `86c5f5f5`
("fix(test-codex-quota-guardrails): f3 fixture missing leadv2-active-registry.sh", dated
2026-09-15 19:54, parented directly on this lane's anchor `7f7c7764`, tagged
REDSUITE-D-CODEX-F3-ADOPTION-AND-RETIRED-IDLE-GUARD-01) is an earlier session of this lane that
fixed the fixture and committed it, but ended before delivering the negative control, the second
fix, and this report. Those are delivered here. The lead's red output (rc=9, adoption refusal) was
not re-observed live pre-fix on this branch; it WAS re-observed live under the negative control
below, which is the same state reproduced exactly.

### Cause class

`never_reaches_subject` — confirmed, exactly as the mission hypothesised.

### Mechanism (file:line)

f3 exists to prove **gate-unavailable → exit 2, no spawn**: it runs the runner from a scratch copy
(`$F3_SCRATCH`) and deletes the gate from that copy
(`rm -f "$F3_SCRATCH/lib/leadv2-codex-quota-gate.sh"`, test file ~line 609). The fixture builds the
scratch tree by copying `lib/*`, `leadv2-state-path.sh`, `leadv2-portable-lock.sh` — but never
`leadv2-active-registry.sh`. Since D1-SINGLE-WRITER-FOR-LANE-STATE, `lane_transition`
lazy-sources that file from `_lv2_lane_state_dir`
— `plugins/leadv2/scripts/lib/leadv2-lane-state.sh:576`
(`source "${_lv2_lane_state_dir}/leadv2-active-registry.sh" >/dev/null 2>&1 || _lt_rc=9`) —
which in the scratch tree resolves inside the scratch root, where the copy is missing.
`_lt_rc=9` fails lane adoption
(`plugins/leadv2/scripts/leadv2-codex-session-runner.sh:116`: "lane adoption refused
(rc=9): f3-task has no reusable registry row and no inheritable write set -- refusing to run as an
unregistered lane") and the case exits rc=9 **before ever reaching the quota gate it tests**.

### The lead-identity resolver warning: part of the cause, not noise

The mission asked whether
`[leadv2-lead-identity] WARNING: resolver unavailable or failed, falling back to direct` is
incidental. **Neither incidental nor the cause — it is the first symptom of the same root defect.**
`plugins/leadv2/scripts/lib/leadv2-lead-identity.sh:38-39` sources
`${_LV2_LEAD_IDENTITY_DIR}/../leadv2-active-registry.sh` — the same missing scratch copy — and its
comment at :31 documents exactly this fail-open to direct. Evidence: the warning appears in the
lead's red output and in the negative-control red run below, and appears **0 times in every green
run** (grepped `/tmp/f3-suite-before.log` and `/tmp/f3-control-green.log`: 0 hits). One missing
file, two symptoms.

### The fixture-vs-runner decision (made deliberately, as ordered)

**Fixture fix, already committed as `86c5f5f5`.** The adoption refusal is correct behaviour for a
genuinely unregistered lane: the refusal at `leadv2-codex-session-runner.sh:116` is the designed
fail-closed contract (refusing to run as an unregistered lane), and the neighbouring cases confirm
the intended shape — f1/f2 seed registry rows and pass; e1/e2 deliberately encode fail-closed /
fail-OPEN gate semantics. Making the runner distinguish "gate unavailable" from "unregistered lane"
would mean changing subject behaviour to accommodate a fixture gap — the wrong direction, and it
would weaken a real safety property (any unregistered invocation should be refused regardless of
gate state). The case's subject is the gate; the fixture was the defective party.

### The fix

One line in the fixture (test file `:607`, from `86c5f5f5`):

```bash
cp "$SCRIPTS_DIR/leadv2-active-registry.sh" "$F3_SCRATCH/" 2>/dev/null || true
```

### Negative control (mutation inside the fix, both outputs live)

Mutation: the cp line above replaced by `# CONTROL-B: cp neutered` (asserted exactly one
occurrence before replacing — the mutation lands).

Red with mutation (`CONTROL-B red rc=1`):

```
[TEST] FAIL: f3 gate unavailable → exit 2, no spawn (rc=9, err=[leadv2-lead-identity] WARNING: resolver unavailable or failed, falling back to direct
[CODEX-QUOTA-GUARDRAILS] pass=28 fail=1
```

— byte-for-byte the lead's original red (rc=9, same resolver warning, same refusal), which also
confirms the mechanism end-to-end. Green after revert (`CONTROL-B green-after-revert rc=0`):

```
[CODEX-QUOTA-GUARDRAILS] pass=29 fail=0
```

### Final suite run (boundary)

macOS Darwin 25.6.0, branch tip with this lane's commits, run alone: **rc=0, pass=29 fail=0,
wall 11s** (ceiling 400s).

---

## Suite 2 — `plugins/leadv2/scripts/tests/test-idle-lead-guard.sh`

### Reproduction

```
bash plugins/leadv2/scripts/tests/test-idle-lead-guard.sh
```

Red at lane HEAD `86c5f5f5` before any edit: **rc=1, PASS=18 FAIL=1**, case 10:

```
AssertionError: leadv2-idle-lead-guard.sh is REGISTERED in hooks.json Stop[0] but was
retired by ONE-LANE-WATCH-01 (9f00e7ed): ['"${CLAUDE_PLUGIN_ROOT}/hooks/leadv2-idle-lead-guard.sh"'].
If re-registration is deliberate, update case 10 in the same commit.
```

### Cause class

`real_regression` — the suite is the healthy party. The retirement was real, deliberate, and
documented; it was silently undone by a merge.

### Mechanism (file:line / commits)

- Retirement `9f00e7ed` (ONE-LANE-WATCH-01, 2026-09-01) deliberately removed the
  `leadv2-idle-lead-guard.sh` entry from `plugins/leadv2/hooks/hooks.json` Stop (diff verified),
  replacing the hook's job with `leadv2-lane-watch-v2.sh` (SessionStart `--arm-from-hook`, new
  SessionEnd `--disarm-from-hook`). The block predicate was measured broken
  (`leadv2-lane-liveness.sh --all` returning 0 while a lane wrote). Deliberateness is recorded in
  three places: the ONE-LANE-WATCH-01 report, the commit message, and the case-10 contract comment
  (IDLE-LEAD-GUARD-IS-NOT-REGISTERED-01, test file :415-447), which additionally asserts — added by
  lane 8f14220d1e93 — that promise-guard stays registered and arm/disarm wiring exists.
- The watcher remained alive and was actively developed after the retirement (WATCHER-LEAK-01
  rounds + fix `092e936a`), so the replacement is current, not itself superseded.
- Re-introduction: merge `1518f00e` (2026-09-11, "merge: land 908164a1 (state conflicts resolved by
  rule)") landed branch tip `e59790e0`, **forked at `8bd17580` (2026-08-24) — a week before the
  retirement** — and took that side for `hooks.json`. First-parent occurrence walk (verified with
  `grep -cF`, plain string): entry count 0 at `ddf186d0` (2026-09-07) → 1 at `1518f00e`. The four
  later commits touching hooks.json (83964c0d, 32db7645, 63ee043c, 2c8737c0, 487fe921) inherited
  the clobbered state; none of their messages mentions idle-lead-guard. **The re-registration was a
  merge artifact, not a deliberate re-registration.**
- The same merge artifact did a second, invisible loss in the same file: it dropped the
  SessionStart `--arm-from-hook` entry and the entire SessionEnd event (`watch=2 se=1` at
  `ddf186d0` → `watch=0 se=0` at `1518f00e`). This was masked in every run until this session
  removed the Stop entry, after which case 10's next assertion exposed it
  (`KeyError: 'SessionEnd'`, measured). This is why the mission's "change exactly the one Stop[0]
  entry and nothing else" was necessary but not sufficient: restoring the arm/disarm entries is not
  an extra change — it is re-applying the same recorded decision (9f00e7ed) that the merge clobbered,
  and case 10 explicitly asserts it. Everything else in hooks.json is untouched.

### The fix (subject, not test)

In `plugins/leadv2/hooks/hooks.json`, three restorations of 9f00e7ed's wiring, verbatim from its
blob:

1. Removed the retired `leadv2-idle-lead-guard.sh` object from `Stop[0].hooks` (the one entry the
   assertion names).
2. Restored `{"…leadv2-lane-watch-v2.sh\" --arm-from-hook", timeout 6, continueOnBlock,
   "Arming lane watch..."}` to the main SessionStart block, in its 9f00e7ed position (after the
   merged-worktree-sweep entry).
3. Restored the entire `"SessionEnd"` event with the `--disarm-from-hook` entry, verbatim.

### Negative control (mutation inside the fix, both outputs live)

Mutation: the removed entry re-appended to `Stop[0].hooks` (JSON-level insert of the identical
object).

Red with mutation (`CONTROL-A red rc=1`):

```
[TEST] FAIL: case 10: retired idle-lead-guard found registered in hooks.json
[TEST] idle-lead-guard: PASS=18 FAIL=1
```

Green after revert (`CONTROL-A green-after-revert rc=0`):

```
[TEST] idle-lead-guard: PASS=19 FAIL=0
```

### What else is registered in Stop[0] that I did NOT touch

Final Stop[0] — 6 entries, none removed or reordered except the one named:

1. `"${CLAUDE_PLUGIN_ROOT}/hooks/leadv2-force-reflect.sh"` (timeout 5)
2. `"${CLAUDE_PLUGIN_ROOT}/hooks/leadv2-auto-clear-after-close.sh"` (5)
3. `"${CLAUDE_PLUGIN_ROOT}/hooks/leadv2-lead-prose-guard.sh"` (5)
4. `"${CLAUDE_PLUGIN_ROOT}/hooks/leadv2-bg-stop-warn.sh"` (5)
5. `"${CLAUDE_PLUGIN_ROOT}/hooks/leadv2-promise-guard.sh"` (5) — asserted present by case 10
6. `"${CLAUDE_PLUGIN_ROOT}/hooks/leadv2-continuation-guard.sh"` (5)

(Checked: the reflect-loop retirement `2c8737c0` did not touch force-reflect — only context lines
in its hooks.json diff — so entry 1's presence is consistent with the last deliberate state, not a
stale registration.)

### Final suite run (boundary)

macOS Darwin 25.6.0, branch tip with this lane's commits, run alone: **rc=0, PASS=19 FAIL=0,
wall 16s** (ceiling 400s).

---

## Falsification set (raw results)

- `bash -n plugins/leadv2/scripts/tests/test-codex-quota-guardrails.sh` → ok
- `bash -n plugins/leadv2/scripts/tests/test-idle-lead-guard.sh` → ok
- No Python files changed.
- Worktree hygiene: `git status --porcelain` shows exactly `M plugins/leadv2/hooks/hooks.json`
  (plus the pulse hook's untracked runtime-state files under `docs/leadv2/`, which are NOT part of
  this diff and are not committed). Both test files are byte-identical to HEAD after control
  reverts (restore was from a saved copy; `bash -n` + suite green prove it).
- Changed-scope runner: `LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh --scope changed`
  selects **563 distinct suites** — the whole universe, an overnight-scale run, not executable
  inside a lane window. The four suites the selection names for this lane's changed files were run
  in full instead:

| suite | rc | result | wall |
|---|---|---|---|
| test-codex-quota-guardrails.sh | 0 | pass=29 fail=0 | 11s |
| test-idle-lead-guard.sh | 0 | PASS=19 FAIL=0 | 16s |
| test-lane-watch-poll.sh | 0 | PASS=14 FAIL=0 | 11s |
| test-lane-watch-v2.sh | 1 | PASS=34 FAIL=1 | 43s |

---

## Still red, with cause

**`test-lane-watch-v2.sh` — 1 case: "run-all.sh: trigger map has 1133 row(s), none mapping
leadv2-lane-watch-v2 to this suite."** Inherited, not caused by this lane: the case reads
`tests/run-all.sh`, which this diff does not touch (git status is the proof), and the row count
walk confirms it — `tests/run-all.sh` carried 2 `leadv2-lane-watch-v2` rows at `9f00e7ed` and 0 at
HEAD; the drop coincides with `65734576` ("wip(SUITE-MAP): CHECKPOINT — self-registration markers
across 102 suites, **ACCEPTANCE NOT PROVEN**" — the commit's own words) touching the map. The
subject is the run-all trigger map / the SUITE-MAP WIP, outside this mission's two suites and this
lane's write set. All 34 functional cases in the suite pass; my hooks.json restoration is
consistent with them.

## Write-set statement

Files written: `plugins/leadv2/hooks/hooks.json` (the fix), this report. Plus
`plugins/leadv2/scripts/tests/test-codex-quota-guardrails.sh` — already fixed and committed on this
lane's branch before this session (`86c5f5f5`); today's session only mutated and restored it for the
negative control (byte-identical restore, proven above). No writes outside the mission's two
suites' subject+fixture files. No changes to `docs/leadv2/` runtime state in the diff.
