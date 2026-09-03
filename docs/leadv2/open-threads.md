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
- [ ] 2026-09-03T20:22:00Z [s:a0d28071] — You are estimating the shape of a single engineering task — not choosing who or what will carry it out. Read the TASK DESCRIPTION below and 

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
- [ ] 2026-09-01T10:27:59Z — ask-timeout: task dispatch-a288d3f8 qid q-e5ee4725 timed out; architect decided a (Helper + fixture-proven pattern ship this lane; converting three high-churn watchers outside LANE_WRITES needs per-loop fixtures and review surface a mid-build scope expansion cannot safely carry.)
- 2026-09-01T12:43:35Z — ask-timeout: task dispatch-168e6ff1 qid q-7447b142 timed out; proceeded on default a (expand write set to leadv2-pulse-beat.sh for --owner=<repo>:<lane> argv stamping; single git-tracked file, trivially revertible; brief defect-1 explicitly requires owner stamping for safe orphan sweeps).
- [ ] 2026-09-01T19:40:56Z — ask-timeout: task dispatch-6d1452d6 qid q-3e1c76bf timed out; architect decided a (The 22:17 GLM run is the duplicate/orphan in an already-assigned lane — the lane session keeps ownership; terminate the orphan, then reconcile at commit.)
- [ ] 2026-09-01T19:44:05Z — ask-timeout: task dispatch-8799bc93 qid q-de501a72 timed out; architect decided a (active.yaml registers a live, non-stale worker (s-20260901T191543Z-58137-3926, pid 91307, phase=e2e, born 22:16:41Z) on this exact worktree — the "unknown writer" is the lane's legitimate owner, so this session must not race it.)
- [ ] 2026-09-01T19:49:32Z — ask-timeout: task dispatch-6d1452d6 qid q-1ba6ae9f timed out; architect decided a (Worker-detection is already fully covered by live env exports (glm-coder.sh, freepool-coder.sh) plus the run-dir/transcript path signal (~/.claude/cache/{glm,kimi}-runs/<run-id>/, docs/handoff/<task>/), with fail-open+journal for unknown sessions — option (b) expands LANE_WRITES mid-lane for a redundant change, cost with no functional gain.)
- [ ] 2026-09-01T21:21:08Z — ask-timeout: task dispatch-6d1452d6 qid q-79937ee6 timed out; architect decided a (A loop that arms on a misclassified session is self-perpetuating damage; a loop that doesn't arm is a visible, non-propagating journal row — fail closed is the correct default for anything that self-perpetuates, and the founder case is solved mechanically by the LEADV2_SESSION_KIND=lead pin, not by heuristic inference.)
- [ ] 2026-09-01T21:24:59Z — ask-timeout: task dispatch-b94c3b1c qid q-392fa4b8 timed out; architect decided a (The 2 routing-guard advisory lines are live steering text that contradicts the shipped think-tier resolver (active regression, same class as dispatch-6280f73a), all 6 files are git-tracked text with lane-commit revert as rollback, and leaving a reviewer HIGH open guarantees a round-3 cycle costing more than the edits.)
- [ ] 2026-09-01T21:38:36Z — ask-timeout: task dispatch-bd9f4fc2 qid q-172adb81 timed out; proceeded on default_option=a (architect unavailable, follow-up visible)
- [ ] 2026-09-01T22:03:31Z — duplicate-dispatch: task dispatch-bd9f4fc2 (WORKERS-MUST-COMMIT-01 fix round 2) has TWO live worker arms on the same worktree. Owner per active.yaml: session s-20260901T215756Z-58137-14380, pid 73982 (claude -p, up since 00:58:32, actively editing the 5 LANE_WRITES files — last mtime within a minute of this line). This arm (the duplicate) verified the owner mid-flight and STOOD DOWN without touching any file: zero edits, zero commits from this arm; worktree state is entirely the owner's. Lead: let pid 73982 finish round 2, or kill it and re-dispatch — do not treat this arm as the lane worker.
- [ ] 2026-09-01T22:06:59Z — dispatch-0e7cd03d (PPC-G1: fix integration test harness timeout): fix complete (raised leadv2-suite-falsifiable.sh TIMEOUT_S default 60s→180s + added test-suite-falsifiable.sh regression tests, green). Commit BLOCKED: BEAT-LOOP-ORPHANS-01 worktree has a pre-existing in-progress merge (.git/MERGE_HEAD, ~100+ unrelated staged files from other lanes) — git refuses a path-scoped commit mid-merge. Worker un-staged its 2 files to avoid contaminating that merge; they sit untracked on disk: plugins/leadv2/scripts/leadv2-suite-falsifiable.sh, plugins/leadv2/scripts/tests/test-suite-falsifiable.sh. Needs: resolve the BEAT-LOOP-ORPHANS-01 merge (out of this task scope, see docs/handoff/BEAT-LOOP-ORPHANS-01/fix-round-3.md), then commit these 2 files. Full: docs/handoff/dispatch-0e7cd03d/developer.full.md
- [ ] 2026-09-01T22:11:10Z — duplicate-dispatch: task dispatch-9a35301a (MERGE-QUEUE-DEAD-HEAD-01) has TWO live worker arms on the same worktree. Owner per active.yaml: pid 49666 (claude -p developer arm, born 01:07:54 local, mid-build — had already edited leadv2-merge-queue.sh with the dead-enqueued reclaim + DEAD-ENQUEUED status when this arm attempted its first Edit; edit rejected as file-changed). This arm (the duplicate) verified the owner alive and mid-flight and STOOD DOWN without touching any file: zero edits, zero commits from this arm; worktree state is entirely the owner's. Lead: let pid 49666 finish (suite test-merge-queue-dead-head.sh not yet on disk as of 22:11Z), or kill it and re-dispatch — do not treat this arm as the lane worker.
- [ ] 2026-09-01T22:38:00Z — duplicate-dispatch: task CACHE-TRUTH-01 (dispatch-f5416cf3) has TWO live worker arms on the same worktree. Owner identified WITHOUT active.yaml (none present in this worktree): pid 31911 (claude -p developer arm), proven by lsof cwd = CACHE-TRUTH-01 worktree + live file progress — rewrote leadv2-cache-truth.sh at 01:32 local and created tests/test-cache-truth.sh (with the mutation negative control) at 01:36, minutes before this line. This arm (the duplicate) had written its own first draft of leadv2-cache-truth.sh; the owner's version REPLACED it on disk (treated as deliberate, not reverted). This arm verified the owner alive and mid-flight and STOOD DOWN without touching any file: zero edits, zero commits from this arm; worktree state is entirely the owner's. Interim measurement finding the owner may reuse: on 260901 streams, claude-subsession/dispatch arms report cache fields (hit ~0.975 across 25 runs) but assistant events contain DUPLICATE message-ids with identical usage (35 events = 21 unique in dispatch-21488ff6) — dedupe by message.id before summing; glm-runs report usage as literal zeros in all 40 runs; freepool reports real input but cache fields all-zero on the 3 runs backed by anthropic/nvidia_nim models; kimi's only 260901 run died in api_retry (0 assistant msgs). Lead: let pid 31911 finish, or kill it and re-dispatch — do not treat this arm as the lane worker.
- [ ] 2026-09-01T23:01:44Z — duplicate-dispatch: task WORKER-MCP-ALL-ARMS-01 (dispatch-0537dcc5) has TWO live worker arms on the same worktree. Owner identified WITHOUT active.yaml (none present in this worktree): pid 41723 (orphaned claude -p developer arm, born 01:51:58 local), proven by lsof cwd = WORKER-MCP-ALL-ARMS-01 worktree + live file progress — edited codex-task.sh / leadv2-dispatch-code.sh / freepool-coder.sh / kimi-coder.sh and created config/codex-mcp-servers.toml + prompts/worker-code-intel-preamble.md between 01:53 and 01:59 local, and is currently blocked on its ask-lead.sh question (dispatch-0537dcc5, "Codex real spawn path is codex-task.sh -> node $COMPANION...") about the codex MCP injection mechanism. This arm (the duplicate, claude pid 97108) verified the owner alive and mid-flight and STOOD DOWN without touching any file: zero edits, zero commits from this arm; worktree state is entirely the owner's. Interim findings the owner may reuse: (1) freepool/kimi were already fully worker-mcp-wired on this branch before the owner's edits landed (both spawn points, LEADV2_WORKER_MCP gate, lib source with canonical fallback) — the mission audit table is stale on those two rows; (2) codex CLI -c/--config override exists on codex exec AND codex app-server (verified via --help), but the companion spawns `codex app-server` with fixed args and NO -c passthrough (lib/app-server.mjs spawn), so per-invocation injection realistically goes through a generated CODEX_HOME (probe: CODEX_HOME=/tmp/empty codex mcp list -> "No MCP servers configured yet", default list shows the user config servers); still-owed by the lane: test-worker-mcp-all-arms.sh, run-all.sh registration, live proofs, commit. Lead: let pid 41723 finish, or kill it and re-dispatch — do not treat this arm as the lane worker.
- [ ] 2026-09-01T23:07:00Z — duplicate-dispatch: task GUARD-CENSUS-IS-WRONG-01 (dispatch-b5e35200) has TWO live worker arms on the same worktree. Owner evidence: an unidentified arm (no process claims the worktree via cwd — writes land via absolute paths from elsewhere) is actively editing the 4 LANE_WRITES files mid-flight: leadv2-guard-census.sh (parser fix: chain-split via capture(), dispatcher follow), leadv2-bash-pre-dispatch.sh (runner-side verdict record into guard-verdicts journal), test-guard-census.sh (+61 lines, last write 2026-09-01T23:04:14Z seconds before this line), fixtures/guards/hooks.json + new fx-dispatcher.sh / fx-dispatched.sh / fx-degrade-wrapped.sh. This arm (glm run 260902-015210-GUARD-CENSUS-IS-WRONG-01-71cc, pid 85787) verified the owner mid-flight and STOOD DOWN without touching any file: zero edits, zero commits from this arm; worktree state is entirely the owner's. Lead: let the owner arm finish (mission items 3-6 — fixtures for blocking guards, founder columns, report.md — not yet on disk as of 23:07Z), or kill it and re-dispatch — do not treat this arm as the lane worker.
- [ ] 2026-09-01T23:21:30Z — duplicate-dispatch: task CACHE-TRUTH-01 (dispatch-f5416cf3, fix round 2) has TWO live worker arms on the same worktree. Owner: pid 87417 (claude -p developer arm), proven by lsof cwd = CACHE-TRUTH-01 worktree + live progress — rewrote leadv2-cache-truth.sh (de-dup by message.id + per-request reported/unreported classification, header already updated) at 02:19:08 local and test-cache-truth.sh at 02:19:46 local, and is running tests/run-all.sh --scope changed (pid 40226) plus a glm-coder run 260902-021625-CACHE-TRUTH-01-54ae (pid 38390) when this line was written. This arm (the duplicate) detected the owner ~80s after its last write and STOOD DOWN before touching any lane file: zero edits, zero commits from this arm — with ONE exception to report: this arm executed the mission-mandated `git merge main` first (merge commit 38fb4f0 on worktree-CACHE-TRUTH-01; sole conflict tests/run-all.sh resolved by keeping BOTH sides' suite registrations — cache-truth rows from HEAD plus merge-queue-dead-head/worker-commit-epilogue/lane-outcome rows from main). The merge changes no lane file and makes the owner's own `git merge main` a no-op. Lead: let pid 87417 finish round 2, or kill it and re-dispatch — do not treat this arm as the lane worker.
- [ ] 2026-09-01T23:29:00Z — duplicate-dispatch: task STATUS-CHURN-01 (dispatch-20095269) has TWO live worker arms on the same worktree. Owner per active.yaml: pid 37128 (claude -p worker, born 02:19:08, actively building — wrote scripts/lib/leadv2-status-cache.sh 02:23:03 and tests/test-status-churn.sh 02:26:59 local). This arm (duplicate, ppid 33073, born 02:19:05) verified the owner mid-flight and STOOD DOWN without touching any file: zero edits, zero commits. Interim findings the owner may reuse (all verified by read-only probes): (1) cache MUST be opt-in via env (e.g. LEADV2_STATUS_SNAPSHOT=1), default-off — test-lanes-snapshot.sh runs the reconciler twice on one fixture expecting tombstone/adoption mutations between runs (a default-on TTL gate would skip the second run and go red), and test-broad-status-row-identity.sh + foreign-lanes run broad-status back-to-back within 10s with DIFFERENT collector stubs asserting different founder-status.md content (default-on artifact-gate at broad-status level goes red); none of those suites are in LANE_WRITES. (2) Production fan-in is exactly two producers: lanes-snapshot.sh --json (hook after BUS_OFFSET_FILE resolution ~L163; wrap the final if/else into _lv2_emit_final for the commit path) and lane-liveness.sh --all --json (hook before the CODEX_RAW block ~L78; single python at L84 emits the payload); broad-status→collector→{lanes-snapshot, lane-detail→lane-liveness} and status-line-tail→lane-liveness --all both funnel there, so exporting the env from broad-status L241 / status-line-tail L305-399 (both in writeset) reaches every listed consumer. (3) lane-liveness output is env-sensitive (12 LEADV2_LANE_* vars passed at L84) — cache sections need an env fingerprint or lane-detail and status-line-tail read each other's stale verdicts; lanes-snapshot output differs by ALL_REPOS (L85). (4) Entry points outside writeset (pulse-beat, single-lead-beat-loop, lane-status-line.sh, backlog-pump) still need the env exported or their paths stay uncached — worth a founder note in report.md. Lead: let pid 37128 finish, or kill it and re-dispatch — do not treat this arm as the lane worker.
- [ ] 2026-09-02T00:16:28Z — ask-timeout: task dispatch-e155ef04 qid q-bba84179 timed out; architect decided b (Flash-preferred policy is confirmed correct by the live probe; the only real defect is stale cost data (0.4 vs true 0.33), a one-line data-only fix in the file the routing item is about — extending LANE_WRITES to it is lower total risk than institutionalizing known drift (a) and vastly cheaper than the arbiter rewrite option (c) that the probe's evidence makes unnecessary.)
- [ ] 2026-09-02T00:39:06Z — ask-timeout: task dispatch-b4d13413 qid q-b3741446 timed out; architect decided a (The lock is provably stale and 0-byte, so deleting it is safe and restores every write op in the worktree, while option b leaves the worktree permanently broken and the diff exposed to a parallel session.)
- [ ] 2026-09-03T19:43:21Z — ask-timeout: task dispatch-a9baff78 qid q-2a8c44e7 timed out; architect decided a (The shared-lane ban (docs/handoff/RESUME-20260903/_shared.md line 26, "ЗАПРЕЩЕНО: main; tests/known-red-suites.txt; ...") is a lead-owned concurrency rule protecting one hot file shared by every concurrent red-suite lane; a per-lane mission text cannot override it, so the lane hands the diff to the lead as a LEAD_ACTION.)
