verdict: APPROVE
next_action: review_round_2

# WORKER-CONTEXT-DIET-01 fix round 1 — developer report

Worktree: `.claude/worktrees/9341e2eb` (branch `worktree-9341e2eb`), commit `7b273a6`
(parent `e908a5f`). Implemented the mechanism-closed design verbatim; no census-falsification
found during implementation.

## Changes (matches design §5 C1-C6)

**C1 — `plugins/leadv2/scripts/claude-subsession.sh` (EXCLUDE_DYNAMIC gate):**
`[[ "${LEADV2_SUBSESSION_EXCLUDE_DYNAMIC:-0}" != "0" ]]` → `== "1"`. Comment rewritten to state
strict opt-in symmetric with `SLIM_MCP` (unchanged, already strict). `SLIM_MCP`'s gate at :404
was NOT touched, per design.

**C2 — `claude-subsession.sh` (guard the resolved-config write):**
Removed the early unguarded `mkdir -p "$handoff_dir" 2>/dev/null || true` (was dead work — python
resolution doesn't touch the dir). Replaced the previously-unguarded
`printf '%s' "$py_out" > "$resolved_path"` with:

```bash
if ! mkdir -p "$handoff_dir" 2>/dev/null || ! printf '%s' "$py_out" > "$resolved_path" 2>/dev/null; then
  echo "[claude-subsession] WARN context-diet: role=${role} cannot write ${resolved_path} — spawning with full MCP set" >&2
  return 15
fi
```

Header comment rc list updated: `| 15 handoff dir/resolved-config write failure`.

Verified live (extracted-function harness, `sed -n '/^resolve_role_mcp_config() {/,/^}$/p'`):
touching a *file* at the handoff-dir path (so `mkdir -p` fails) with a resolvable server config
produces exactly:
```
[claude-subsession] WARN context-diet: role=developer cannot write /tmp/.../handoff_ro/mcp-role-developer.resolved.json — spawning with full MCP set
RC=15
```
No bare `No such file or directory`, no script abort — the invariant (§ design "never kill a
worker spawn, never fail silently") now holds structurally for this path, not just by accident
of `set -e` subshell semantics as the design's §2 trace described for the pre-fix state.

**C3 — `plugins/leadv2/scripts/tests/test-subsession-context-diet.sh` (default-unset test):**
1. Harness hermeticity: added
   `unset LEADV2_SUBSESSION_SLIM_MCP LEADV2_SUBSESSION_EXCLUDE_DYNAMIC 2>/dev/null || true`
   in `_it_run_subsession()`, right after `set +e`, before `extra_env` export.
2. New `test_11_defaults_fully_off()` (task id `CD-11`, role `developer`, no extra env),
   registered after `test_10_role_sanitised`. Asserts absence of `--strict-mcp-config`,
   `--mcp-config`, `--exclude-dynamic-system-prompt-sections`, and no `context-diet` in stderr.

**C4 — same test file, `test_8_exclude_dynamic_killswitch()`:** added a second assertion
(`CD-08b`) with `LEADV2_SUBSESSION_EXCLUDE_DYNAMIC=2`, proving the flag stays absent (this is the
direct regression test for C1 — before the fix this value would have enabled the flag).

**C5 — docs:**
- `plugins/leadv2/docs/context-diet.md`: §1/§2 headings now say `default `0` (opt-in)`. The rc
  table's rc-13 row no longer claims "unwritable handoff dir" (that's now rc 15, added as its own
  row). The "Only the literal `0` disables" paragraph replaced with a strict-opt-in statement for
  both gates, citing the 2026-08-23 probe and the mission gate.
- `plugins/leadv2/docs/phases.md` (~:478): both env vars now documented as `default 0, opt-in =1`.

**C6 — finding 5 (two Low findings):** Checked `docs/handoff/dispatch-9341e2eb/` (the directory
this task's design references) — contains `developer.*`, `review.diff`, `e2e-gate.*`,
`selfcheck.md`, `costs.yaml`, `architect-prepass.md`, and no `critic.*` file. Confirmed
unrecoverable. No change made, per mission "do NOT invent work."

## Falsification / self-check (as required by ORIGINAL MISSION)

```
$ bash -n plugins/leadv2/scripts/claude-subsession.sh && echo OK1
OK1
$ bash -n plugins/leadv2/scripts/tests/test-subsession-context-diet.sh && echo OK2
OK2
```
No Python files touched — `py_compile` not applicable.

Full suite (`bash plugins/leadv2/scripts/tests/test-subsession-context-diet.sh`):
```
[TEST] Test 1: role=developer resolves --strict-mcp-config + --mcp-config
[TEST] PASS: developer role appends --strict-mcp-config
[TEST] Test 2: role=hack-detect (no dedicated file) falls back to default
[TEST] PASS: hack-detect falls back to mcp-role-default.json
[TEST] Test 3: no allowlist anywhere -> fail open, WARN logged, no flags
[TEST] PASS: missing allowlist fails open with expected WARN, no flags appended
[TEST] Test 4: malformed allowlist JSON -> fail open, WARN logged
[TEST] PASS: malformed allowlist fails open with expected WARN
[TEST] Test 5: explicit {"servers":[]} still appends flags (deliberate no-MCP)
[TEST] PASS: explicit empty servers list still appends flags
[TEST] Test 6: allowlist names a server absent from every config source -> fail open
[TEST] PASS: unresolvable server fails open with expected WARN
[TEST] Test 7: LEADV2_SUBSESSION_SLIM_MCP=0 -> no flags, no WARN (deliberate operator choice)
[TEST] PASS: kill-switch=0 suppresses flags with no WARN
[TEST] Test 8: LEADV2_SUBSESSION_EXCLUDE_DYNAMIC=0 -> --exclude-dynamic-system-prompt-sections absent
[TEST] PASS: EXCLUDE_DYNAMIC=0 suppresses --exclude-dynamic-system-prompt-sections
[TEST] Test CD-08b: LEADV2_SUBSESSION_EXCLUDE_DYNAMIC=2 -> flag absent (strict opt-in, only literal 1 enables)
[TEST] PASS: EXCLUDE_DYNAMIC=2 suppresses --exclude-dynamic-system-prompt-sections
[TEST] Test 9: default (unset) -> flag absent; =1 opts in
[TEST] PASS: default omits --exclude-dynamic-system-prompt-sections
[TEST] PASS: EXCLUDE_DYNAMIC=1 opts in the flag
[TEST] Test 10: resolve_role_mcp_config('../../evil', ...) coerces to default, no traversal
[TEST] PASS: unsafe role coerced to 'default', resolved config written under expected safe path
[TEST] Test 11: both SLIM_MCP and EXCLUDE_DYNAMIC unset -> no diet flags, no context-diet WARN
[TEST] PASS: defaults-off: no diet flags, no context-diet WARN

=== Results: 13 passed, 0 failed ===
```

Red-before-green: before this change, `test_11` didn't exist and `CD-08b` didn't exist, so
there is no prior red run of these specific assertions to paste — they are new coverage, not
fixes to failing tests. The prior 10-test suite (all passing on `e908a5f`) is preserved
unmodified in assertion content, only the harness hermeticity line was added; re-ran green above
confirms no regression.

## Acceptance (design §8) — verified

- A1: suite prints "13 passed, 0 failed", CD-11 (`test_11`) present and passing. ✓ (above)
- A2: `test_11` asserts exactly this — no `context-diet` in stream/stderr, none of the three
  flags on the recorded command line, for a spawn with neither env var set. ✓
- A3: manually probed the extracted `resolve_role_mcp_config()` with a resolvable allowlist and
  an unwritable handoff dir (a file where a directory was expected) — got exactly one tagged
  `[claude-subsession] WARN context-diet:` line naming the role, rc 15, no bare
  "No such file or directory" text, spawn survives (function returns cleanly). ✓
- A4: `context-diet.md` §1/§2 read "default `0` (opt-in)" with the probe/mission-gate sentence;
  `phases.md`'s paragraph says both variables default to off. ✓
- A5: `test_8`'s new `CD-08b` assertion — `EXCLUDE_DYNAMIC=2` produces no
  `--exclude-dynamic-system-prompt-sections` flag, same as `=0`. ✓
- A6: commit `7b273a6` on `worktree-9341e2eb`, message names `9341e2eb`; `git status --short --
  plugins/leadv2` is clean after commit. ✓

## Non-goals honored (design §7)

Did not touch `SLIM_MCP`'s gate expression, did not flip defaults, did not restructure
`resolve_role_mcp_config()` under `set +e`, did not tag the python heredoc's `WARN_SKIP`/
`WARN_UNRESOLVED` lines, did not address the wrong-repo `repowise` resolution hole, did not touch
`--permission-mode`/`--max-turns`/`build_cached_prefix()`/`PER_TASK_BOILERPLATE`/the probe script,
did not invent the two Low findings, no refactors/renames/`CLAUDE_ARGS` reordering.

## Census check (PREPASS-MECHANISM-CLOSURE-01)

No falsification found. All call sites, rc semantics, and config boundaries described in the
design's §1-§3 matched what I read in the live file at every line I touched. The one place I
deviated from the design's literal keystrokes (removing the now-redundant early `mkdir -p` at the
old :429 instead of leaving it as dead code) is explicitly allowed by design §5 C2: "shape, not
final keystrokes... as long as both failure modes reach the same tagged WARN + return 15." Both
do.

## Gates not run

The mission text (both the wrapper's FOREGROUND WORK CONTRACT paragraph and the "Then:" section
of the ORIGINAL MISSION) asks for the required end-to-end and cross-provider review gates
"recorded for this task." `docs/handoff/dispatch-81f3ffbd/context.yaml` does not exist, and no
gate script name is present in either the scoped design or the original mission body beyond the
generic reference. The developer role's tool access (Read/Write/Edit/Bash/Glob/Grep) is
sufficient to invoke `leadv2-review-run.sh` / `leadv2-phase8-e2e-gate.sh` directly, but doing so
without a context.yaml-recorded invocation would be guessing at the task's actual gate
configuration rather than running "the gate recorded for this task" — flagging this explicitly
for the lead rather than fabricating a gate invocation. Self-check (bash -n, full test suite) is
complete and green above.

DELIVERABLE_COMPLETE
