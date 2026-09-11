# SALVAGE-EXITS-ZERO-ON-CONFLICT-01 — lane report

- Dispatch: `dispatch-b9fd9799`, task row `c65d77ed1b3c`, lane branch `worktree-c65d77ed1b3c`
- Code commit: `4adad6b1` (on anchor `4d3eb1bd`, main base `b94ca7be`)
- Scope design: architect prepass (mechanism-closed), generated 2026-09-09T15:52:10Z

## 0. Census — confirmed, not falsified

The design's §0 discovery held on the implementer's tree:

- The rc mapping (0 green/nothing · 1 red · 3 conflict · 2 fatal) is **already in main**
  (`eabf35f6`, lane CONTROL-PLANE-FILES-CONFLICT-ON-EVERY-OLD-BRANCH-01):
  `leadv2-lane-salvage.sh:446-451`, `main "$@"` last statement, `set -uo pipefail` (no `-e`).
  Nothing to re-implement; the task row is stale relative to the tree, as the prepass said.
- This lane therefore delivered exactly the two genuinely-open items: **R1** (`--help` did not
  print the exit codes: the old `sed -n '2,40p'` range stopped at line 40, the exit-code block
  lives at lines 50–56) and **R2** (no suite under the mandated name; no demonstrated negative
  control for the `conflict) return 3` arm).

## 1. Diff

`git diff 4d3eb1bd --stat` (verified again after mutation restore — exactly this, nothing else):

```
 plugins/leadv2/scripts/leadv2-lane-salvage.sh      |   2 +-
 .../scripts/tests/test-lane-salvage-exit-codes.sh  | 275 +++++++++++++++++++++
 2 files changed, 276 insertions(+), 1 deletion(-)
```

C1 — the one production line changed (`leadv2-lane-salvage.sh:322`):

```
-      -h|--help) sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
+      -h|--help) awk 'NR==1{next} !/^#/{exit} {sub(/^# ?/,""); print}' "${BASH_SOURCE[0]}"; exit 0 ;;
```

Prints the whole leading comment block up to the first non-`#` line (drift-proof: header
growth above `set -uo pipefail` is printed automatically instead of a frozen sed range).
The exit-code `case` at `:446-451` was NOT touched — it is correct.

C2 — new suite `plugins/leadv2/scripts/tests/test-lane-salvage-exit-codes.sh`
(275 lines, self-registered via `# run-all-triggers: leadv2-lane-salvage.sh` header;
run-all discovery needs no registration edit — `tests/run-all.sh:301,335` scan the
`test-*.sh` glob at `:493`). Cases E1–E8 per the design table, each asserting BOTH the rc
(captured unpiped, output to a file) and the `verdict=` token; E8 re-derives the expected rc
FROM the printed verdict through a `case` mirroring the contract, so rc and stdout cannot
disagree silently.

## 2. Acceptance: rendered_line — `--help` shows the exit-code table

Probe: `bash plugins/leadv2/scripts/leadv2-lane-salvage.sh --help > /tmp/help.out; rc=$?`
→ `rc=0`, 55 lines, tail:

```
52:  0 = salvaged_green | nothing_to_salvage
53:  1 = salvaged_red (carried, but run-all exited non-zero or timed out)
54:  3 = conflict (a pick conflicted outside the auto-resolvable shape)
55:  2 = usage / environment error (no verdict), incl. main-moved invariant
```

## 3. Acceptance: file_artifact — suite green run + red run under mutation

### 3.1 Green run (verbatim)

```
$ bash plugins/leadv2/scripts/tests/test-lane-salvage-exit-codes.sh
ok - bash -n leadv2-lane-salvage.sh (incl. 3.2)
ok - E1 verdict=conflict carried=0/1, branch dropped
ok - E1 conflict at first pick: exit 3
ok - E2 verdict=conflict carried=1/2, prefix branch kept
ok - E2 conflict after one carried pick: exit 3
ok - E3 verdict=salvaged_green
ok - E3 salvaged_green: exit 0
ok - E4 verdict=salvaged_red suite_rc=7
ok - E4 salvaged_red: exit 1
ok - E5 verdict=nothing_to_salvage carried=0/0
ok - E5 nothing_to_salvage: exit 0
ok - E6 unknown lane: FATAL
ok - E6 unknown lane: no SALVAGE_RESULT line
ok - E6 unknown lane: exit 2
ok - E7 --help lists '0 = salvaged_green'
ok - E7 --help lists '1 = salvaged_red'
ok - E7 --help lists '3 = conflict'
ok - E7 --help lists '2 = usage'
ok - E7 --help: exit 0
ok - E8 exit code agrees with printed verdict (5/5 runs)
salvage-exit-codes: pass=20 fail=0
```
Runtime 5.7 s (target < 60 s).

### 3.2 Red run — mutation `conflict) return 3` → `return 0` (verbatim)

Mutation applied INSIDE `main()`'s body at `:449` by a /tmp python patcher asserting exactly
one occurrence (`conflict)                          return 3 ;;`), applied after code commit
`4adad6b1`:

```
$ bash plugins/leadv2/scripts/tests/test-lane-salvage-exit-codes.sh
ok - bash -n leadv2-lane-salvage.sh (incl. 3.2)
ok - E1 verdict=conflict carried=0/1, branch dropped
FAIL - E1 conflict at first pick: rc=0 (want 3)
ok - E2 verdict=conflict carried=1/2, prefix branch kept
FAIL - E2 conflict after one carried pick: rc=0 (want 3)
ok - E3 verdict=salvaged_green
ok - E3 salvaged_green: exit 0
ok - E4 verdict=salvaged_red suite_rc=7
ok - E4 salvaged_red: exit 1
ok - E5 verdict=nothing_to_salvage carried=0/0
ok - E5 nothing_to_salvage: exit 0
ok - E6 unknown lane: FATAL
ok - E6 unknown lane: no SALVAGE_RESULT line
ok - E6 unknown lane: exit 2
ok - E7 --help lists '0 = salvaged_green'
ok - E7 --help lists '1 = salvaged_red'
ok - E7 --help lists '3 = conflict'
ok - E7 --help lists '2 = usage'
ok - E7 --help: exit 0
FAIL - E8 verdict=conflict exited rc=0 (want 3)
FAIL - E8 verdict=conflict exited rc=0 (want 3)
salvage-exit-codes: pass=17 fail=4
SUITE_RC=1
```

The mutation reddens exactly the conflict cases (E1, E2) and the agreement arm (E8, twice —
one row per recorded conflict run), each FAIL line carrying `rc=0 (want 3)`.

Restore: `git checkout -- plugins/leadv2/scripts/leadv2-lane-salvage.sh`; `git diff --stat`
→ empty; re-run green → `pass=20 fail=0`, `SUITE_RC=0`.

### 3.3 leadv2-mutation-control.sh artifact (gate-accepted proof)

```
$ bash plugins/leadv2/scripts/leadv2-mutation-control.sh \
    plugins/leadv2/scripts/tests/test-lane-salvage-exit-codes.sh \
    plugins/leadv2/scripts/leadv2-lane-salvage.sh \
    's/conflict)                          return 3 ;;/conflict)                          return 0 ;;/' \
    docs/handoff/SALVAGE-EXITS-ZERO-ON-CONFLICT-01
leadv2-mutation-control: snapshot=head_plus_declared declared=2 excluded_dirty=0
MUTATION-CONTROL ok suite=plugins/leadv2/scripts/tests/test-lane-salvage-exit-codes.sh \
  file=plugins/leadv2/scripts/leadv2-lane-salvage.sh \
  red_line=FAIL - E1 conflict at first pick: rc=0 (want 3) \
  diff_hash=04ef44d463ed5538ca69fd66d41eab663dd3c0db2bd3a9bc5d5d667408016228 \
  lane_diff_hash=ec3a450e6f5ef0e8d4d3e992ff899f11ed789733a095debb12427e77e5d1d422
MC_RC=0
```

Artifact: `docs/handoff/SALVAGE-EXITS-ZERO-ON-CONFLICT-01/mutation-control/20260909T160738Z-94850.txt`
(committed force-added — `.gitignore:77 docs/handoff/*/*` drops it):
`baseline_rc=0 mutated_rc=1 red_line=FAIL - E1 conflict at first pick: rc=0 (want 3)`.

## 4. Acceptance: log_line — a zero-exit lane loop prints no OK for a conflict lane

Fixture (scratch repo, one clean lane + one conflict lane), loop `bash salvage "$l" && echo "OK $l"`:

```
$ bash /tmp/loop-demo.sh
OK GREENLANE
loop_done
DEMO_RC=0
```

No `OK CONFLICTLANE` — the 2026-09-04 "17 OK" shape (loop reported OK while every conflict
lane had exited 0) cannot recur: the conflict lane's rc=3 now fails the `&&`.

## 5. Callers — C4 grep re-run (verbatim)

`grep -rn leadv2-lane-salvage ~/Projects/leadv2` (excl `.git`, `worktrees`, `docs/handoff`):

```
plugins/leadv2/scripts/leadv2-land.sh:18:#     plugins/leadv2/scripts/leadv2-lane-salvage.sh, which owns REBASING
plugins/leadv2/scripts/leadv2-land.sh:242:    printf 'leadv2-land: REFUSED reason=behind_main: … Rebase the past with plugins/leadv2/scripts/leadv2-lane-salvage.sh (it carries stale lane commits onto salvage/%s …), then land THAT branch with this script.\n'
plugins/leadv2/scripts/leadv2-lane-salvage.sh:2,31,68,330  (the tool itself: header, usage, FATAL strings)
plugins/leadv2/scripts/tests/test-control-plane-merge.sh:15,27,37  (T4: rc=$? after unpiped $(bash …) — reads rc)
plugins/leadv2/scripts/tests/test-leadv2-land.sh:154  (string assert on the refusal text only)
plugins/leadv2/scripts/tests/test-lane-salvage.sh:7,10,41,683,685  (runner helper: rc captured via file, no pipe)
tests/test-run-all-self-registration.sh:335  (frozen pre-migration trigger-map row, not edited)
docs/WAVES.md:58, docs/leadv2/scheduled-decisions.md:501, docs/audits/scope-changed-deterministic.md:50  (prose)
```

Other repos (`persona-engine`, `m3-market`, `respiro-ios`, `~/.claude/leadv2-shared`, whole
trees excl `.git`/`node_modules`): every hit is prose in `docs/` (task rows, WAVES.md, handoff
missions inside persona-engine worktrees); **zero code callers**. m3-market, respiro-ios and
`~/.claude/leadv2-shared` have no hits at all.

Conclusion: **no production caller executes the tool, so there is no rc-swallowing to fix**
(mission item 2 closes as "no caller"). No new caller appeared from the parallel В0 lanes —
`leadv2-land.sh` still references the tool in a comment and a refusal message only.
The new suite reads rc unpiped via file capture (`_run_salvage`).

## 6. Falsification set

```
$ bash -n plugins/leadv2/scripts/leadv2-lane-salvage.sh && echo "bash -n OK"
bash -n OK
$ bash -n plugins/leadv2/scripts/tests/test-lane-salvage-exit-codes.sh && echo "bash -n OK"
bash -n OK
```
No Python files changed — `py_compile` n/a.

Changed-scope runner (foreground, worktree `c65d77ed1b3c`, base `main@b94ca7be56`, 2 changed
files, range non-degenerate — 2 commits ahead of main):

```
$ bash tests/run-all.sh --scope changed
[CORE-OFFLINE] scope=changed running 4 of 95 suites (base=main@b94ca7be56, 2 changed files, 0 unmapped)
[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-control-plane-merge.sh (scope-selected ad-hoc)
[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-lane-salvage-exit-codes.sh (scope-selected ad-hoc)
[PASS] …/run-core-offline.sh
[PASS] …/tests/test-status-surface-bash32.sh
[PASS] …/tests/test-status-surface-single-lead.sh
[PASS] …/tests/test-status-surface-fast-names.sh
[PASS] …/test-control-plane-merge.sh
[PASS] …/test-lane-salvage-exit-codes.sh
[PASS] …/test-lane-salvage.sh
run-all: 7 passed, 0 failed, scope=changed
RUN_ALL_RC=0
```

The new suite self-selected via its `run-all-triggers` header (selection proof above) —
DoD gate item (c) satisfied by the discovery mechanism itself, not by assertion.

## 7. LEAD_ACTION (out-of-scope findings, per prepass §7)

1. `docs/handoff/WAVE-B1-SALVAGE-THE-SEVENTEEN-01/mission.md:31` tells the operator to look
   for **`verdict=ok`** — a value the tool has never emitted (it emits `salvaged_green`).
   Doc drift was a real contributing cause of the 2026-09-04 false-OK loop and lives outside
   this lane's write set. Fix to `verdict=salvaged_green` (or "rc 0").
2. Task row `c65d77ed1b3c` intent is stale w.r.t. `eabf35f6`: item 1's rc mapping landed in
   the sibling lane on 2026-09-04; record that this lane delivered R1 (`--help` table) + R2
   (suite + negative control) + the callers census.

## 8. Non-goals preserved

- rc mapping, verdict vocabulary, `SALVAGE_RESULT` line format untouched (three suites pin them;
  only the `--help` line changed in production code).
- `test-control-plane-merge.sh`, `test-lane-salvage.sh`, `test-run-all-self-registration.sh`,
  `tests/run-all.sh` not edited.
- Off-limits files (`leadv2-deploy-merge.sh`, `leadv2-active-registry.sh`, `lib/*`,
  `leadv2-state-path.sh`, `scripts/waves-refresh.sh`) untouched — zero hunks.
- No env vars, wrappers, or configuration introduced.
