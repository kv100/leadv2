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
