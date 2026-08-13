Product implementation task dispatch-40241035. Implement ONLY the scoped design below; preserve its non-goals. Before closing, run the required end-to-end gate and the cross-provider review gate recorded for this task.

===== SCOPED DESIGN (authoritative) =====
# DISPATCH-FG-GUARD-01 — architect prepass

Repo: `~/Projects/leadv2` · `git rev-parse HEAD` = `dec659204427576dd5098173b50e69eff0d0bbbe`

## 0. Scope in one line

Two independent, additive changes: (C1) a new fail-open PreToolUse:Bash hook that denies a
*foreground* invocation of a long-running leadv2 worker launcher; (C3) enrich one existing
`exit 5` refusal message in `leadv2-dispatch-code.sh` with verdict, age, and the literal re-run
command. No control-flow change anywhere.

---

## 1. Surveyed facts (do not re-derive)

| Fact | Evidence |
|---|---|
| Hook dir | `plugins/leadv2/hooks/` — 87 hooks, all `#!/usr/bin/env bash` |
| Existing model | `plugins/leadv2/hooks/leadv2-block-fg-agent.sh` — `set -euo pipefail`, `trap '… exit 0' ERR`, `INPUT="$(cat 2>/dev/null || true)"`, `[[ -z "$INPUT" ]] && exit 0`, deny = `exit 2` with message on **stderr** |
| Override convention | `leadv2-block-bash-heredoc.sh:22` — `printf '%s' "$CMD" \| grep -q '# bash-guard: allow'` then `exit 0` |
| Command extraction | heredoc hook parses `tool_input.command` via inline `python3 -c` JSON read (NOT jq) — 11 PreToolUse entries; the `Bash` matcher entry already contains 7+ hooks |
| `run_in_background` | For **Agent** it is not passed (documented in `leadv2-block-fg-agent.sh:28`). For **Bash** it IS a real `tool_input` field of the Bash tool, so `tool_input.run_in_background` is expected present-or-absent — design must treat *absent* as "unknown → fall back to textual test", never as "false". |
| C3 site | `plugins/leadv2/scripts/leadv2-dispatch-code.sh:588-594` — `reason="lane_is_live"`, `emit decision …`, `printf … >&2`, `exit 5`. Probe loop above it (lines 582-587) already holds `_v` (verdict) and `_probe_id`. |
| Liveness contract | `plugins/leadv2/scripts/leadv2-lane-liveness.sh` accepts `--project-root --lane --no-codex --json`. Without `--json` it prints `row["verdict"]` only (line 459). With `--json` it prints the whole row: `{lane, verdict, age_s, source, log_path, reason}`. **`age_s` is the field C3 needs and it is only reachable via `--json`.** |
| Test registry | Suites are registered by an explicit `run_check "<label>" bash "$TEST_DIR/test-*.sh"` line in `plugins/leadv2/scripts/tests/run-core-offline.sh` (lines 82-112). `tests/run-all.sh` drives that runner; on `--scope changed` it also picks up `test-*.sh` whose **stem matches a changed file's stem** under `plugins/leadv2/scripts/`. A suite that is not registered and whose stem does not match a changed script is **never executed**. |
| Test style | `plugins/leadv2/scripts/tests/test-hook-token-mode-isolation.sh` — sources `../leadv2-temp.sh`, `lv2_mktemp_dir`, `PASS`/`FAIL` counters, `pass()`/`fail()` printing `[TEST] PASS: …`, `trap cleanup EXIT`. |

### Write-set correction (CRITICAL, must be honoured)

The mission's write set says `tests/` ("the repo's existing hook test location"). That is **wrong
for a hook test**. Root `tests/` holds 6 status-surface/e2e suites only; every hook regression
lives in `plugins/leadv2/scripts/tests/`. Placing the new suite in root `tests/` leaves it
unregistered and unrun. Implementation writes the suite to
`plugins/leadv2/scripts/tests/test-fg-dispatch-guard.sh` and registers it in
`run-core-offline.sh`. Both paths are declared in `LANE_WRITES`.

---

## 2. C1 — `plugins/leadv2/hooks/leadv2-block-fg-dispatch.sh` (new)

### Data flow (numbered)

1. Claude Code fires PreToolUse for tool `Bash`; hook receives the tool-call JSON on stdin.
2. `INPUT="$(cat 2>/dev/null || true)"`; empty → `exit 0` (fail-open #1).
3. Single `python3 -c` pass over the JSON emits two lines: line 1 = `tool_input.command`, line 2 =
   `tool_input.run_in_background` normalised to `true`/`false`/`` (empty = key absent). Any parse
   exception → print nothing → both vars empty → `exit 0` (fail-open #2). One parse, not two, so a
   malformed payload cannot half-succeed.
4. Empty command → `exit 0`.
5. **Override:** `grep -q '# fg-dispatch: allow'` → `exit 0`.
6. **Target match:** does the command mention a guarded launcher *basename*? Match on the
   basename token so `bash /abs/path/x.sh`, `./x.sh`, `$DIR/x.sh` and a bare alias all hit:
   `grep -Eq '(^|[^[:alnum:]_./-])(leadv2-dispatch-code|leadv2-codex-session-runner|leadv2-fanout|glm-coder|omp-task)\.sh([^[:alnum:]_-]|$)'`.
   No match → `exit 0`.
7. **Exemptions** (any hit → `exit 0`): `--no-spawn`, `LEADV2_DISPATCH_SPAWN=0`, `--help`/`-h`,
   and the `status` / `record-review` subcommands. Subcommands are matched as whole words
   (`[[:space:]](status|record-review)([[:space:]]|$)`) so a path fragment like
   `.../status-surface.sh` cannot be mistaken for the `status` subcommand.
8. **Backgrounded test** — deny only if ALL of these are false:
   - `run_in_background` field parsed as `true` (authoritative when present);
   - command matches trailing-`&`: `[[:space:]]&[[:space:]]*$` (also accepts `&` followed by a
     trailing `# comment`, and `& disown`/`&& wait`-free forms — see risk R3);
   - command contains `nohup` … with a `&`;
   - command contains `setsid`.
9. Otherwise: write the deny message to **stderr**, `exit 2`.
10. Any uncaught error anywhere → `trap '… exit 0' ERR` (fail-open #3).

### Deny message contract

Must contain, verbatim-checkable by the test:
- the marker `[leadv2-block-fg-dispatch] BLOCKED`;
- the cause sentence naming **the 2-minute Bash tool timeout SIGTERMing the process group**;
- the line `Run this instead:` followed by the caller's own command with ` &` appended (echo
  back `$CMD` — do not synthesise a canonical command, the caller's flags must survive);
- the override hint `# fg-dispatch: allow`.

### Registration

Append one entry to the existing `"matcher": "Bash"` object inside
`hooks.json → hooks.PreToolUse`, after `leadv2-block-bash-heredoc.sh`:

```json
{ "type": "command",
  "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/leadv2-block-fg-dispatch.sh\"",
  "timeout": 5,
  "statusMessage": "Foreground-dispatch guard..." }
```

Do **not** create a second `"matcher": "Bash"` entry — the existing one is the only Bash matcher
and duplicating it risks ordering ambiguity.

### Interface contract

| Direction | Shape |
|---|---|
| stdin | `{"tool_name":"Bash","tool_input":{"command":"…","run_in_background":bool?},"cwd":"…"}` |
| exit 0 | allow (also every failure mode) |
| exit 2 | deny; stderr text is shown to the model |
| env | `LEADV2_ALLOW_FG_DISPATCH=1` → unconditional `exit 0` (secondary escape hatch, mirrors `LEADV2_ALLOW_FG` in `leadv2-block-fg-agent.sh`) |

---

## 3. C3 — actionable `lane_is_live` refusal

Site: `plugins/leadv2/scripts/leadv2-dispatch-code.sh`, the `if (( _live == 1 ))` block at ~588.

1. Immediately before the refusal `printf`, re-probe the *winning* `_probe_id` with `--json`:
   `_row="$(bash "${LANE_LIVENESS_BIN}" --project-root "${PROJECT_ROOT}" --lane "${_probe_id}" --no-codex --json 2>/dev/null || true)"`
2. Extract `age_s` with a bounded `python3 -c` read; on any failure set `_age="?"`. **Fail-open:
   an unreadable age must not change the exit path** — it is still `exit 5`.
3. Print (stderr, replacing the current 2-line `printf`):
   ```
   [leadv2-dispatch-code] REFUSE placement: lane_is_live ref=<ref> path=<candidate>
     verdict=<_v> age=<_age>s probe_id=<_probe_id>
     The lane is still running. Re-run once it clears:
       <original argv> &
   ```
4. `<original argv>` comes from a snapshot taken **before any argument parsing**, near the top of
   the script: `LEADV2_DISPATCH_ARGV=("$0" "$@")`, rendered with `printf '%q '`. Placing it after
   the first `shift` yields a truncated, wrong command — that is the one ordering constraint in C3.
5. The `emit decision` line already carries `verdict=` and `probe_id=`; extend it with `age=` for
   journal parity. No other change.

Behaviour invariant: same condition, same `exit 5`, same `emit` event name. Only the human-facing
bytes change.

---

## 4. Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | New suite lands in root `tests/` per the mission's write set → never executed, acceptance is vacuous | Suite goes to `plugins/leadv2/scripts/tests/` **and** gets a `run_check` line in `run-core-offline.sh`. Verify by grepping the runner output for the suite label. |
| R2 | A false deny wedges the lead out of dispatching entirely | Three independent fail-open layers (empty stdin, parse failure, ERR trap) + `# fg-dispatch: allow` + `LEADV2_ALLOW_FG_DISPATCH=1`. Every ambiguous state resolves to allow. |
| R3 | Trailing-`&` regex misfires: `cmd && other`, `cmd &> log`, `foo=1&2` | Anchor on `[[:space:]]&[[:space:]]*(#.*)?$` — requires whitespace before `&` and nothing but optional comment after. `&&` and `&>` cannot match because they have a non-space char after `&`. Add explicit negative test cases for `&&` and `&>`. |
| R4 | `run_in_background` absent is read as `false` → denies a call the harness would have backgrounded | Tri-state parse: `true` / `false` / *absent*. Only an explicit `true` short-circuits to allow; absent falls through to the textual test, and the textual test's own failure still denies — which is the intended conservative direction for an interactive fg call. Documented in the hook header. |
| R5 | Basename regex hits a *mention* of the script inside a `grep`/`cat`/`echo` (e.g. `grep -n foo leadv2-dispatch-code.sh`) → spurious deny | Accepted, mitigated by the override comment. Deliberately not solved by parsing shell grammar — a parser here is a bigger correctness liability than an occasional override. Note it in the deny message ("if you were only reading the file, append `# fg-dispatch: allow`"). |
| R6 | `hooks.json` edit breaks JSON → every hook in the plugin stops loading | Implementation must run `python3 -m json.tool plugins/leadv2/hooks/hooks.json >/dev/null` after the edit and include that in the test suite. |
| R7 | C3's argv snapshot placed after parsing → wrong "re-run this" command printed, i.e. the exact class of bug (a confidently-wrong artifact) this task exists to kill | Snapshot line is the first executable statement after `set -…`; test asserts the printed command round-trips the original flags. |
| R8 | Hook lands in canonical but the plugin **cache** copy is stale, so it never loads in a live session | Known plugin-cache gotcha (global CLAUDE.md, shared-trees §). Out of this lane's write set — report it in the handoff as a required post-merge step, do not silently assume the hook is live. |
| R9 | Two parallel lanes editing `hooks.json` | Single-file, append-one-entry edit; re-`git diff hooks.json` immediately before `git add`. |

### Constraint checklist

1. **Env vars** — `LEADV2_ALLOW_FG_DISPATCH`, `LEADV2_DISPATCH_SPAWN` both `LEADV2_*`. No
   `LEAD_V2_*` drift. `LEADV2_DISPATCH_SPAWN` is read here only as a *textual exemption in the
   command string*, never as a live env read — no semantic contradiction with existing usage.
2. **Paths** — all four write paths verified: `hooks.json`, `leadv2-dispatch-code.sh`,
   `run-core-offline.sh` exist; `leadv2-block-fg-dispatch.sh` and `test-fg-dispatch-guard.sh` are
   `(to-create)`.
3. **`claude -p`** — none introduced. N/A.
4. **Concurrent access** — see R9.
5. **Config contradiction** — none found.

---

## 5. Non-goals (implementer: ignore these)

- Phase/pipeline structure (cause C4) — founder-owned, explicitly out of scope.
- Routing, quota gates, arm resolution — untouched.
- Any behaviour change in `leadv2-dispatch-code.sh` beyond the message bytes and the argv snapshot.
- Changing `leadv2-block-fg-agent.sh` or the Agent-side fg problem.
- Deleting/deduplicating `.claude/scripts/tests/` (separate open thread).
- Refreshing the plugin cache (R8) — reported, not performed.

## 6. Rollback

Delete the `leadv2-block-fg-dispatch.sh` entry from the `"matcher": "Bash"` array in
`plugins/leadv2/hooks/hooks.json`. That alone fully disarms C1. C3 is message-only and needs no
rollback.

---

acceptance:
- surface: rendered_line
  observable: A lead runs `bash plugins/leadv2/scripts/leadv2-dispatch-code.sh @mission.md` with no
    trailing `&`; instead of the dispatch starting, the terminal shows a block notice headed
    `[leadv2-block-fg-dispatch] BLOCKED` that says the 2-minute Bash tool timeout would SIGTERM the
    process group, and shows that same command with ` &` appended under `Run this instead:`.
  authored_at: 2026-08-05T00:00:00Z
- surface: rendered_line
  observable: The identical command typed with a trailing `&`, and the variants ending in
    `status`, `--help`, `--no-spawn`, and `# fg-dispatch: allow`, produce no block notice at all —
    the dispatch proceeds as it did before this change.
  authored_at: 2026-08-05T00:00:00Z
- surface: log_line
  observable: In the lane journal, the refusal event for a live lane reads
    `lane_placement_refused … reason=lane_is_live … verdict=alive age=<n> probe_id=<id>` — a
    reader sees how old the live lane is, where before the line carried no age at all.
  authored_at: 2026-08-05T00:00:00Z
- surface: rendered_line
  observable: When dispatch refuses a live lane, the terminal shows the verdict, the lane's age in
    seconds, and on its own indented line the complete command the lead can paste to retry once
    the lane clears — not just the reason and the path.
  authored_at: 2026-08-05T00:00:00Z
- surface: rendered_line
  observable: Running the repo's offline regression runner prints a `[TEST] PASS` line for the
    foreground-dispatch guard suite among the other suites, and the run ends reporting zero
    failures.
  authored_at: 2026-08-05T00:00:00Z

LANE_WRITES: plugins/leadv2/hooks/leadv2-block-fg-dispatch.sh, plugins/leadv2/hooks/hooks.json, plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/tests/test-fg-dispatch-guard.sh, plugins/leadv2/scripts/tests/run-core-offline.sh

DELIVERABLE_COMPLETE
===== END SCOPED DESIGN =====

===== ORIGINAL MISSION (context only; the design above wins on any conflict) =====
# DISPATCH-FG-GUARD-01 (plugin repo ~/Projects/leadv2)

## Outcome
A long-running leadv2 worker launch can no longer be silently killed by the Bash tool's
foreground timeout, and a lane refused as live tells the caller how to proceed.

## Incident this fixes (2026-08-05, do not re-derive)
The lead ran `leadv2-dispatch-code.sh` in a foreground Bash call. The 2-minute tool timeout
SIGTERMed the process group mid architect-prepass. The lead then judged liveness from
`ls -la` mtime — 2 minutes old, because a dying process writes on its way out — and reported the
lane as working. It was dead for 38 minutes. Full causes:
`~/Projects/persona-engine/docs/handoff/DISPATCH-KILLED-BY-FG-TIMEOUT-01/causes.md`.

## Repo / base
Work in `~/Projects/leadv2`. Record `git rev-parse HEAD` there in your first line.

## Write set (allowed paths ONLY)
- `plugins/leadv2/hooks/leadv2-block-fg-dispatch.sh` (new)
- `plugins/leadv2/hooks/hooks.json` (register the new PreToolUse Bash hook)
- `plugins/leadv2/scripts/leadv2-dispatch-code.sh` (C3 — message only, no behaviour change)
- `tests/` (the repo's existing hook test location)

## C1 — block the foreground launch
New PreToolUse hook on `Bash`, modelled on the existing `leadv2-block-fg-agent.sh`: same input
parsing, same fail-open `trap ... exit 0` discipline, same exit-code convention.

Deny a Bash command that invokes a long-running worker launcher when the call is NOT
backgrounded. Match by basename so path and alias variants are covered:
`leadv2-dispatch-code.sh`, `leadv2-codex-session-runner.sh`, `leadv2-fanout.sh`, `glm-coder.sh`,
`omp-task.sh`.

"Backgrounded" = the command ends in `&`, or uses `nohup ... &`, or `setsid`, or the tool call set
`run_in_background`. If the hook input exposes `run_in_background`, honour it; otherwise fall back
to the textual `&` / `nohup` / `setsid` test.

Exempt, so the guard never blocks legitimate quick calls: `--no-spawn`,
`LEADV2_DISPATCH_SPAWN=0`, the `status` and `record-review` subcommands, `--help`.

The deny message must state why (the 2-minute tool timeout SIGTERMs the process group) and the
exact corrected command to run instead. Override escape hatch: a trailing `# fg-dispatch: allow`
comment, matching the convention `leadv2-block-bash-heredoc.sh` already uses.

**Fail open.** A hook that errors must exit 0 — never wedge the lead out of dispatching.

## C3 — make the live-lane refusal actionable
In `leadv2-dispatch-code.sh`, the exit-5 `lane_is_live` refusal (around lines 582-595) prints the
reason and path only. Add the liveness verdict, its age in seconds, and the literal command to
re-run once it clears. Message only — no behaviour change.

## Non-goals
Do NOT touch the phase/pipeline structure — that is cause C4, a separate founder decision,
explicitly out of scope. Do not change routing, quota gates, or arm resolution.

## Acceptance
- A foreground `bash .../leadv2-dispatch-code.sh @mission.md` is DENIED, message contains the
  corrected command.
- The same command with a trailing `&` is ALLOWED.
- `status`, `--help`, `--no-spawn` are ALLOWED.
- `# fg-dispatch: allow` overrides the deny.
- Malformed/empty stdin exits 0 (fail-open).
- The repo's existing hook test suite passes from a clean base.

## Rollback
Remove the hook's entry from `hooks.json`. Name it explicitly in your report.

## Return
`PASS|FAIL|BLOCKED` + changed paths + commit + raw test output. Do not edit boards or plans.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-40241035" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.