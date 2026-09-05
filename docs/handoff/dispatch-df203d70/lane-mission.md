Product implementation task dispatch-df203d70. Implement this mechanism-closed design; preserve its non-goals. Before closing, run the required end-to-end gate and the cross-provider review gate recorded for this task.

PREPASS-MECHANISM-CLOSURE-01 — the design is authoritative, but it is not infallible, and you are the one reading the actual code. If discovery FALSIFIES its census — a caller it did not list, a return code whose consequence differs from what it claims, a configuration state it missed — STOP and say so in your report instead of implementing around it. Silently implementing a design whose census is wrong is how a defect becomes the next review round. Correcting the census in your report is a valid, valuable deliverable; quietly widening scope beyond it is not.

===== SCOPED DESIGN (authoritative) =====
# CODEX-BATCH-REVIEW-FIXROUND-01 — architect prepass

Scope: 4 confirmed findings from the 2026-08-25 adversarial review of the 08-24 batch. One lane, on `main`, no worktree fan-out needed (files are disjoint).

## 1. HIGH — deny-floor bypass (`codex_exec_direct`)

**File:** `plugins/leadv2/codex-lead/deny-extra.yaml:42`

Current regex `'(^|[;&|]\s*)codex\s+exec\b'` anchors on start-of-string or a shell separator, so any prefix token defeats it. Confirmed bypass shapes (from review, live-probed): `env codex exec …`, `/usr/local/bin/codex exec …`, `xargs -I{} codex exec {}`.

**Change:** replace the regex with `'\bcodex\s+exec\b'`, matching the shape already used by the sibling `plugin_uninstall_floor` / `plugin_disable_floor` floor rules in the same file. Leave `kind`, `enabled`, `message`, `allow_inline_override: false` untouched.

Note the `\b` before `codex` still matches `/usr/local/bin/codex` (`/` is a non-word char, so a word boundary exists before `c`) — that is the intent.

**Regression tests** (`plugins/leadv2/tests/test-deny-floor.sh`): add three cases asserting DENY for exactly the three bypass shapes above, following the existing case style in that file. Keep the pre-existing bare `codex exec …` and `; codex exec …` cases green.

Widening risk: `\bcodex\s+exec\b` now also fires inside a quoted string or a comment (e.g. `echo "run codex exec"`). This floor is deliberately blunt and `allow_inline_override: false`; the sibling floor rules accept the same false-positive surface. Accept, do not add lookarounds — the file's own comment (MERGED-BATCH-FIXROUND-01 H1) records that a clever single regex that fails to compile is silently skipped, i.e. simplicity is the safety property here.

## 2. RED SUITE — LANE-PLACEMENT-01 case P-e

**Files:** `plugins/leadv2/scripts/tests/test-lane-placement-pin.sh` (stub at lines 115–123), contract assertion added in the same suite.

Root cause confirmed by reading both sides:
- `leadv2-dispatch-code.sh:831` probes with `--json` and extracts fields via `_placement_probe_field` (`plugins/leadv2/scripts/leadv2-dispatch-code.sh:731-741`), which is `json.loads` with a bare `except Exception: pass`.
- The test stub emits plain text `alive` / `dead:exited`. `json.loads("alive")` raises, the exception is swallowed, `_v` is empty → the live branch is never taken → dispatch proceeds rc 0 where case P-e expects the refusal path rc 5.

Product code is correct. Fix the fixture.

**Change A — stub emits the real row shape.** Real shape comes from `leadv2-lane-liveness.sh:811` (`print(json.dumps(row, separators=(",",":")))` over the row built by `resolve()`), keys `verdict` / `reason` / `age_s`:

- live sentinel present → `{"lane":"<id>","verdict":"alive","reason":"process_alive","age_s":5,"pid_alive":true}`
- otherwise → `{"lane":"<id>","verdict":"dead:silent_9999s_no_process","reason":"log_silent_no_process","age_s":9999,"pid_alive":false}`

The dead-branch `verdict` string is cosmetic for the assert (only the `alive`/`starting:` prefixes are live-triggering at `leadv2-dispatch-code.sh:841`), but use the real `dead:silent_*_no_process` spelling so the fixture stays a faithful mirror. `reason=process_alive` also exercises the `_signal="pid_identity"` mapping at `:837-840`, which the journaled `lane_liveness verdict=live … signal=` line asserts on.

**Change B — contract assertion at the call site.** The reviewer's point: nothing today tests the `--json` contract itself, so stub-vs-real drift can silently re-open this hole. Add a case to the same suite that invokes the **real** `plugins/leadv2/scripts/leadv2-lane-liveness.sh --project-root <tmp> --lane <nonexistent> --no-codex --json` and asserts its stdout is a JSON object carrying the three keys `dispatch-code` consumes (`verdict`, `reason`, `age_s`). This case must not use the stub. If the real script's shape changes, this case fails before the placement cases silently pass for the wrong reason.

**Out of scope for this item:** the divergent untracked copy at `.claude/scripts/tests/test-lane-placement-pin.sh` (differs from the plugin copy, untracked by git). Do not edit or delete it in this lane; flagged below as a follow-up.

## 3. MEDIUM — subagent-lifecycle hook is not fail-open

**File:** `plugins/leadv2/codex-lead/marketplace/plugins/leadv2/hooks/leadv2-subagent-lifecycle.sh:6-30`

The embedded python has no top-level try/except, and the wrapper has no trailing `exit 0`. `os.makedirs` / `mkstemp` / `os.replace` on a read-only or unwritable registry dir raises, python exits non-zero, and the hook returns non-zero from a SubagentStart/Stop event — which can block subagent spawn.

**Change:** mirror the sibling `leadv2-native-pulse.sh` pattern verified in this repo (its tail is `except SystemExit: pass` / `except Exception: pass` / `PY` / `exit 0`):
1. Wrap the python body in `try:` … `except SystemExit: pass` … `except Exception: pass`. The `SystemExit` arm matters — the `stop` branch uses `raise SystemExit` as its normal exit path, so a bare `except Exception` would not catch it but an unwrapped `raise` inside a `try` with only `except Exception` would still propagate; keep both arms exactly as native-pulse has them.
2. Add a trailing `exit 0` after the `PY` terminator so a non-zero python exit (OOM, missing python3) still yields hook rc 0.

Preserve behaviour on the happy path: registry file content, filename hashing, atomic `os.replace`, tmp cleanup — byte-identical outcome.

**Test** (`plugins/leadv2/codex-lead/tests/test-codex-hooks.sh`): add a case that points `LEADV2_NATIVE_AGENT_REGISTRY` at an unwritable path (a `chmod 0500` tmp dir, or a path whose parent is a regular file) and asserts the hook exits 0 for both `start` and `stop`, and that a normal writable-dir `start` still writes the registry json.

**Deployment caveat (not a code change, a landing step):** hooks are the one exception to one-inode — the installed plugin *cache* is a separate copy and `claude plugin update` no-ops for a directory-source marketplace when content changed but the version did not. Landing this fix in the repo does not make it run. Either bump the plugin version or copy the hook into the cache and restart the session; state which was done in the lane's evidence.

## 4. HYGIENE

- **Delete** `plugins/leadv2/scripts/ZZ-pre-review-run.sh` — untracked 1217-line stale pre-fix copy of `leadv2-review-run.sh`, referenced by nothing (verified in review). Since it is untracked, `git rm` will not apply; plain `rm`, and note in the commit body that no tracked path changed for this item.
- **`.gitignore`:** append `docs/leadv2/burn-deferred.jsonl` and `docs/leadv2/burn-deferred.d/` in the existing `docs/leadv2/` runtime-artifact block (beside `bus.jsonl` / `merge-queue.jsonl`), same style, one comment line naming them as the burn-governor runtime ledger.

## Non-goals (explicit — do not touch)

- `leadv2-review-run.sh` fanout default (3→1 is intentional V3 design).
- Selector / profile-select files — owned by lane CLAUDE-PROFILE-SELECT-FINISH-01.
- `leadv2-worktree-protected.sh` pid-liveness — fail-safe direction, deferred by lead decision.
- Any product-code change in `leadv2-dispatch-code.sh` (item 2 is a fixture + test-contract fix only).
- The untracked divergent `.claude/scripts/tests/test-lane-placement-pin.sh`.
- No refactor of the deny-floor parser, no new env vars, no new scripts.

## Risks

| Risk | Mitigation |
|---|---|
| `\bcodex\s+exec\b` false-positives on quoted/commented text | Accepted — matches sibling floor rules; floor is blunt by design and the file's own H1 comment argues against clever regexes |
| Fixture "fixed" to a shape that is itself wrong | Change B pins the real script's `--json` keys in the same suite, so drift fails loudly |
| Hook fix lands in repo but stale copy keeps running from the plugin cache | Landing step above: version bump or cache copy + session restart, stated in lane evidence |
| Unwritable-dir hook test leaves a `chmod 0500` dir behind on failure | Test must `chmod u+w` in a `trap … EXIT` before `rm -rf` |
| No env vars introduced, no `claude -p` invocations, no concurrent read+write file races between items (all four touch disjoint files) | — checklist items 1, 3, 4 pass vacuously |

## Suites to run (all green before landing)

- `plugins/leadv2/tests/test-deny-floor.sh`
- `plugins/leadv2/scripts/tests/test-lane-placement-pin.sh`
- `plugins/leadv2/codex-lead/tests/test-codex-hooks.sh`, `test-codex-native-pulse.sh`, `test-codex-plugin-manifest.sh`

## acceptance:

```yaml
acceptance:
  - surface: log_line
    observable: "A test-deny-floor.sh run prints a DENY line for each of `env codex exec ...`, `/usr/local/bin/codex exec ...`, and `xargs -I{} codex exec {}`, and the run's final line reads that all cases passed with zero failures."
    authored_at: 2026-08-25T09:05:00Z
  - surface: log_line
    observable: "The lane-placement suite's final summary line reports zero failing cases, with case P-e listed as passing rather than as 3 failed asserts."
    authored_at: 2026-08-25T09:05:00Z
  - surface: log_line
    observable: "The codex-lead hook suite prints a passing line for a new case in which the subagent-lifecycle hook is given an unwritable registry directory and still reports success for both the start and the stop event."
    authored_at: 2026-08-25T09:05:00Z
  - surface: file_artifact
    observable: "`plugins/leadv2/scripts/ZZ-pre-review-run.sh` is absent from the working tree, and `.gitignore` contains lines for `docs/leadv2/burn-deferred.jsonl` and `docs/leadv2/burn-deferred.d/` so neither appears in the untracked-files section of a git status listing."
    authored_at: 2026-08-25T09:05:00Z
```

LANE_WRITES: plugins/leadv2/codex-lead/deny-extra.yaml, plugins/leadv2/tests/test-deny-floor.sh, plugins/leadv2/scripts/tests/test-lane-placement-pin.sh, plugins/leadv2/codex-lead/marketplace/plugins/leadv2/hooks/leadv2-subagent-lifecycle.sh, plugins/leadv2/codex-lead/tests/test-codex-hooks.sh, plugins/leadv2/scripts/ZZ-pre-review-run.sh, .gitignore

DELIVERABLE_COMPLETE
===== END SCOPED DESIGN =====

===== ORIGINAL MISSION (context only; the design above wins on any conflict) =====
CODEX-BATCH-REVIEW-FIXROUND-01 — fix the confirmed findings from the 2026-08-25 adversarial review of the 08-24 batch. All on main, one lane.

1. HIGH — deny-floor bypass (plugins/leadv2/codex-lead/…/deny-extra.yaml:42, rule codex_exec_direct): regex `(^|[;&|]\s*)codex\s+exec\b` misses prefixed forms — `env codex exec …`, `/usr/local/bin/codex exec …`, `xargs -I{} codex exec {}` all pass (live-probed). Fix: drop the start-anchor, match `\bcodex\s+exec\b` like the sibling plugin_uninstall_floor/plugin_disable_floor rules do. Add these three bypass shapes as regression tests in tests/test-deny-floor.sh.

2. RED SUITE — LANE-PLACEMENT-01 case P-e fails 3 asserts (test-lane-placement-pin.sh:114-122). Root cause (confirmed): the stub for LEADV2_DISPATCH_LANE_LIVENESS_BIN emits plain-text `alive`/`dead:exited`, but leadv2-dispatch-code.sh:831 now calls the probe with --json and parses via _placement_probe_field (json.loads, exceptions swallowed → empty verdict → dispatch proceeds rc 0 instead of refusing rc 5). Product code is correct; fix the fixture to emit the real JSON shape ({"verdict":"alive","reason":"process_alive","age_s":5} / dead variant), AND add a contract assertion at the dispatch-code call site so stub-vs-real shape drift trips the suite again (reviewer flagged: no test covers the --json contract itself).

3. MEDIUM — marketplace/plugins/leadv2/hooks/leadv2-subagent-lifecycle.sh:6-30 is not fail-open: python body (registry write, os.makedirs/os.replace) has no top-level try/except and the wrapper has no trailing exit 0 — a transient FS error propagates non-zero from a SubagentStart/Stop hook and can brick subagent spawn. Make it match leadv2-native-pulse.sh's fail-open pattern (except Exception: pass + exit 0). Add a test (read-only FS or unwritable dir → hook still exits 0).

4. HYGIENE:
   - Delete untracked plugins/leadv2/scripts/ZZ-pre-review-run.sh (1217-line stale pre-fix copy of leadv2-review-run.sh, referenced by nothing — verified).
   - Add docs/leadv2/burn-deferred.jsonl + docs/leadv2/burn-deferred.d/ to .gitignore (runtime burn-governor ledger, not source).

Do NOT touch: leadv2-review-run.sh fanout default (3→1 is intentional V3 design), the selector/profile-select files (separate lane CLAUDE-PROFILE-SELECT-FINISH-01 owns them), leadv2-worktree-protected.sh pid-liveness (fail-safe direction, deferred by lead decision).

Run: tests/test-deny-floor.sh, the lane-placement suite, codex-lead hook suites — all green before landing.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-df203d70" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.

Before you finish, run your own falsification set and paste its raw output into
your final report: `bash -n` every shell file you changed, `python3 -m
py_compile` every Python file you changed, and the repo's changed-scope test
runner. Show the red output you got and the green output after your fix. A lane
whose self-check is missing or red is refused before any reviewer is spent on
it -- you will have burned the lane for nothing.

Commit your work on the lane branch before ending your session; an uncommitted
exit is treated as an incident.