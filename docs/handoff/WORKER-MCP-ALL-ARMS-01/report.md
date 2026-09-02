# WORKER-MCP-ALL-ARMS-01 — report

## Round 1

No report.md was written in round 1 (reviewer noted this). Round 1 shipped the
cross-arm MCP suite (`test-worker-mcp-all-arms.sh`) covering freepool/kimi
`run` paths, the codex doc-gap assertions, and the preamble/dispatch wiring.

## Round 2 evidence

Reviewer verdict on round 1: FAIL (high=1) — the suite claimed coverage of the
`bg`/child spawn paths but never invoked them; deleting the whole
`cmd_run_child` MCP wiring (`freepool-coder.sh:1261-1293`,
`kimi-coder.sh:1119-1135`) left the suite green. The `bg` path is the ONLY
path the dispatcher uses.

### 1. Real `bg` → `__supervise` → `__run_child` exercised, transport faked one level lower

The suite now invokes `freepool-coder.sh bg` / `kimi-coder.sh bg` exactly as
the dispatcher does (preamble-prepended prompt via `@file`, `--cwd`, timeout).
The detached setsid supervisor spawns the real `__run_child`, which execs a
stub `claude` binary that dumps argv + env to files (no network). The suite
waits on the terminal sentinel (`.finalized`), bounded at 120s.

Fake-transport artifacts from a green run (stub binary in `/tmp`, run
`260902-030650-repo-0892`):

`stub argv dump (excerpt)`:

```
argv: -p
argv: NOTE: the Agent/Task/sub-agent tool is disabled for this session. ...
      (prompt continues; contains "CODE-INTEL ROUTING" preamble block and the mission line)
argv: --strict-mcp-config
argv: --mcp-config
argv: /tmp/.../mcp-role-developer.resolved.json
```

`stub env dump (excerpt)`:

```
ANTHROPIC_AUTH_TOKEN=stub-token
ANTHROPIC_BASE_URL=http://stub
ANTHROPIC_DEFAULT_OPUS_MODEL=freepool-default
FREEPOOL_ROLE=implement
```

`--mcp-config` value (role-resolved server list, resolved at spawn time from
the fixture repo's `.mcp.json` through `lib/leadv2-worker-mcp.sh`):

```json
{"mcpServers": {"repowise": {"command": "stub-repowise", "args": []}, "codebase-memory-mcp": {"command": "stub-cbm", "args": []}}}
```

launcher journal:

```
freepool_select role=implement model=sonnet
worker_mcp_attached config=mcp-role-developer.resolved.json role=developer
```

New cases (all PASS): child argv carries `--strict-mcp-config --mcp-config`;
resolved config carries both servers; child env carries the transport
(BASE_URL/AUTH_TOKEN, freepool also FREEPOOL_ROLE); the code-intel preamble +
mission both reach the child `-p`. Identical coverage for kimi. Full suite
output: 34/34 PASS (`TOTAL: PASS=34 FAIL=0`, rc=0).

### 2. Mutation negative control — RUN, red pasted

Reviewer's exact mutation (empty `mcp_cfg` in `cmd_run_child`) applied to
SCRATCH COPIES only; the real `bg` chain run against each mutant:

```
== freepool: reviewer mutation applied to scratch copy (cmd_run_child wiring removed) ==
freepool: bg run finalized (260902-030629-freepool-repo-32ae)
-- new-case assertion against mutant: 'ARGV contains --mcp-config'
   RED/GREEN: RED — '--mcp-config' absent from child argv; the new bg case FAILS on this mutant (mutation caught)

== kimi: reviewer mutation applied to scratch copy (cmd_run_child wiring removed) ==
kimi: bg run finalized (260902-030633-kimi-repo-1dc9)
   RED/GREEN: RED — '--mcp-config' absent from child argv; the new bg case FAILS on this mutant (mutation caught)

working tree check: 0   (git status clean — mutants never touched the tree)
```

The same controls run in-suite (mutated scratch copies asserted to produce NO
`--mcp-config`): all three PASS (freepool run, freepool bg, kimi bg).
Mutants reverted (scratch-only; working tree verified clean by `git status`).

### 3. Per-arm summary

- **arm freepool**: MCP servers reach the child via `--strict-mcp-config
  --mcp-config <role-resolved json>` on the `claude` argv built in
  `cmd_run_child`, resolved by `worker_mcp_resolve` →
  `resolve_role_mcp_config` (shared lib, no copy) — proved by suite cases
  "freepool bg: cmd_run_child puts --strict-mcp-config --mcp-config on the
  child argv" / "...role-resolved config with both servers reaches the child".
- **arm kimi**: same mechanism in kimi's `cmd_run_child` — proved by the
  mirrored "kimi bg: ..." cases.
- **arm codex**: NO in-repo mechanism exists. UNVERIFIED-below-otherwise
  evidence: the real spawn goes through `node "$COMPANION"`
  (`codex-companion.mjs`, openai-codex plugin cache — outside this repo and
  outside LANE_WRITES). Probe:
  `grep -c mcp ~/.claude/plugins/cache/openai-codex/codex/1.0.4/scripts/codex-companion.mjs`
  → 0 occurrences in 1027 lines; its spawn call is
  `spawn(process.execPath, [scriptPath, "task-worker", "--cwd", cwd, "--job-id", jobId])`
  — no `-c mcp_servers` / config passthrough exists for this repo to wire.
  The `-c mcp_servers…` / toml path named in the mission therefore does not
  exist to exercise; the suite asserts only the documented allowlist
  (`config/codex-mcp-servers.toml`) and the doc-gap NOTE, and the suite header
  now states exactly that (no claim without a case).

### 4. Falsifiable gate + changed-scope

```
leadv2-suite-falsifiable: suite=.../test-worker-mcp-all-arms.sh
baseline: rc=0
probe[assertion_tools_broken]: rc=1 shim_invocations=183
probe[empty_cwd]: rc=0
probe[stripped_env]: rc=0
verdict: falsifiable — a failure injection turned the suite red (rc=1)
```

`tests/run-all.sh --scope changed`: (selected-suite line appended below after
run completes.)

### 5. Incidental finding (not fixed in this lane)

`load_secret()` sources the secrets file under active `set -e` in the
`bg`/child path (`cmd_run_child` is dispatched as a bare statement, unlike
`run` which is invoked inside `if`), so a secrets file containing
`FREEPOOL_BASE_URL=...` kills the child at the `readonly FREEPOOL_BASE_URL`
assignment (freepool-coder.sh:65) — reproduced: child exits rc=1,
`RUN_FAILED`. Production secrets presumably carry only the token (the
existing suite's freepool `run` fixture masked this because the `if`-context
disables `set -e`). Flagging as a footgun for a future lane; the round-2 bg
fixtures use a token-only secrets file + `FREEPOOL_PROXY_URL`.

## Round 3 evidence

Round 3 fixes review verdict H1 (journal truncation) and H2 (unconditional
preamble injection). Round-2 review verdict: `FAIL, high=2`.

### 1. H1 — `tee -a` on the kimi journal + full journal-write audit

Fix: `kimi-coder.sh:1135` is now `| tee -a "${run_dir}/journal.jsonl" |`
(was bare `tee`, which truncated the file and destroyed the
`worker_mcp_attached`/`worker_mcp_skipped` records `worker_mcp_resolve()`
writes at :1120 BEFORE the stream starts).

Audit — every `tee`/`>` onto a `journal.jsonl` across LANE_WRITES shell files
(`grep -nE 'journal\.jsonl' | grep -E 'tee|>>|>[^>]'` per file):

| File:line | Write | Verdict |
|---|---|---|
| `kimi-coder.sh:1135` | `tee -a` stream | FIXED this round (was bare `tee`) |
| `freepool-coder.sh:1283` | `tee -a` stream (direct path) | already append |
| `freepool-coder.sh:1285` | `tee -a` stream (redact path) | already append |
| `freepool-coder.sh:1260` | `>> journal.jsonl` (`freepool_select` record) | append |
| `codex-task.sh`, `leadv2-codex-planner.sh`, `lib/leadv2-worker-mcp.sh`, `leadv2-dispatch-code.sh` | — | no direct journal.jsonl writes |
| `worker_mcp_journal()` (kimi:151, freepool:127) | `printf >> "$1"` | append |

Out-of-lane note: `glm-coder.sh:1203` still has a bare `tee` onto
`journal.jsonl`, but it is NOT the H1 bug: glm passes
`${run_dir}/progress.log` (not journal.jsonl) as `worker_mcp_resolve`'s
journal target (`glm-coder.sh:1181`), so journal.jsonl carries no pre-spawn
MCP records for the tee to destroy. Left untouched (outside LANE_WRITES).

Suite case (two consecutive journal writes, both records present):

```
[TEST] PASS: kimi bg: journal keeps BOTH the pre-spawn worker_mcp_attached record and the stream (tee -a)
```

### 2. H2 — preamble injected only when the arm's MCP attach succeeds

`leadv2-dispatch-code.sh` no longer injects the code-intel preamble
unconditionally. The single injection site (`_spawn_worker_body`, ~:5090) now
calls `worker_mcp_preamble_for_arm "${arm}" "${WORK_ROOT}" ""` — a new
predicate in `lib/leadv2-worker-mcp.sh:192` built ON TOP of
`resolve_role_mcp_config()` (the same resolver the launchers run at spawn
time, so the prediction is deterministic):

- rc=0 attached (glm/glm-flash/kimi/freepool with `LEADV2_WORKER_MCP=1`
  default, sonnet with `LEADV2_SUBSESSION_SLIM_MCP=1`) → full preamble;
- rc=3 skip/fail-open (`LEADV2_WORKER_MCP=0`, nothing resolvable, preamble
  file missing) → one-line `code-intel MCP unavailable in this session — use
  grep/Read instead of mcp__* tools.` note that names no concrete tool;
- rc=4 unwired (codex) → nothing.

The round-2 unconditional global `_LEADV2_CODE_INTEL_PREAMBLE` is deleted
from `leadv2-dispatch-code.sh` (grep hits remain only inside the suite, as
the regression guard). The dispatcher also `emit`s a
`code_intel_preamble arm=… mode=attached|skipped|none` decision line per
spawn. Suite (behavioural, lib level — rc + stdout asserted):

```
[TEST] PASS: preamble gate: kimi attached (default gate) -> rc=0 + preamble text
[TEST] PASS: preamble gate: freepool attached (default gate) -> rc=0 + preamble text
[TEST] PASS: preamble gate: glm attached (default gate) -> rc=0 + preamble text
[TEST] PASS: preamble gate: kimi LEADV2_WORKER_MCP=0 -> rc=3 + fallback note, no preamble
[TEST] PASS: preamble gate: kimi fail-open (nothing resolvable) -> rc=3 + fallback note, no preamble
[TEST] PASS: preamble gate: codex unwired -> rc=4 + empty output
[TEST] PASS: preamble gate: sonnet default (no SLIM_MCP) -> rc=3 + fallback note, no preamble
[TEST] PASS: preamble gate: sonnet LEADV2_SUBSESSION_SLIM_MCP=1 -> rc=0 + preamble text
[TEST] PASS: preamble gate: fallback note promises no concrete mcp__* tools
[TEST] PASS: leadv2-dispatch-code.sh: preamble injection is gated by worker_mcp_preamble_for_arm(arm)
[TEST] PASS: leadv2-dispatch-code.sh: unconditional-injection marker _LEADV2_CODE_INTEL_PREAMBLE stays deleted (round-2 H2 regression)
[TEST] PASS: leadv2-dispatch-code.sh: sources the shared worker-MCP lib (no second resolver)
```

Codex stays unwired: `codex-task.sh` still emits the documented MCP-gap NOTE;
`config/codex-mcp-servers.toml` remains a declared allowlist only.

### 3. Mutation negative controls (by hand in a scratch copy —
`leadv2-mutation-control.sh` does not exist on main)

Both controls mutate a scratch copy (never the lane tree), run the mutated
artifact, and assert the suite's case goes red; run inside the suite:

```
[TEST] PASS: negative control (tee -a): mutated kimi goes RED — attached record destroyed by truncation, journal case catches it
[TEST] PASS: negative control (dispatch gate): unconditional injection goes RED — dispatch gate check catches it
```

That is: (d) scratch kimi-coder.sh with `tee -a` → `tee` — the bg run's
journal.jsonl LOSES the `worker_mcp_attached` record (truncation reproduced,
the exact round-2 H1), and the suite's journal case fails on it; (e) scratch
leadv2-dispatch-code.sh with the gate call replaced by an unconditional
prepend — the dispatch gate check fails on it (exact round-2 H2).

### 4. Falsifiable gate + changed-scope

```
leadv2-suite-falsifiable: suite=.../test-worker-mcp-all-arms.sh
baseline: rc=0
probe[assertion_tools_broken]: rc=1 shim_invocations=235
probe[empty_cwd]: rc=0
probe[stripped_env]: rc=0
verdict: falsifiable — a failure injection turned the suite red (rc=1)
```

`tests/run-all.sh --scope changed` (full run, 2026-09-02): the state file at
`.git/worktrees/WORKER-MCP-ALL-ARMS-01/leadv2-run-all-last-checked-sha` is
guarded as a "sensitive file" by this session's own permission layer (`rm`/
write both refused: "Claude requested permissions to edit ... which is a
sensitive file") — it could NOT be reset this round, so `--scope changed`
ran against whatever range that file already pinned. Command run for real
(detached to a log file, foreground-polled to completion in three ~580s
waves, never left running past turn end):

```
[RUN] .../plugins/leadv2/scripts/tests/run-core-offline.sh
[CORE-OFFLINE] running 83 suites across 4 shards
...
[CORE-OFFLINE] suites passed=65 failed=20 missing=0
[FAIL] .../plugins/leadv2/scripts/tests/run-core-offline.sh
[RUN] .../tests/test-status-surface-bash32.sh
test-status-surface-bash32: 16 passed, 0 failed, 0 skipped
[PASS] .../tests/test-status-surface-bash32.sh
[RUN] .../tests/test-status-surface-single-lead.sh
test-status-surface-single-lead: 23 passed, 0 failed
[PASS] .../tests/test-status-surface-single-lead.sh
[RUN] .../tests/test-status-surface-fast-names.sh
test-status-surface-fast-names: 12 passed, 0 failed
[PASS] .../tests/test-status-surface-fast-names.sh
  Failures (blocking):
    - plugins/leadv2/scripts/tests/run-core-offline.sh
run-all: 3 passed, 1 failed, scope=changed
```

The one blocking failure is `run-core-offline.sh` itself, which aggregates 83
independent suites (`passed=65 failed=20`). None of the 20 are
`test-worker-mcp-all-arms.sh` (not registered in `run-core-offline.sh`'s list
at all — `grep -n worker-mcp-all-arms ... run-core-offline.sh` → no match; it
is picked up separately by `--scope changed`'s stem-mapping, run directly and
green — see §4 above). Failed-suite audit against this round's 10-file diff
(`git diff --name-only 258d018e..HEAD`):

- `core-offline cross-run exclusive lock (SUITE-SPEED-01)` — its own test
  file (`test-core-offline-lock-01.sh`) is untouched by this round. Re-run
  standalone (not inside the 4-shard concurrent core-offline run):
  `[LOCK-01] pass=3 fail=0`, rc=0 — passes clean in isolation, so the failure
  inside the full run is lock-timing contention from running 4 shards
  concurrently (plus 5 other active leadv2 lanes on this machine per the
  session's own `[LEADV2_ACTIVE_OTHER_SESSIONS]` banner), not a regression.
- `dispatch arm vocabulary (kimi retirement)` and `dispatch refusal fallback
  chain` — both exercise `leadv2-dispatch-code.sh`, which this round DOES
  touch, so audited directly against the diff. The two hunks this round adds
  are (a) sourcing `lib/leadv2-worker-mcp.sh` after the existing
  `leadv2-helpers.sh` source, and (b) the `worker_mcp_preamble_for_arm`
  call + `_ci_txt` mission-fold inside `_spawn_worker_body` — both isolated
  to the code-intel preamble. The failing assertions are about arm-ladder
  fallback chains (`expected: 'glm glm-flash codex sonnet freepool', got:
  'glm codex sonnet'`) and quota-capped routing (`arms='' expected
  'glm,codex,sonnet'`) — a different subsystem (`arm_resolved`/
  `route_resolved` in the arbiter, nowhere near the preamble block) that
  this round's diff never touches. Pre-existing, tracked elsewhere.
- The other 15 failures (`landed-at-spawn`, `phase precondition guard
  matrix`, `claim-evidence gate`, etc.) touch none of this round's 10 files
  and match the repo's already-documented pre-existing-red set (memory:
  "run-all changed pre-existing reds").

Suite self-check: `bash -n` green on all 7 changed shell files
(codex-task.sh, freepool-coder.sh, kimi-coder.sh, leadv2-dispatch-code.sh,
lib/leadv2-worker-mcp.sh, tests/test-worker-mcp-all-arms.sh, tests/run-all.sh
— `leadv2-codex-planner.sh` is NOT in this round's diff, corrected from the
round-3 note); no Python files changed this round. Direct suite run:
`PASS=49 FAIL=0`, rc=0 (2 more than round-3's 47 — the R4 negative control
"mission fold" pair, added this round).

## R4 findings

R3 review (opus, `d815dba0`): `FAIL high=4`. Each row below: REAL/REFUTED +
evidence command. No command = REAL by inspection (self-evident from the
cited line).

| # | Finding | Verdict | Evidence |
|---|---|---|---|
| 1 | `lib/leadv2-worker-mcp.sh:210` fallback note inverted — tells the widest-tool-set session it has none | REAL, already fixed on the wip commit before this round started | `worker_mcp_preamble_for_arm()` (lib/leadv2-worker-mcp.sh:203-277) now returns rc=3 with **empty stdout** on every fail-open branch (was: an inverted "MCP unavailable" string). Verified by direct read of the current tree (no "MCP unavailable" string remains — `grep -n 'MCP unavailable' lib/leadv2-worker-mcp.sh` → no match) and by the suite's own regression case: `[TEST] PASS: preamble gate: fail-open branch stays silent (no inverted 'MCP unavailable' claim)`. |
| 2 | `tests/test-worker-mcp-all-arms.sh:1163` injection asserted by two greps only — deleting the mission-fold line stays green | REAL, already fixed on the wip commit before this round started | `_run_spawn_worker_mission()` (test file, ~:474-500) sources the REAL `leadv2-dispatch-code.sh` via `LEADV2_DISPATCH_SOURCE_ONLY=1`, calls `_spawn_worker_body` with a stub kimi launcher, and asserts the captured `bg` argv contains `CODE-INTEL ROUTING`. Negative control (~:502-540) deletes the exact mission-fold line (`[[ -z "${_ci_txt}" ]] || mission=...`) in a scratch copy and proves the structural grep-only check STILL passes while this behavioural case goes RED. Both re-run this round: `[TEST] PASS: leadv2-dispatch-code.sh: _spawn_worker_body puts the resolved preamble text INSIDE the mission the child bg call receives` and `[TEST] PASS: negative control (mission fold): mutated dispatcher goes RED -- preamble text absent from the mission the child receives (mutation caught)`. |
| 3 | `report.md:253` — `RUNALL_PLACEHOLDER`, changed-scope gate has no artifact | REAL, fixed this round | See "Round 3 evidence §4" above: `tests/run-all.sh --scope changed` run for real (detached, foreground-polled ~29min across 3 waves — `core-offline` alone takes >10min per prior-round memory), placeholder replaced with the actual `run-all: 3 passed, 1 failed, scope=changed` output and a failed-suite-by-failed-suite audit against this round's diff. |
| 4 | `config/codex-mcp-servers.toml:283` — evidence-free "codex has no MCP hook" claim decides against wiring | REAL, already fixed on the wip commit before this round started | The file (47 lines total, not the ~283 the finding's line number implied — pre-fix version was longer) now carries two probes with commands + output inline. Independently re-run this round: `LEADV2_ALLOW_DIRECT_CODEX=1 codex exec --help` → confirmed `-c/--config key=value` is the only override flag, no dedicated MCP flag; `grep -c mcp ~/.claude/plugins/cache/openai-codex/codex/{1.0.3,1.0.4}/scripts/codex-companion.mjs` → `0` for both cached versions; `grep -n 'spawn(' <same files>` → line 643 in both, identical `spawn(process.execPath, [scriptPath, "task-worker", "--cwd", cwd, "--job-id", jobId], ...)` — the companion never shells out to `codex exec`, so none of probe 1's flags reach a codex process on this path. `codex-task.sh:50`'s `find ... | sort -V | tail -1` resolution independently confirmed via `find ~/.claude/plugins/cache/openai-codex -name codex-companion.mjs -path "*/scripts/*" | sort -V` → picks 1.0.4 over 1.0.3, both probed. |

All 4 REAL, all 4 fixed (3 landed on the wip commit before this round began;
this round's actual work was replacing the report.md placeholder with a real
`--scope changed` run + auditing its 20 pre-existing core-offline failures
against the diff, re-verifying the codex evidence chain independently, and
clearing a stale `/tmp/leadv2-core-offline-*.lock` (holder pid 64695, dead)
that would otherwise have blocked the run). No placeholder tokens remain
anywhere in this file — checked via `grep -rn PLACEHOLDER report.md` → no
match after this edit.

Falsifiable gate, re-run this round from the lane root:

```
leadv2-suite-falsifiable: suite=.../plugins/leadv2/scripts/tests/test-worker-mcp-all-arms.sh
baseline: rc=0
probe[assertion_tools_broken]: rc=1 shim_invocations=234
probe[empty_cwd]: rc=0
probe[stripped_env]: rc=0
verdict: falsifiable — a failure injection turned the suite red (rc=1)
```
