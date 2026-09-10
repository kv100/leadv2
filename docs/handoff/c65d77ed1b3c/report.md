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

## 9. Round 2 (2026-09-10) — verification-and-filing: `round1-red.txt` filed, zero code diff

Design: architect prepass round 2 (mechanism-closed, base_head `7ac957d4`). Its census HELD
(measured, §9.3/§9.6): every mission item was already in main; the only open deliverable was
the negative-control filing. **This round changed zero bytes of code** — `git diff --stat
7ac957d4..HEAD -- plugins/ tests/` is empty; the diff is docs-only.

### 9.1 Unmutated suite (verbatim; rc captured UNPIPED — stdout redirected to a file)

```
$ bash plugins/leadv2/scripts/tests/test-lane-salvage-exit-codes.sh > /tmp/salvage-green-58081.txt 2>&1
$ rc=$?   # captured on the next line, never through a pipe
$ echo "rc=$rc"; cat /tmp/salvage-green-58081.txt
rc=0
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
<!-- bash-guard: allow -->
### 9.2 `round1-red.txt` — negative control, red run (the filed artifact)

Path: `docs/handoff/c65d77ed1b3c/round1-red.txt`, committed force-added (`.gitignore:77
docs/handoff/*/*` drops it), and copied to the main checkout's handoff dir per prepass R3.
Procedure per prepass §5.3: `plugins/leadv2/scripts/` copied to a scratch dir
(`/tmp/salvage-mut.bQEF9y`), the patcher asserted EXACTLY ONE matching arm
(`:449  conflict) return 3 ;;` inside `main()`) before replacing it with `return 0 ;;`;
the tree was never mutated. Mutated rc=1. Unmutated control, same suite, same
tree: `pass=20 fail=0`, rc 0 (§9.1) — the declared mutation flips exactly the
four conflict-rc assertions and nothing else. Suite output verbatim (pasted from
`/tmp/salvage-mut.bQEF9y/red.txt` with `cat`, not retyped):

```
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
```
Exactly the four FAIL lines the prepass predicted (E1, E2, E8 ×2), each ending
`rc=0 (want 3)`; 17 unrelated assertions stay green.
<!-- bash-guard: allow -->
### 9.3 Caller grep re-run (verbatim, byte-accurate: appended by the command itself)

```
plugins/leadv2/scripts/leadv2-lane-salvage.sh:2:# leadv2-lane-salvage.sh — LANE-SALVAGE-TOOL-01
plugins/leadv2/scripts/leadv2-lane-salvage.sh:31:#   leadv2-lane-salvage.sh <lane-id> [--force] [--suite-timeout <sec>]
plugins/leadv2/scripts/leadv2-lane-salvage.sh:68:_slv_fatal() { printf 'leadv2-lane-salvage: FATAL %s\n' "$*" >&2; exit 2; }
plugins/leadv2/scripts/leadv2-lane-salvage.sh:185:  WT="$(mktemp -d "${TMPDIR:-/tmp}/lane-salvage.${LANE_ID}.XXXXXX")"
plugins/leadv2/scripts/leadv2-lane-salvage.sh:221:  t="$(mktemp -d "${TMPDIR:-/tmp}/lane-salvage-union.XXXXXX")"
plugins/leadv2/scripts/leadv2-lane-salvage.sh:330:  [[ -n "${LANE_ID}" ]] || _slv_fatal "usage: leadv2-lane-salvage.sh <lane-id> [--force] [--suite-timeout <s>] [--log-dir <dir>]"
plugins/leadv2/scripts/leadv2-lane-salvage.sh:361:  pick_err="$(mktemp "${TMPDIR:-/tmp}/lane-salvage-pick.XXXXXX")"
plugins/leadv2/scripts/leadv2-land.sh:18:#     plugins/leadv2/scripts/leadv2-lane-salvage.sh, which owns REBASING
plugins/leadv2/scripts/leadv2-land.sh:242:    printf 'leadv2-land: REFUSED reason=behind_main: %s is %s commit(s) behind %s (LEADV2_LAND_MAX_BEHIND=%s). Rebase the past with plugins/leadv2/scripts/leadv2-lane-salvage.sh (it carries stale lane commits onto salvage/%s from current %s), then land THAT branch with this script.\n' \
plugins/leadv2/scripts/tests/test-lane-salvage-exit-codes.sh:3:# run-all-triggers: leadv2-lane-salvage.sh
plugins/leadv2/scripts/tests/test-lane-salvage-exit-codes.sh:4:# test-lane-salvage-exit-codes.sh — SALVAGE-EXITS-ZERO-ON-CONFLICT-01
plugins/leadv2/scripts/tests/test-lane-salvage-exit-codes.sh:30:SALVAGE="${SCRIPT_DIR}/../leadv2-lane-salvage.sh"
plugins/leadv2/scripts/tests/test-lane-salvage-exit-codes.sh:74:# kept in lockstep with leadv2-lane-salvage.sh's own exit-code case.
plugins/leadv2/scripts/tests/test-lane-salvage-exit-codes.sh:259:  _fail "bash -n leadv2-lane-salvage.sh"
plugins/leadv2/scripts/tests/test-lane-salvage-exit-codes.sh:261:  _ok "bash -n leadv2-lane-salvage.sh (incl. 3.2)"
plugins/leadv2/scripts/tests/test-control-plane-merge.sh:15:#   T4  leadv2-lane-salvage.sh's exit code carries the verdict:
plugins/leadv2/scripts/tests/test-control-plane-merge.sh:27:# run-all-triggers: leadv2-lane-salvage.sh leadv2-merge-old-branch.sh leadv2-control-plane-merge-driver.sh
plugins/leadv2/scripts/tests/test-control-plane-merge.sh:37:SALVAGE="${PLUGIN_DIR}/scripts/leadv2-lane-salvage.sh"
plugins/leadv2/scripts/tests/test-leadv2-land.sh:154:  assert_contains "b: refusal names lane-salvage" "$err" "leadv2-lane-salvage.sh"
plugins/leadv2/scripts/tests/test-lane-salvage.sh:7:# run-all-triggers: leadv2-lane-salvage.sh
plugins/leadv2/scripts/tests/test-lane-salvage.sh:8:# test-lane-salvage.sh — LANE-SALVAGE-TOOL-01
plugins/leadv2/scripts/tests/test-lane-salvage.sh:10:# Hermetic git-sandbox fixtures for leadv2-lane-salvage.sh. Every case is a
plugins/leadv2/scripts/tests/test-lane-salvage.sh:41:SALVAGE="${SCRIPT_DIR}/../leadv2-lane-salvage.sh"
plugins/leadv2/scripts/tests/test-lane-salvage.sh:54:  tmp="$(mktemp -d "${TMPDIR:-/tmp}/lane-salvage-fixture.XXXXXX")"
plugins/leadv2/scripts/tests/test-lane-salvage.sh:111:FLAG="$(git rev-parse --git-common-dir)/lane-salvage-test-hook-fired"
plugins/leadv2/scripts/tests/test-lane-salvage.sh:627:  if ! git -C "$repo" worktree list --porcelain 2>/dev/null | grep -q 'lane-salvage\.LANE9'; then
plugins/leadv2/scripts/tests/test-lane-salvage.sh:683:  _fail "bash -n leadv2-lane-salvage.sh"
plugins/leadv2/scripts/tests/test-lane-salvage.sh:685:  _ok "bash -n leadv2-lane-salvage.sh (incl. 3.2)"
plugins/leadv2/scripts/tests/test-lane-salvage.sh:700:printf 'lane-salvage: pass=%d fail=%d\n' "$PASS" "$FAIL"
tests/test-run-all-self-registration.sh:335:leadv2-lane-salvage.sh:plugins/leadv2/scripts/tests/test-lane-salvage.sh
docs/leadv2/scheduled-decisions.md:501:Проба ведущей 2026-09-04. Инструмент `leadv2-lane-salvage.sh` (линия LANE-SALVAGE-TOOL-01,
docs/audits/scope-changed-deterministic.md:50:- `leadv2-lane-salvage.sh:299,306`: fresh worktree, no checkpoint → first run
```

Classification vs prepass §1 — same six files, same roles, **no new invocation**:
- `leadv2-land.sh` refusal text sits at `:242` here vs `:272` in the prepass (and
  `test-leadv2-land.sh:154` vs `:155`): the prepass grepped the main checkout, whose main
  is 159 commits ahead of this lane's merge-base (`7ac957d4`); `leadv2-land.sh` grew
  upstream between the two trees. Same two roles (comment + refusal message), never executes
  the tool.
- Two prose hits the prepass table did not list: `docs/leadv2/scheduled-decisions.md:501`
  and `docs/audits/scope-changed-deterministic.md:50` — narrative/doc references, no
  execution, no rc consumption. Not callers.
- Self-hits inside `leadv2-lane-salvage.sh` (usage text, mktemp templates) — the tool itself.

### 9.4 `--help` rendered table (acceptance: rendered_line; `--help` rc=0)

```
  salvaged_green     all work commits carried AND run-all exited 0
  salvaged_red       carried, but run-all exited non-zero (or timed out)
  conflict           a pick conflicted outside the auto-resolvable shape
  nothing_to_salvage no non-anchor, non-merge commits ahead of merge-base

Exit codes (CONTROL-PLANE-FILES-CONFLICT-ON-EVERY-OLD-BRANCH-01): the exit
code now CARRIES the verdict — a record that says "conflict" must never be
read as success by a caller that only checks $?
  0 = salvaged_green | nothing_to_salvage
  1 = salvaged_red (carried, but run-all exited non-zero or timed out)
  3 = conflict (a pick conflicted outside the auto-resolvable shape)
  2 = usage / environment error (no verdict), incl. main-moved invariant
```

### 9.5 Falsification set (round 2)

```
$ bash -n plugins/leadv2/scripts/leadv2-lane-salvage.sh && echo "bash -n OK"
bash -n OK
$ bash -n plugins/leadv2/scripts/tests/test-lane-salvage-exit-codes.sh && echo "bash -n OK"
bash -n OK
```
No shell or Python file changed this round (zero code diff) — re-checked anyway.
`py_compile` n/a. Changed-scope runner and mutation-control re-run: §9.8 (post-commit,
they bind to committed HEAD).

### 9.6 Census check vs the round-2 design (PREPASS-MECHANISM-CLOSURE-01)

No falsification found: no caller the design missed (§9.3), no return-code consequence
differing from design §1/§2, no configuration state missed that this lane's invariant
touches. The two §3 sharp edges (`--suite-timeout 0` = unbounded; unwritable TMPDIR
reported as `conflict`) stay filed as backlog per design §5(4)c — deliberately untouched.

### 9.7 Lane state (round 2)

- Code diff vs `7ac957d4`: **zero** (`git diff --stat 7ac957d4..HEAD -- plugins/ tests/`
  will read empty once §9 is committed — this round touches docs only).
- Docs committed: `round1-red.txt` (force-added, gitignored by `.gitignore:77`), this §9,
  and the dispatcher's round-2 refresh of the tracked `docs/handoff/c65d77ed1b3c/brief.md`
  (committed to keep the lane clean for salvage; it is the round-2 mission text, not a
  lane edit).

### 9.8 Post-commit gates (appended after the docs commit)

```
$ bash tests/run-all.sh --scope changed   # foreground, rc captured unpiped
[CORE-OFFLINE] scope=changed running 0 of 95 suites (base=main@7ac957d427, 0 changed files, 0 unmapped)
[CORE-OFFLINE] SCOPE_RESULT selected=0 total=95 base=main@7ac957d427 changed=0 unmapped=0 verdict=nothing_to_run reason=no_relevant_changed_files
[PASS] …/run-core-offline.sh
[PASS] …/test-status-surface-bash32.sh
[PASS] …/test-status-surface-single-lead.sh
[PASS] …/test-status-surface-fast-names.sh
run-all: 4 passed, 0 failed, scope=changed
RUN_ALL_RC=0
```
Selection is empty BY CONSTRUCTION this round: base `main@7ac957d427` == the pre-round-2
HEAD, and the round-2 diff is docs-only, so no trigger-mappable file changed. The
code-relevant proof is carried by the direct runs above (§9.1 green `pass=20 fail=0` rc=0;
§9.2 red `pass=17 fail=4` rc=1) and by round 1's changed-scope run over the actual code
range (§6: 7 passed incl. `test-lane-salvage-exit-codes.sh`).

### 9.9 mutation-control re-run (after the last non-artifact commit `8da8200c`)

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
  lane_diff_hash=8e2e6460580a0e1d84404216fba330877982ccf70996ce92122d9c5f887e4e73
MC_RC=0
```
Artifact: `docs/handoff/SALVAGE-EXITS-ZERO-ON-CONFLICT-01/mutation-control/20260910T182602Z-90301.txt`
(force-added; gitignored). Same `diff_hash` as round 1 (the mutated file is byte-identical);
`lane_diff_hash` re-binds to the round-2 committed HEAD.

Round 2 complete: negative control RUN and FILED; every acceptance observable of the
round-2 design is evidenced above; zero code diff.

## 10. Round-2 gates (resumed run, 2026-09-10 late) — e2e rerun + gate-runner decision

### 10.1 End-to-end gate: changed-scope rerun at HEAD `885bae1`

`bash tests/run-all.sh --scope changed` (foreground, rc captured unpiped):

```
[CORE-OFFLINE] scope=changed running 0 of 95 suites (base=main@7ac957d427, 0 changed files, 0 unmapped)
[CORE-OFFLINE] SCOPE_RESULT selected=0 total=95 base=main@7ac957d427 changed=0 unmapped=0 verdict=nothing_to_run reason=no_relevant_changed_files
[PASS] …/run-core-offline.sh
[PASS] …/test-status-surface-single-lead.sh
[PASS] …/test-status-surface-fast-names.sh
[FAIL] tests/test-status-surface-bash32.sh   # [SUITE-TIMEOUT] exceeded 600s ceiling
run-all: 3 passed, 1 failed, scope=changed    RUN_ALL_RC=1
```

The bash32 red is **concurrent-runner contention, not this lane's diff** (the changed
range is docs-only; selection is empty). At the moment of the run, >=3 foreign lanes were
running their own changed-scope suites (`b35ad780ea1d`, `JOURNAL-PHASE-SILENT-RC0-01`,
`REGISTRY-SILENT-RC0-01` — pids observed live), each invoking the same
`leadv2-status-surface.5s.sh` wrapper with `LEADV2_STATUS_SYNC=1` against the shared
registry. A/B proof — same suite, same tree, quiet window (22:15:30, no foreign
status-surface process live):

```
$ gtimeout 420 bash tests/test-status-surface-bash32.sh
test-status-surface-bash32: 16 passed, 0 failed, 0 skipped      # rc 0
```

Red under contention, green isolated => environmental (matches the recorded
core-offline-reds-under-concurrent-runners failure mode). Code-relevant proof for this
lane remains the direct runs: §9.1 green `pass=20 fail=0` rc 0, §9.2/§3.2 red
`pass=17 fail=4` rc 1.

### 10.2 Why the standalone `leadv2-phase8-e2e-gate.sh` stamper was NOT run

Round 1's code is already merged into `main` (merge-base `7ac957d4`), and round 2 wrote
only docs. The stamper's `lv2_lane_diff_is_empty` checks LANE_WRITES (the two code
files) against merge-base..HEAD — unchanged — so it would false-refuse `no_work`, delete
the round-1 `e2e-gate-passed.flag`, and overwrite `review-gate.md` with
`blocked/no_work`, destroying a true pass record. The e2e substance (changed-scope run)
was executed directly instead (§10.1). The lead's close pipeline, which resolves the
lane-start base rather than merge-base, remains the authoritative stamper.

### 10.3 Report + mutation-control consolidated into `docs/handoff/c65d77ed1b3c/`

The review engine's DoD gate requires one task dir holding `brief.md`, `report.md`, and
`mutation-control/`. They were split (`brief.md` here; report+MC under
`docs/handoff/SALVAGE-EXITS-ZERO-ON-CONFLICT-01/`), which made every paste-evidence
check fail against a report-less task dir (measured: `dod_fail paste_evidence_missing
brief_line=27,31`). `report.md` moved by `git mv` (history preserved); the MC artifacts
moved with it and were re-force-added. §3.3/§9.9 path references predate the move.

### 10.4 Cross-provider review gate (round 2)

Re-run via `leadv2-review-run.sh` over `review-r2.diff` = `git diff 7ac957d4..HEAD`
(the full round-2 docs range). Verdict: `docs/handoff/dispatch-b9fd9799/review-gate.md`.
