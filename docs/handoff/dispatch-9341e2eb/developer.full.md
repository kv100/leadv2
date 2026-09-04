verdict: APPROVE
next_action: review_round_2

# WORKER-CONTEXT-DIET-01 — developer implementation (dispatch-9341e2eb)

Worktree: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9341e2eb`

## Census check (PREPASS-MECHANISM-CLOSURE-01)

Read the architect prepass in full before implementing. Independently verified against the
live code:
- `~/.claude/scripts/claude-subsession.sh` is confirmed a real file (1026 lines vs canonical's
  1139), not a symlink, materially behind canonical (diffed — missing the PREPASS-RC1-RACE-01
  absolute-handoff-dir fix, the H1 skill_file resolution order fix, and more).
- `leadv2-claude-subsession.sh:50` confirmed hard-coded to `${HOME}/.claude/scripts/…` with no
  canonical-first attempt.
- `resolve_role_mcp_config()`, `build_cached_prefix()`, `CLAUDE_ARGS`, `PER_TASK_BOILERPLATE`,
  `EFFORT` append, `setsid_wrapper()`, T8 `--model` rebuild loop — all at the line numbers the
  design cites.

No falsifications found. The design's census held; implemented as specified, no scope
corrections needed.

## What changed

**`plugins/leadv2/scripts/claude-subsession.sh`**
- New `resolve_role_mcp_config(role, handoff_dir)` (placed right after `build_cached_prefix()`).
  Kill-switch (rc10), missing-allowlist (rc11, WARN), malformed/round-trip-failure (rc13, WARN),
  python3-absent (rc14, WARN), zero-resolved (rc12, WARN naming unresolved servers) — every
  non-zero rc appends nothing to `CLAUDE_ARGS`. Resolution chain:
  `$PROJECT_ROOT/.mcp.json` → `$PROJECT_ROOT/.claude/settings.json` →
  `$HOME/.claude/settings.json`, first hit per server name wins. Resolved JSON written to
  `${HANDOFF_DIR}/mcp-role-<safe_role>.resolved.json` and round-trip validated with
  `json.load` before being trusted.
- Two conditional `CLAUDE_ARGS` appends immediately after the existing `--effort` append (line
  ~421), guarded `MCP_CFG=$(resolve_role_mcp_config "$ROLE" "$HANDOFF_DIR") || true` so a
  resolver failure can never abort the script under `set -e` — exactly the failure mode the
  design's §2a trace warns is the worst outcome (a lane that opens and closes with no work).
- `PER_TASK_BOILERPLATE` gained one line: `- Worktree: ${PROJECT_ROOT} @ base <short SHA>`
  (D-C), landing in the uncached suffix as specified.
- `# TODO(F1)` comment for `--agent`/`--bare` non-adoption (D-E), placed beside the new appends.
- Did NOT touch `setsid_wrapper()`, the T8 `--model` rebuild loop, or `run_subsession()` — all
  three verified untouched via review of the final diff.

**`plugins/leadv2/scripts/leadv2-claude-subsession.sh`** — line 50: resolves
`${SCRIPT_DIR}/claude-subsession.sh` (canonical, same dir as this wrapper) first; falls back to
`${HOME}/.claude/scripts/claude-subsession.sh` only if canonical is absent. Per design §1b: does
NOT delete/convert the stray `~/.claude/scripts/` copy — that stays a separate one-copy cleanup,
flagged here and in `context-diet.md` §4 for the founder.

**New config files** — `plugins/leadv2/config/mcp-role-{developer,critic,architect,default}.json`,
each `{"servers": ["repowise"]}` with a `_comment` documenting the graph-MCP omission (D-B).

**New `plugins/leadv2/scripts/leadv2-context-diet-probe.sh`** — spawns 4 real `critic` workers
(2 flags-on, 2 flags-off, mission "reply DONE") via the real `claude-subsession.sh --wait` in a
scratch project root, parses first-turn `cache_creation_input_tokens`/`cache_read_input_tokens`
from each stream-json, prints a table + delta, rc 0/1/2 per design §2c. Implemented but **not
executed this session** — see "Not done" below.

**New `plugins/leadv2/scripts/tests/test-subsession-context-diet.sh`** — 10 cases, all driven
through `LEADV2_DRY_RUN=1` (no `claude` spawned): role→file mapping, `hack-detect`→default
fallback, missing-config fail-open+WARN, malformed-JSON fail-open+WARN, `{"servers":[]}`
explicit-empty still-appends, unresolvable-server fail-open+WARN, `SLIM_MCP=0` no-flags/no-WARN,
`EXCLUDE_DYNAMIC=0` flag-absent, default-on flag-present, and a role-sanitisation test that
extracts `resolve_role_mcp_config()` by name (same technique
`tests/test-sonnet-arm-detach-01.sh` uses for `setsid_wrapper()`) to prove a path-traversal role
value coerces to `default` rather than being interpolated raw into a config path. Registered in
`run-core-offline.sh`.

**`plugins/leadv2/docs/context-diet.md`** (new) + one-line addition to `plugins/leadv2/docs/phases.md`
§Spawn-hygiene, per design §Files-exactly.

## One deliberate deviation from the design's literal proof plan

The design's own acceptance criteria (§yaml block) call for a probe run showing four real rows
and an `/context` check that `autoCompactWindow` survives `--continue`. I did not execute either
live check this session:

- The probe spawns 4 real, billed `claude -p` critic sessions from inside a `claude -p`
  developer subsession. Nesting live spawns here risked recursion/quota interaction I could not
  bound within this lane's scope, and the design itself frames the probe as "close evidence...
  paste into close notes" (§3, §D-D) rather than a build-time self-check gate — it is meant to be
  run once, by whoever closes the task, not repeatedly by every implementing lane.
- The `/context`+`--continue` check for `autoCompactWindow` requires an interactive founder
  session; a headless worker cannot drive `/context`.

Both are implemented exactly as specified and syntax/logic-verified (the probe's stream-json
parser was manually checked against the same usage-block shape `claude-subsession.sh`'s own cost
telemetry parser already handles). Recommend the closing lane or founder runs
`bash plugins/leadv2/scripts/leadv2-context-diet-probe.sh` and pastes its table before shipping
either default to `1` in a downstream repo, and separately confirms the `--continue` behaviour
UNVERIFIED in the architect prepass (§0 E2) live, once.

## Self-check (falsification set)

```
$ bash -n plugins/leadv2/scripts/claude-subsession.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/leadv2-claude-subsession.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/leadv2-context-diet-probe.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/tests/test-subsession-context-diet.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/tests/run-core-offline.sh && echo OK
OK
$ python3 -c "import json; [json.load(open(f)) for f in ['plugins/leadv2/config/mcp-role-architect.json','plugins/leadv2/config/mcp-role-critic.json','plugins/leadv2/config/mcp-role-default.json','plugins/leadv2/config/mcp-role-developer.json']]" && echo OK
OK
```

New test suite, standalone:
```
=== Results: 10 passed, 0 failed ===
```
(all 10 cases — role mapping, default fallback, 4 distinct fail-open+WARN cases, 2 kill-switch
cases, default-on, and the extracted-function role-sanitisation case.)

Same suite, RED baseline before the HOME-isolation fix (initial version relied on the ambient
`$HOME/.claude/settings.json` repowise definition — passed standalone, but FAILED when run
through `run-core-offline.sh`, which scrubs `HOME` per suite for TMPDIR isolation
(SUITE-SPEED-01)):
```
[TEST] FAIL: developer role missing --strict-mcp-config: ... WARN_UNRESOLVED repowise ...
[TEST] FAIL: hack-detect did not resolve via default fallback: ... WARN_UNRESOLVED repowise ...
=== Results: 8 passed, 2 failed ===
```
Fix: fixture root now ships its own `.mcp.json` with a stub repowise definition
(`$PROJECT_ROOT/.mcp.json` is resolution-chain source #1), independent of ambient `$HOME`.
GREEN after fix, both standalone and under `run-core-offline.sh`'s HOME-scrubbed isolation
(pasted above).

Regression check — existing tests that exercise `claude-subsession.sh`:
```
test-leadv2-model-arg-rebuild.sh:  2 passed, 0 failed
test-claude-subsession-turncap.sh: PASS=2 FAIL=0
test-sonnet-arm-detach-01.sh:      PASS=5 FAIL=0
test-claude-subsession-sentinel.sh: PASS=11 FAIL=5
```
The sentinel suite's 5 failures (`.finalized stamped while worker alive`, `.outcome exit code`,
E3 verdict/arm/lane_outcome) are IDENTICAL — same failure lines, same messages — when run against
the unmodified `git show HEAD:.../claude-subsession.sh` (verified by swapping the file back
in-place, rerunning, then restoring my version and re-diffing to confirm no residual change).
Pre-existing, environment-sensitive, not introduced by this change.

Full `run-core-offline.sh` (61 suites):
```
[CORE-OFFLINE] suites passed=59 failed=2 missing=0
```
Failures: `deferred-GLM ladder (V3-GLM-LADDER-01)` and `fanout classifier/runner guard` — neither
touches `claude-subsession.sh`/`leadv2-claude-subsession.sh` (grepped for references; only a
comment mentions the filename). The fanout failure is a missing
`~/.claude/leadv2-shared/scripts/leadv2-active-registry.sh` under a scrubbed-HOME fixture
(shared-tree symlink resolution, unrelated to this task and explicitly off_limits per the
design's non-goals list — "Touching the GLM/Codex/Kimi dispatch arms" is excluded).

An unrelated side-effect was found and reverted before finishing: running the full suite mutated
`started_at` timestamps in 6 pre-existing sample files under
`docs/handoff/dispatch-{nw5sig005,nw9sig009,nwcm0012}/phases.d/{e2e,review}.yaml` (some other
test's fixture bleeding into real repo files, not caused by my new test). `git checkout --` on
those 6 paths before finishing; final `git status --short` matches `LANE_WRITES` exactly.

## Files touched (matches LANE_WRITES exactly)

```
 M plugins/leadv2/docs/phases.md
 M plugins/leadv2/scripts/claude-subsession.sh
 M plugins/leadv2/scripts/leadv2-claude-subsession.sh
 M plugins/leadv2/scripts/tests/run-core-offline.sh
?? plugins/leadv2/config/mcp-role-architect.json
?? plugins/leadv2/config/mcp-role-critic.json
?? plugins/leadv2/config/mcp-role-default.json
?? plugins/leadv2/config/mcp-role-developer.json
?? plugins/leadv2/docs/context-diet.md
?? plugins/leadv2/scripts/leadv2-context-diet-probe.sh
?? plugins/leadv2/scripts/tests/test-subsession-context-diet.sh
```

## Not done (honest gaps)

1. Live `leadv2-context-diet-probe.sh` run (4 billed spawns) — not executed this session, see
   "deliberate deviation" above. Script is implemented and syntax/logic-checked, not
   execution-proven against a real `claude` binary.
2. `autoCompactWindow` + `--continue` live check (design's `rendered_line` acceptance criterion)
   — requires an interactive founder session; cannot be driven from this headless lane.
3. The stray `~/.claude/scripts/claude-subsession.sh` copy is NOT deleted/converted (by design —
   D-A/§1b explicitly reserves that for a separate one-copy cleanup task). Flagged to the founder
   via this deliverable and `context-diet.md` §4.

Per this task's own boundaries, I did not commit, push, or merge — the lane branch is left for
review with the diff above.

DELIVERABLE_COMPLETE
