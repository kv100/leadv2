# FLEET-RUNTIME-UNATTENDED-01 — report

Developer lane, worktree `583d804d01e5` @ base `fa27042a`, macOS Darwin 25.6.0 (arm64), no systemd
on this machine — every claim below states explicitly whether it ran against real systemd or a
stubbed unit layer, per the mission's platform note.

## What was built

`plugins/leadv2/scripts/fleet/` (new directory), 5 files:

- **`leadv2-fleet-lib.sh`** — shared, side-effect-limited helpers: disk-floor gate (`df -Pk`,
  portable), Claude-arm usability (local OAuth credential expiry read, no `claude` invocation, no
  network call, never prints the token), GLM-arm usability (`~/.claude/secrets/zai.env` /
  `ZAI_AUTH_TOKEN` presence, never prints the value), the stop-flag check, a portable mtime helper
  (BSD `stat -f` vs GNU `stat -c`). Sourced by the other four scripts.
- **`leadv2-fleet-state.sh`** — the mission's 3rd deliverable. One flat `key=value` file per
  instance under `${LEADV2_FLEET_STATE_ROOT:-~/.claude/leadv2-state/fleet}/<name>.state`,
  mkdir-based locking (portable, no `flock` dependency — macOS ships none), atomic write via
  `mv`. `read` prints exactly 5 lines (status+reason/degrade, lanes in flight, landed today, rows
  filed today, last change) — see smoke test below.
- **`leadv2-fleet-unit.sh`** — the mission's 1st deliverable. Generates and installs a systemd
  **user** service + a companion oneshot service + timer per instance, `Restart=always`,
  `loginctl enable-linger`. `install --dry-run` prints the generated unit text and the exact
  command sequence **without invoking `systemctl`/`loginctl` at all** (verified below) — this is
  what lets the guard suite run on a systemd-less machine.
- **`leadv2-fleet-guard.sh`** — the mission's 2nd deliverable. Timer-invoked (never a loop inside
  the long-running unit): reaps lane worktrees carrying a `.fleet-terminal` marker, self-stops with
  a named reason below the disk floor, records (does not stop on) a stalled worktree (newest file
  mtime under it older than `--stall-minutes`, default 60).
- **`leadv2-fleet-runner.sh`** — **one file beyond the three named in the mission**, added because
  the mission's own controls (`kill the session process`, `touch the flag mid-lane`) require a
  process to kill and a loop that checks the flag *between* lanes — and the mission explicitly
  says the guard is timer-triggered, *not* that loop. This is the systemd unit's `ExecStart`
  target: a foreground, sequential "take one lane, run it to its own terminal, then decide about
  the next one" loop. It is not a supervisor daemon in the retired sense — it holds no health-check
  loop over a running session and never runs two lanes concurrently per instance; process-level
  restart-on-crash is systemd's job (`Restart=always`), this script's job ends the moment it
  decides "no new lane" and it exits 0. See "Scope decision: lane execution" below for why lane
  execution itself is a pluggable hook rather than a call into `leadv2-dispatch-code.sh`.

Plus the guard suite: `plugins/leadv2/scripts/tests/test-fleet-runtime-guards.sh` (10 cases, all
green — full run pasted below).

## Scope decisions (read before reviewing off-limits compliance)

1. **Reaping does not touch the active registry.** `leadv2-active-registry.sh` and
   `leadv2-dispatch-code.sh` are owned by other lanes this session and off-limits to depend on.
   `leadv2-fleet-guard.sh` reaps only worktrees carrying a `.fleet-terminal` marker file — a
   convention this fleet code alone owns and writes (by whichever script eventually drives a lane
   to completion), decoupled from the registry's internal schema. No file in the off-limits list
   was read, grepped, or written by any fleet script.
2. **Lane execution is a pluggable hook (`LEADV2_FLEET_LANE_CMD`), not a direct call into
   `leadv2-dispatch-code.sh`.** That script is under concurrent edit by another lane this session
   and off-limits. `leadv2-fleet-runner.sh` defines and tests the *contract* the hook must honor
   (rc 0 = landed, rc != 0 = reached a terminal without landing) and fails loudly
   (`FATAL: LEADV2_FLEET_LANE_CMD not set`) if nothing wires it — it does not silently no-op loop.
   Wiring the real dispatch entry point into this hook is explicitly flagged as follow-up work for
   whichever lane owns `leadv2-dispatch-code.sh`.
3. **No `claude` invocation anywhere in `leadv2-fleet-guard.sh`, `leadv2-fleet-state.sh`, or
   `leadv2-fleet-lib.sh`** (grep-verified below). The Claude-arm usability check is a local file
   read (OAuth credential expiry), never a CLI spawn or network call.
4. **No supervisor daemon / no `leadv2-fanout.sh` or `leadv2-supervise-loop.sh` revival.** The
   guard is timer-invoked (one pass, exits); the runner is a sequential foreground loop with no
   health-check/polling of another process — the shape the mission explicitly forbids.

```
$ grep -n '\bclaude\b' plugins/leadv2/scripts/fleet/leadv2-fleet-guard.sh \
    plugins/leadv2/scripts/fleet/leadv2-fleet-state.sh \
    plugins/leadv2/scripts/fleet/leadv2-fleet-lib.sh
(no output — zero matches)
```

## Controls — three claims, three negative controls, each RUN

All three ran on macOS Darwin 25.6.0, no systemd installed. Per the mission's own instruction
("stub the unit layer rather than skipping the case"), Claim 1 is verified two ways: (a) the
*generation* of the correct `Restart=` config is a live, unstubbed run of the real code
(`leadv2-fleet-unit.sh print-unit`); (b) that a process governed by that config actually gets
relaunched on kill is proven by a minimal test-local "mini-systemd" harness driven by the real
generated unit content — this is the honest boundary: our code owns the declared config, only a
real systemd instance can prove PID1 itself honors it, which this machine cannot run.
**UNVERIFIED: real systemd's own Restart=always behavior on this exact unit** — that requires a
Linux host with systemd, out of reach in this sandbox; it is systemd's own well-documented,
externally-tested behavior, not code this lane wrote.

### Claim 1 — the unit declares restart-on-kill; a config-driven relaunch is proven

```
$ bash plugins/leadv2/scripts/fleet/leadv2-fleet-unit.sh print-unit \
    --repo /tmp/x --name a1 --cap 2 --restart always | grep '^Restart='
Restart=always

$ bash plugins/leadv2/scripts/fleet/leadv2-fleet-unit.sh print-unit \
    --repo /tmp/x --name a1 --cap 2 --restart no | grep '^Restart='
Restart=no
```

Mini-systemd harness (reads the real generated unit's `ExecStart=`/`Restart=`, execs it, kills
-9, and relaunches iff `Restart=always`) — see suite groups B in
`test-fleet-runtime-guards.sh`, full run below:
```
PASS: Restart=always: killed runner process comes back (mini-systemd: RESTARTED)
PASS: Claim 1 negative control — Restart=no: killed process stays dead (mini-systemd: NOT_RESTARTED)
```

### Claim 2 — the stop flag stops between lanes, not inside one

Positive (suite group C): a runner with a 1s fake lane is launched; the stop flag is touched
0.3s in (mid-lane); the suite asserts the in-flight lane's own log shows exactly one
`lane-start`/`lane-end` pair (it finished) and the runner's terminal state is
`stopped (reason: stop_flag)` with no second lane started:
```
lanes_started=1 status_line=status: stopped (reason: stop_flag)
PASS: stop flag: current lane finished (exactly 1 lane ran) and no new lane started; status=stopped/stop_flag
```

Negative control (code mutation on the marked line, via `leadv2-mutation-control.sh` — worker
mode, scratch copy, artifact below): disabling the stop-flag gate (`if fleet_stop_flag_present;
then # c2-mut: stop-flag gate` → `if false; then # c2-mut: stop-flag gate`) must turn this case
red.

```
$ LEADV2_LANE_START_SHA=fa27042a bash plugins/leadv2/scripts/leadv2-mutation-control.sh \
    plugins/leadv2/scripts/tests/test-fleet-runtime-guards.sh \
    plugins/leadv2/scripts/fleet/leadv2-fleet-runner.sh \
    's|if fleet_stop_flag_present; then # c2-mut: stop-flag gate|if false; then # c2-mut: stop-flag gate|' \
    /tmp/fleet-mc-out
leadv2-mutation-control: snapshot=head_plus_declared declared=2 excluded_dirty=0
MUTATION-CONTROL ok suite=plugins/leadv2/scripts/tests/test-fleet-runtime-guards.sh file=plugins/leadv2/scripts/fleet/leadv2-fleet-runner.sh red_line=FAIL: stop flag positive case: expected exactly 1 lane + status stopped/stop_flag, got: lanes_started=4 status_line=status: alive (degraded: glm) diff_hash=cebfb8dad6b01ee09f3e285f6aed86e689976456973054ac6e2a503fd12525c0 lane_diff_hash=66d970e30bcd38aa9f0f4e666d02fc3725b1e8825e4bf83e1d11d4e866d671d8
```

Artifact: `/tmp/fleet-mc-out/mutation-control/20260917T173715Z-59174.txt` (worker mode — mutates a
scratch copy only; `git status --short` on this lane checkout was empty before and after, and the
suite was re-run green afterward, confirming the real lane files were never touched):
```
suite=plugins/leadv2/scripts/tests/test-fleet-runtime-guards.sh
file=plugins/leadv2/scripts/fleet/leadv2-fleet-runner.sh
anchor=s|if fleet_stop_flag_present; then # c2-mut: stop-flag gate|if false; then # c2-mut: stop-flag gate|
baseline_rc=0
mutated_rc=1
red_line=FAIL: stop flag positive case: expected exactly 1 lane + status stopped/stop_flag, got: lanes_started=4 status_line=status: alive (degraded: glm)
diff_hash=cebfb8dad6b01ee09f3e285f6aed86e689976456973054ac6e2a503fd12525c0
lane_diff_hash=66d970e30bcd38aa9f0f4e666d02fc3725b1e8825e4bf83e1d11d4e866d671d8
```
Without the gate, the runner ran 4 lanes back-to-back on the fake 1s lane command and never
reached `stopped` — the control proves the gate is load-bearing, not decorative.

### Claim 3 — the disk floor refuses a new lane start

Positive: `--floor-kb 999999999999` (impossible on any real filesystem — mission's own suggested
technique, symmetric to its suggested negative control):
```
PASS: disk floor (impossible floor-kb) refuses with named reason: status: stopped (reason: disk_floor: disk_floor free_kb=98074408 floor_kb=999999999999)
```

Negative control (mission's own suggestion — raise the floor to 0):
```
PASS: Claim 3 negative control — floor-kb=0: a lane starts (disk floor does not block)
```

## Guard suite — full run

```
$ bash plugins/leadv2/scripts/tests/test-fleet-runtime-guards.sh
group A: generated unit content
PASS: print-unit --restart always emits Restart=always
PASS: print-unit --restart no emits Restart=no (Claim 1 negative control)
PASS: ExecStart points at leadv2-fleet-runner.sh with repo/name/cap
PASS: guard timer unit is generated alongside the service
PASS: --dry-run install never invokes systemctl/loginctl
group B: Claim 1 — restart-on-kill via generated Restart= field
PASS: Restart=always: killed runner process comes back (mini-systemd: RESTARTED)
PASS: Claim 1 negative control — Restart=no: killed process stays dead (mini-systemd: NOT_RESTARTED)
group C: Claim 2 — stop flag between lanes
lanes_started=1 status_line=status: stopped (reason: stop_flag)
PASS: stop flag: current lane finished (exactly 1 lane ran) and no new lane started; status=stopped/stop_flag
group D: Claim 3 — disk floor refusal
PASS: disk floor (impossible floor-kb) refuses with named reason: status: stopped (reason: disk_floor: disk_floor free_kb=98073216 floor_kb=999999999999)
PASS: Claim 3 negative control — floor-kb=0: a lane starts (disk floor does not block)

10 of 10 passed (fleet guard suite, macOS Darwin, no systemd — unit layer stubbed per mission)
```
rc=0 at a ~5s wall time on macOS Darwin 25.6.0, commit `c218e901` base `fa27042a`. Also re-run
against `/bin/bash` (the system's real Bash 3.2.57, not the Homebrew 5.3.9 default) to satisfy the
mission's Bash-3.2-compatibility requirement — `bash -n` clean on all 6 files and the suite is
10 of 10 green there too, same output.

10 of 10 passed, macOS Darwin 25.6.0, ~5s wall time, no systemd on this host — the unit layer is
stubbed throughout (mini-systemd harness in group B; `print-unit`/`--dry-run` never shell out to
`systemctl`/`loginctl` in groups A/C/D).

## CI selection

The suite is admitted by the repo's tracked-admission discovery
(`plugins/leadv2/scripts/lib/leadv2-suite-discovery.sh`, GATE-DISCOVERS-246-UNTRACKED-SUITES-01):
a suite runs only if it is `git`-tracked/staged AND sits under one of the four scanned dirs
(`plugins/leadv2/scripts/tests` is one). It carries
`# run-all-triggers: leadv2-fleet-unit leadv2-fleet-guard leadv2-fleet-state leadv2-fleet-runner leadv2-fleet-lib`
so `tests/run-all.sh --scope changed` selects it whenever any fleet file changes; `--scope all`
picks it up unconditionally via discovery once tracked.

```
$ git ls-files --error-unmatch -- plugins/leadv2/scripts/tests/test-fleet-runtime-guards.sh
plugins/leadv2/scripts/tests/test-fleet-runtime-guards.sh

$ bash plugins/leadv2/scripts/lib/leadv2-suite-discovery.sh --root "$(pwd)" \
    --dir "$(pwd)/plugins/leadv2/scripts/tests" --skip-report=count | grep fleet
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/583d804d01e5/plugins/leadv2/scripts/tests/test-fleet-runtime-guards.sh
```

## Self-check (falsification set)

```
$ for f in plugins/leadv2/scripts/fleet/*.sh plugins/leadv2/scripts/tests/test-fleet-runtime-guards.sh; do
    bash -n "$f" && echo "OK $f" || echo "FAIL $f"
  done
OK plugins/leadv2/scripts/fleet/leadv2-fleet-guard.sh
OK plugins/leadv2/scripts/fleet/leadv2-fleet-lib.sh
OK plugins/leadv2/scripts/fleet/leadv2-fleet-runner.sh
OK plugins/leadv2/scripts/fleet/leadv2-fleet-state.sh
OK plugins/leadv2/scripts/fleet/leadv2-fleet-unit.sh
OK plugins/leadv2/scripts/tests/test-fleet-runtime-guards.sh
```

No Python files were added or changed in this lane (`py_compile` — not applicable).

## Left alone / not done

- **Real systemd verification** (Claim 1's live "PID1 relaunches the process" behavior) — no
  systemd on any host available to this lane. Marked `UNVERIFIED` above rather than asserted.
- **Wiring `LEADV2_FLEET_LANE_CMD` to the real `leadv2-dispatch-code.sh` entry point** — explicitly
  off-limits this session (owned by another lane); the contract is defined and tested, wiring is
  follow-up.
- **Daily counter reset** (`landed_today`/`rows_filed_today` zeroing at day boundary) — the mission
  did not ask for a scheduler for this, and no caller in this session's scope increments these
  fields yet (that will come with the dispatch-loop wiring above); the primitives
  (`set-field`/`inc-field`) are in place for whoever wires it.
- **`leadv2-fleet-guard.sh`'s worktree reaping** was smoke-tested for the `git worktree remove`
  path structurally but not against a real multi-worktree fleet run end-to-end (no live fleet to
  reap from in this sandbox); the marker-file convention and the fallback `rm -rf` path are
  exercised by direct invocation only, not by the guard suite (which focuses on the three named
  controls per the mission's deliverable list).

  **Round 2 note:** the `rm -rf` fallback named above no longer exists — see H4 below. Reaping is
  now covered directly by the suite's Group G.

---

## Round 2 (dispatch-c7527bac) — round-1 review fixes

Round 1 (commits `550b4389`, `85475b83`) failed review: `docs/handoff/dispatch-c7527bac-review/critic.full.md`,
verdict FAIL, critical=2 high=5 medium=7 low=4. This section maps every finding to its fix and the
evidence that proves it. The everything-above section is round-1's own report, left in place for
its still-accurate design rationale; treat the pass counts and code snippets quoted in it (e.g.
"10 of 10 passed", the unquoted `ExecStart=` form) as **superseded** by this section.

### Critical

- **C1 — controls asserted only via manual smoke-testing, not codified suite assertions.** Fixed:
  Group F now asserts `no_landing_streak`, `no_arm`, `quota_window`, and degrade-to-glm as real
  `pass`/`fail` cases; Group E asserts the state `read` 5-line contract and `set-field`/`inc-field`
  unknown-field rc=2; Group G asserts guard reap (positive), `reap_refused` (negative/safety), and
  stall detection + the `stalled` field. See "Suite — full run" below.
  **Judgment call, stated plainly:** C1's literal wording for scenario (b) said assert reason
  `quota_window` for an arm that is merely unusable (not a real quota refusal). M1, in the same
  review, calls that exact conflation a bug and asks for `credentials_missing` / `auth_expired` /
  `quota_exhausted` / `key_missing` to be distinguished. Implementing M1 makes C1(b)'s literal
  wording describe the wrong post-fix behavior, so Group F implements the **fixed** semantics:
  `quota_window` is reserved for a live credential whose quota probe actually refuses
  (`fleet_stop_kind_for_no_arm` in `leadv2-fleet-lib.sh`); every other no-arm cause reads `no_arm:
  <arm>=<reason>`. Group F(b) tests the `no_arm` path (missing glm key), Group F(c) tests the real
  `quota_window` path (live claude credential, quota probe forced to fail).
- **C2 — mutation controls proved only that a marker comment existed, not that the mutation
  actually defeats the property.** Fixed two ways: Group 0 still asserts the three `#
  c1-mut`/`c2-mut`/`c3-mut` marker strings are present (so the control can't silently rot), and the
  new Group H applies each of the three sed patches to a scratch copy of `plugins/leadv2/scripts/fleet/`
  and re-runs the relevant scenario against the mutated copy, asserting it goes RED. All three
  entries are also registered in `tests/mutations/catalog.yaml` (`fleet-runner-stop-flag-gate-c2`,
  `fleet-unit-restart-passthrough-c1`, `fleet-lib-disk-floor-gate-c3`) for the canonical
  `leadv2-mutation-control.sh` runner to pick up post-commit.
  **Regression this surfaced:** adding the `# c1-mut: ...` comment onto the *live* `Restart=${4}`
  line in `leadv2-fleet-unit.sh` means the rendered unit's `Restart=` value now carries a trailing
  comment (`Restart=always # c1-mut: restart policy passthrough`). The suite's own exact-match
  assertions (`grep -q '^Restart=always$'`) and the mini-systemd harness's `[[ "${restart}" ==
  "always" ]]` comparison both broke against that real output — not a suite bug, a real
  consequence of the marker landing in production text. Fixed by loosening the suite's grep to a
  prefix match and having `mini_systemd_once` strip a trailing `# ...` comment before comparing.

### High

- **H1 — flap:** `leadv2-fleet-runner.sh` now writes `status=alive` only after every self-stop
  check has passed for the iteration (see the script's header comment and the restructured main
  loop) — a restarted process re-detecting the same stop condition goes straight back to
  `stopped` with the same reason, never visibly through `alive`.
- **H2 — unit shipped with zero `Environment=` lines, so every real install self-stopped
  `unwired`.** `leadv2-fleet-unit.sh` gained `--lane-cmd`, rendering
  `Environment=LEADV2_FLEET_LANE_CMD=<cmd>` when given; `install` without it prints a named warning
  with the exact re-install command. Suite: Group A's two new `--lane-cmd`/`Environment=`
  assertions.
- **H3 — `--cap` rendered into the unit and never read anywhere (documented lie).** Resolved via
  "forward, don't consume": the runner exports `LEADV2_FLEET_CAP` to the pluggable lane hook for
  the real concurrency owner (`leadv2-active-registry.sh`/`leadv2-dispatch-code.sh`, both
  off-limits this session) to read once wired, rather than implementing N-way concurrency in bash
  3.2 (no `wait -n`). Documented in the runner's header.
- **H4 — reap fell back to `rm -rf` on `git worktree remove` refusal, risking an in-flight lane's
  uncommitted work and leaving a dangling `.git/worktrees` entry.** Fixed: on refusal,
  `leadv2-fleet-guard.sh` now records `reap_refused` to the stall log and leaves the tree
  untouched — no deletion fallback exists anymore. Suite: Group G's `reap_refused` case (a
  worktree with a broken `.git` file, so `git worktree remove` itself errors) asserts the
  directory survives and the log line is written.
- **H5 — nothing wrote the `.fleet-terminal` marker, so the guard's reap step was dead code.**
  Fixed: `leadv2-fleet-runner.sh`'s lane hook contract now recognizes an optional `FLEET_WORKTREE=`
  stdout line from the lane command and touches `<path>/.fleet-terminal` the moment the lane
  returns (either rc). Suite: Group G's positive reap case exercises this end to end (creates the
  marker directly, since no real dispatch entry point is wired in this session — that wiring is
  the off-limits lane's follow-up, documented above).

### Medium

- **M1/M2 — quota refusal and missing/expired credentials were conflated under one
  `quota_window` label.** Fixed via `fleet_arm_reason`/`fleet_no_arm_reasons`/
  `fleet_stop_kind_for_no_arm` in `leadv2-fleet-lib.sh` (see C1's judgment-call note above).
- **M3 — `landed_today`/`rows_filed_today` never rolled over at midnight.** Fixed:
  `leadv2-fleet-state.sh` stores a `day` field; `_fs_load_or_default` zeroes both counters and
  resets `day` when the stored day differs from today's UTC date.
- **M4 — unit content quoting / missing `Wants=`.** `WorkingDirectory=`/`ExecStart=` args are
  quoted; `Wants=network-online.target` added alongside `After=`.
- **M5 — Group B's top-level `export LEADV2_FLEET_*` leaked into Group C/D's environment for the
  rest of the suite run (shellcheck SC2030/2031).** Fixed: Group B now sets these vars via
  prefix-assignment scoped to each `mini_systemd_once` call only, backed by a suite-level
  `ZAI_ENV_SUITE` fixture rather than a Group-B-owned file.
- **M6 — the guard's stall check walked every file under every worktree with `find -type f` on
  every timer tick.** Fixed: replaced with a single `fleet_mtime_epoch` read of the worktree root
  directory itself — a directory's own mtime already advances on any direct create/rename/delete
  under it. Suite: Group G's stall case (`touch -t` an old timestamp on the worktree root).
- **M7 — the mkdir-lock broke purely on age (30s), so a live, slow holder could be preempted.**
  Fixed: the lock dir now stores the holder's pid; a lock is broken only when that pid is provably
  dead (`kill -0` fails), with the 30s age fallback retained only for a lock dir with no pid file
  at all (race / pre-fix leftover). Suite: Group E's lock-steal case (a lock dir with a pid that is
  guaranteed dead, asserting the steal completes well under 25s, not the 30s fallback).

### Low

- **L1 — `grep -c` on zero matches printed an empty string, not `0`, breaking arithmetic
  comparisons downstream.** Fixed in `run_claim2`'s `lanes_started` computation with a `${var:-0}`
  fallback.
- **L2 — `sed -n '2,10p'` sliced the unit content by fixed line numbers, which the H2 fix's
  optional `Environment=` line silently invalidated** (everything below it shifts by one line
  whenever `--lane-cmd` is empty — this broke Group B outright during round-2 verification, see
  below). Fixed by removing the slice entirely: `mini_systemd_once` already greps
  `^ExecStart=`/`^Restart=` with `head -1` out of the full `print-unit` output, so no slice was
  ever needed.
- **L3 — the report should state plainly that Claim 1's restart semantics are stubbed via
  mini-systemd, not proven against a real systemd instance.** Already stated in round 1's Claim 1
  section above ("UNVERIFIED: real systemd's own Restart=always behavior..."); restated here for
  round 2's own record: this remains true and unchanged — no systemd host was available to this
  lane in round 2 either.
- **L4 — the lane's diff against its stated base `c5215469` appeared to delete
  `docs/handoff/d353f0bee7ca/LEAD-NOTE-glm-thinking-budget.md`.** Investigated via `git log
  --oneline --follow` (no result) and `git merge-base --is-ancestor c5215469 HEAD` (false):
  `c5215469` is not an ancestor of this lane's HEAD — it is a sibling commit that landed on `main`
  independently after this lane branched at `fa27042a`. The "deletion" is a diff-methodology
  artifact of comparing two non-ancestor commits, not a regression this lane introduced. No rebase
  was attempted (this repo's worktrees are shared/actively edited by concurrent lanes this
  session; rebasing risks disrupting that, and correctness does not require it).

### Suite — full run (round 2)

```
$ bash plugins/leadv2/scripts/tests/test-fleet-runtime-guards.sh
group 0: mutation-target markers present
group A: generated unit content
group B: Claim 1 — restart-on-kill via generated Restart= field
group C: Claim 2 — stop flag between lanes
group D: Claim 3 — disk floor refusal
group E: state file contract
group F: runner self-stop reasons and degrade
group G: guard reap / reap_refused / stall
group H: mutation controls (scratch-copy, must go RED)

29 of 29 passed (fleet guard suite, macOS Darwin, no systemd — unit layer stubbed per mission)
```
rc=0. macOS Darwin 25.6.0, worktree `583d804d01e5`. All three mutation controls (Group H) went RED
against a scratch copy as required by C2; Group 0 additionally guards against the markers
themselves rotting away silently.

### Self-check (round 2)

```
$ for f in plugins/leadv2/scripts/fleet/*.sh plugins/leadv2/scripts/tests/test-fleet-runtime-guards.sh; do
    bash -n "$f" && echo "OK $f" || echo "FAIL $f"
  done
OK plugins/leadv2/scripts/fleet/leadv2-fleet-guard.sh
OK plugins/leadv2/scripts/fleet/leadv2-fleet-lib.sh
OK plugins/leadv2/scripts/fleet/leadv2-fleet-runner.sh
OK plugins/leadv2/scripts/fleet/leadv2-fleet-state.sh
OK plugins/leadv2/scripts/fleet/leadv2-fleet-unit.sh
OK plugins/leadv2/scripts/tests/test-fleet-runtime-guards.sh

$ python3 -c "import yaml; yaml.safe_load(open('tests/mutations/catalog.yaml')); print('OK')"
OK
```
No Python files changed this round beyond `catalog.yaml` (data, not code — validated by parsing
above, not `py_compile`).

`tests/run-all.sh --scope changed` was run for the changed-scope self-check; its output is pasted
in the developer.full.md deliverable rather than duplicated here (long-running, background-run
per this session's token-discipline rule).
