## Drifted `.claude/scripts/tests/` tree — 100-file stale fork (2026-08-03)

**Source:** GATE-WRONG-ROOT-FALSE-DEAD-01 (C3 note)
**State:** open — hygiene cleanup, not a blocker

The `.claude/scripts/tests/` directory is a 100-file REAL COPY (not symlinks) of
`plugins/leadv2/scripts/tests/`. It drifted 5+ days behind canonical as of
2026-07-29, missing 11 suites including every suite recent lanes registered.

GATE-WRONG-ROOT-FALSE-DEAD-01 C3 makes the gate stop READING this tree (plugin-preferred
always-on path via `plugins/leadv2/` probe). But the files remain on disk and may still
be referenced by other tooling. Full de-duplication/delete is a separate task with its own
blast radius assessment.

**Action:** Audit what still references `.claude/scripts/tests/` paths; convert to symlinks
or delete. Do NOT leave as copies (global CLAUDE.md shared-trees policy).

## Captured asks (auto)
- [ ] 2026-08-07T10:40:51Z [s:e61c349c] — NOTE: the Agent/Task/sub-agent tool is disabled for this session. Do all work directly in this one context -- never attempt to spawn a sub-a
- [ ] 2026-08-13T10:30:41Z [s:3faa6ae2] — NOTE: the Agent/Task/sub-agent tool is disabled for this session. Do all work directly in this one context -- never attempt to spawn a sub-a
- [ ] 2026-08-13T10:57:34Z [s:4c40a9de] — NOTE: the Agent/Task/sub-agent tool is disabled for this session. Do all work directly in this one context -- never attempt to spawn a sub-a
- [ ] 2026-08-31T11:11:43Z [s:6541653c] — You are estimating the shape of a single engineering task — not choosing who or what will carry it out. Read the TASK DESCRIPTION below and 

## STATUSLINE-SIDECAR-KEY-DRIFT — hot path can never read the tail's count sidecar (2026-08-24)

**Source:** LANE-REGISTRY-SELF-DEADLOCK-01 census correction (found while making the suite green)
**State:** open — latent defect, pre-existing since 2026-07-31

89711f8 (SUPERVISOR-HARDENING-01) folded `_sup${IS_SUPERVISOR}` into
leadv2-lane-status-line.sh's CACHE_KEY, but leadv2-lane-status-line-tail.sh's
COUNT_SIDECAR_FILE stayed on the plain cwd key. The hot path therefore reads
`leadv2-statusline-lanecount-<cwd>_sup<n>` while the tail writes
`leadv2-statusline-lanecount-<cwd>` — the count sidecar is unreachable in every
mode, and the hot path renders "lanes ?" (or no lanes segment for a
non-supervisor) forever. The D4/D1.5 e2e pair that was written to guard exactly
this agreement has been born-dead since the same day (unreachable behind the
born-red C1/D6 asserts ahead of it); LANE-REGISTRY-SELF-DEADLOCK-01 re-pinned
those asserts to today's behaviour — when this drift is fixed, the
"gate-lifted hot path renders honest lanes ?" assert flips and must be re-pinned.

**Action:** Either drop the `_sup` suffix from the sidecar lookup (it is a
count, supervisor-state-independent) or key the tail's sidecar the same way;
then re-pin the two D4 asserts in test-lane-liveness-authoritative.sh.

## DISPATCH-REG-SPAWN-ATOMICITY — register/worker-pid stamp window keeps a dead lane live-looking for up to silent_max (2026-08-24)

**Source:** LANE-REGISTRY-SELF-DEADLOCK-01 design §4 (accepted residual)
**State:** open — follow-up lane, deliberately not attempted here

The active.yaml row is registered pre-spawn (pid_role=lead_durable) and the
worker pid is stamped post-spawn; the two are not atomic. A dispatch that dies
between them leaves a lead-only row that now correctly resolves dead once aged
past STARTING_MAX/SILENT_MAX — but it stays live-looking for up to 300 s (900 s
with a stream) after every attempt, so a retry loop tighter than that window
still cannot converge. Closing it needs registration + stamping as one locked
registry transaction.

**Action:** Single locked `register_and_spawn_confirm` op in
leadv2-active-registry.sh; until then, retry loops must back off >= silent_max.

## test-dispatch-duplicate-caller-race.sh RED pre-existing (2026-08-24)

**Source:** docs-only duplicate-caller-race lane self-check
**State:** open — suite fails with my lane's zero script changes (docs only)

`bash plugins/leadv2/scripts/tests/test-dispatch-duplicate-caller-race.sh` → rc=1.
1 passed (one racer wins rc=0, one refused rc=2), 1 failed: "no sig8 extracted /
ledger file never created". Racer output shows `FOREIGN-PROJECT-ROOT-GUARD-01`
warn (env=temp fixture root, cwd=real repo) — dispatch used the cwd-derived
root, so the terminal ledger went to the real repo's ledger, not the fixture's
`${LEDGER_FILE}`. Suspect: FOREIGN-PROJECT-ROOT-GUARD-01 / cwd-root precedence
drift vs the test's env-based root injection. Needs an engine-side look, not a
test tweak. Log: /tmp/dcr-test.log (session 1b9adeab).

## TEST-ESCAPE-DUPLICATE-CALLER-RACE — race test spawns real GLM workers (open)

**Source:** docs-only lane dispatch-adbc3304 (= escaped worker of the test itself)
**State:** open — report + fix recommendation committed; fix NOT applied (docs-only)

`test-dispatch-duplicate-caller-race.sh` stubs `LEADV2_DISPATCH_SUBSESSION_BIN`
but not `LEADV2_DISPATCH_GLM_BIN` → the winning racer's glm arm calls the REAL
`glm-coder.sh bg` and launches a real GLM session with the fixture mission
"docs-only: duplicate-caller-race $$ $(date +%s)". 3 confirmed instances
incl. this lane and a sibling (run 260824-141732-leadv2-3094) that committed
UNREVIEWED straight to main: `73e6aca` (plugins/leadv2/docs/duplicate-caller-race.md,
128 lines). Founder call needed: keep or revert 73e6aca. Full evidence:
`plugins/leadv2/docs/test-escape-duplicate-caller-race.md`. Fix: add
`LEADV2_DISPATCH_GLM_BIN` stub to the test (+ audit the 10 sibling tests listed
there). Do NOT re-run the test until stubbed — each run spawns another worker.

**Update 2026-08-24 (instance #4, different test):** `test-prepass-repo-parity.sh`
also spawns a real GLM worker — confirmed from inside the escaped run
`260824-215528-b7de635e-52b2` (lane b7de635e). Trigger: sibling lane
PREPASS-PROVIDER-FALLBACK-01-R3 ran the suite with its WIP dispatcher in place;
the escaped worker's parent chain roots in that lane's `glm-coder.sh __supervise`.
Stock main parks+exit 3 on prepass failure, so the escape runs through the WIP
code path. Evidence: `plugins/leadv2/docs/test-escape-prepass-repo-parity.md`.
Escaped worker did no mission work; docs-only commit on its own lane branch.

**Update 2026-08-24 (instance #5, another test):** `test-dispatch-ledger-task-id.sh`
case C1 ALSO spawns a real GLM worker — confirmed from inside the escaped run
`260824-220011-a9247cab-135b` (lane a9247cab, this worktree). Same trigger:
sibling lane PREPASS-PROVIDER-FALLBACK-01-R3 ran the suite; the escaped worker's
mission is the C1 fixture ("N7F-C1 — case one heading", `$$`=79466, epoch
1787598009 = 22:00:09 EEST, seconds before the worker started) and its parent
chain roots in that lane's `glm-coder.sh __supervise`. The suite stubs
`LEADV2_DISPATCH_SUBSESSION_BIN` but the real glm launch still escaped — likely
the same un-stubbed `LEADV2_DISPATCH_GLM_BIN` root cause as duplicate-caller-race
(UNVERIFIED from inside the worker; engine-side confirm). Evidence:
`plugins/leadv2/docs/test-escape-dispatch-ledger-task-id.md`. Escaped worker did
no mission work; docs-only commit on its own lane branch.

**Update 2026-08-24 (instance #6, engine-side CONFIRMED):** the same suite ran
again at ~22:03 and escaped again — this worker (lane cfd8f8be, run
`260824-220336-cfd8f8be-09e9`) carried the C2 fixture mission
("dispatch-ledger-task-id c2 97396 1787598213"). The #5 UNVERIFIED is now
VERIFIED from inside a worker with a clean engine-side look: the test sets
`LEADV2_DISPATCH_SUBSESSION_BIN` (6×) but never `LEADV2_DISPATCH_GLM_BIN`, and
`leadv2-dispatch-code.sh:3361` defaults that to the REAL
`${SCRIPT_DIR}/glm-coder.sh` → every `--spawn` dispatch case mints a real GLM
session. One suite run spawned ≥5 escaped workers (23ea94b3, e0259db2 both C1;
cfd8f8be = C2; b2ffe12a, 02f1b276 likely same suite). Fix unchanged: stub
`LEADV2_DISPATCH_GLM_BIN=/bin/true` in every case + the 10 sibling tests from
test-escape-duplicate-caller-race.md. Full evidence:
`plugins/leadv2/docs/test-escape-dispatch-ledger-task-id.md` (instances #5+#6).
Escaped worker did no mission work; docs-only commit on its own lane branch.

**Update 2026-08-24 (instance #6, root cause VERIFIED):** the BASE case of `test-dispatch-ledger-task-id.sh` (line 80, inline mission, no @file/--kind) ALSO escapes — escaped run `260824-220338-N4-TESTRUNNER-FALSE-RED-1ad8` (this worktree), parent lane N7F-C3-BOUND-ID (second sibling lane to trigger). Engine-side confirmed on e3ed68c: dispatch-code.sh:3361 defaults GLM_BIN to real glm-coder.sh, :3593 `bash "${GLM_BIN}" bg` is the escape line, and the test has 0 GLM_BIN occurrences while stubbing only SUBSESSION_BIN. Fix unchanged: stub LEADV2_DISPATCH_GLM_BIN in the test (=/bin/true). Evidence: `plugins/leadv2/docs/test-escape-dispatch-ledger-task-id.md` (instance #6 section). Escaped worker did no mission work; docs-only commit on its own lane branch.
**Run-order note (2026-08-24 22:06):** the two 22:03 entries above marked "#6" are distinct escapes from the same suite run — 220336 (C2, lane cfd8f8be) precedes 220338 (BASE, lane N7F-C3-BOUND-ID) by 2 s; the latter independently confirmed the same root cause (dispatch-code.sh:3361 GLM_BIN default).

**Update 2026-08-24 (instance #7, F4 case):** the suite ran AGAIN ~22:03-22:05 (test shell `$$`=34102) and the F4 case (first confirmed; `test-dispatch-ledger-task-id.sh:329-338`) ALSO spawned a real GLM worker — escaped run `260824-220550-3d13912b-5665` (this worktree), mission "# OPS-42 — cleanup, N1B-F4 no-task-id 34102 1787598346". Root cause identical and re-confirmed from inside: `LEADV2_DISPATCH_GLM_BIN` absent, `LEADV2_DISPATCH_CACHE_DIR=.../f4a-cache` ties the worker to F4A. Sibling lane N7F-C3-BOUND-ID ran the suite this time — the escape is lane-independent. Fix unchanged (stub GLM_BIN=/bin/true at every --spawn call site + 10 sibling tests). Evidence: `plugins/leadv2/docs/test-escape-dispatch-ledger-task-id.md` (instance #7 section). Escaped worker did no mission work; docs-only commit on its own lane branch.

**Update 2026-08-24 (instance #8, F4b case + 2 new facts):** the F4b guard case (bound `--task-id OPS-42`, `test-dispatch-ledger-task-id.sh:342-364`) ALSO escapes — this worker (run `260824-220144-OPS-42-470e`, worktree OPS-42, parent PREPASS-PROVIDER-FALLBACK-01-R3 glm-coder.sh, mission "N1B-F4b with-task-id 79466 1787598101"). Blast radius now complete: BASE/C1/C2/C3/F4a/F4b — every `--spawn` case. NEW: (1) the bound task-id leaks into real infra — escape minted worktree `.claude/worktrees/OPS-42` + branch `worktree-OPS-42`, named after the REAL founder task id the fixture borrows; a genuine OPS-42 dispatch will collide. (2) This worker's own (unwitting) suite re-run spawned 3 MORE escapes (02f1b276 F4a, 408054ce C-site glm, N7F-C3-BOUND-ID C3 codex) — escaped workers must never re-run the suite. (3) Suite is FALSE-RED from a worktree: 5 passed/9 failed, every fail logs `FOREIGN-PROJECT-ROOT-GUARD-01 foreign_env_overridden` (fixture root overridden by cwd worktree) — feeds N4-TESTRUNNER-FALSE-RED. Live ledger clean (no fixture sigs in ~/.claude/cache/dispatch-ledger). Evidence: `plugins/leadv2/docs/test-escape-dispatch-ledger-task-id.md` (instance #8 section). Escaped worker did no mission work; docs-only commit on its own lane branch.

**Update 2026-08-24 (instance #9, C2 again — plus founder-approved containment):**
the C2 case (mission with NO H1) escaped AGAIN from the same suite run at
22:00:34 — escaped run `260824-220034-98f232e7-35b3` (worktree 98f232e7),
mission "plain mission body, no heading line, dispatch-ledger-task-id c2
79466 1787598032" (test shell $$=79466). Root cause as verified by instances
#6/#7 from inside: `LEADV2_DISPATCH_GLM_BIN` unstubbed
(leadv2-dispatch-code.sh:3361 defaults to real glm-coder.sh). NEW facts this
instance: (1) the escape MULTIPLIES — observed live: an escaped worker
(worktree 44687dea) re-ran the suite itself, dispatching more fixture missions
(new trees 408054ce, e1f871c9 born mid-survey; ~17 supervise trees in 4 min);
(2) founder approved containment via ask q-c2cdbad5 (option a): 12+ escape
supervise trees + all fixture test loops killed, verified stable-clean — real
PREPASS-R3 lane + main-checkout tree preserved; (3) main branch untouched by
the whole swarm (HEAD still e3ed68c at 22:20); fix-candidates exist on lane
branches worktree-OPS-42 (71f0e39, GLM stub + fixture-root isolation) and
worktree-N4-TESTRUNNER-FALSE-RED (660a5d7). Evidence:
`plugins/leadv2/docs/test-escape-dispatch-ledger-task-id.md` (instance #9
section). This worker did no mission work; docs-only commit on its own lane
branch.
- [ ] 2026-08-30T12:26:33Z — ask-timeout: task dispatch-6280f73a qid q-c65ebb33 timed out; architect decided a (option (b) is not "gap left open" but an active regression — the in-scope ledger fix starts emitting a token the untouched readers currently turn into `done`.)
- [ ] 2026-08-30T19:57:48Z — ask-pending dispatch-42bad5a1: lane wants leadv2-dispatch-product-close.sh added to LANE_WRITES to wire the RED-proof verdict for the close gate; script is not currently in the approved write set. Needs founder/lead decision on scope expansion.
