# PROMISE-GUARD-BIND-01 — bind the verdict to the promised artifact (design)

Scope: `plugins/leadv2/hooks/leadv2-promise-guard.sh` (524 L) + its 3 suites. No implementation here.

## 1. Findings (evidence first)

**F1 — the artifact is discarded before the verdict.** The extractor splits `final_text` on `[.!?\n;]`, then splits each sentence **on comma**, and appends the matching *clause* (`:355-372`). The quote is `arr[0][:280]` (`:452-459`). So `«Перепишу миссию, какую поверхность выселить»` is stored as the second clause only. The promise's object lives in a sibling clause and never reaches the verdict. Log confirms: a nameable target (path / TASK-ID-nn / backticked cmd) appears in only **15/344** fired quotes (4%) and **81/1237** suppressed quotes (7%).

**F2 — the recorder keeps no arguments, so there is nothing to bind against.** `:334-338`: `turn_tools.append('Bash:' + first_word)` for Bash, else `turn_tools.append(name)`. `Write`/`Edit`/ `Agent` are recorded as a bare name — `input.file_path`, `input.prompt`, and every Bash argument are dropped. Measured over 1581 rows the top label is `Bash:cd` (3327 occurrences, 5× the next), i.e. the recorder captures the shell prologue, not the work. **The recorder must change too.**

**F3 — suppressed_action is decided at `:446-450`,** `if HAS_ACTION == yes → suppressed_action else fired`, then `:496` exits silently. `has_action` is set at `:339-341` for *any* action tool anywhere in the turn, and `:403` (`action_after_promise = has_action`) is the 2026-08-22 revert of the positional rule (rationale `:374-402`). Presence, never identity.

**F4 — the brief's "one fired row in 1579" is wrong; the guard blocks a lot, and badly.** Census of `~/.claude/leadv2-promise-guard.jsonl` (1581 rows): `suppressed_action` 1237 (78%), `fired` 344 (22%); 193 of the fired had zero tools. The last eight zero-tool blocks are almost all non-promises: `Государству нужен не ты в Киеве`, `решение индивидуальное на КПП`, `and I'll do my best to assist you` (×2), `Please let me know what you'd like to work on`. So the guard is loose *and* noisy: it already costs the lead turns, on filler.

**F5 — schema is free.** Nothing outside the hook reads the JSONL or the strings `suppressed_action`/`fired` (repo-wide grep). The verdict vocabulary can change without a consumer migration.

**F6 — CI never selects the suites.** `tests/run-all.sh:8,:137` maps a changed file's stem to `test-<stem>.sh` **only under `plugins/leadv2/scripts/`**. The hook is under `hooks/`, and the suite is `test-promise-guard.sh`, not `test-leadv2-promise-guard.sh`. `--scope changed` selects nothing.

## 2. Design — bind to the target, not to presence

### 2a. One target grammar, applied to BOTH sides (symmetry is the mechanism)

| kind | shape | example |
|---|---|---|
| `path` | `[\w@./-]+\.(sh\|py\|ts\|tsx\|js\|json\|md\|ya?ml\|sql)` or `(docs\|plugins\|scripts\|web\|agent\|platform\|tests\|supabase)/[\w./-]+` | `plugins/leadv2/hooks/x.sh` |
| `task` | `\b[A-Z][A-Z0-9]+(?:-[A-Z0-9]+)+-\d{2}\b` | `PROMISE-GUARD-BIND-01` |
| `cmd` | head token of a backticked/bare run matching the existing `ACTION_BASH_RE` vocabulary (`:204-216`) | `leadv2-dispatch-code.sh` |
| `lane` | `dispatch-<task>` \| worktree `\b[0-9a-f]{8}\b` | `dispatch-LANE-FOO-01` |

Target must be ≥6 chars and not in a STOP set (`main`, `HEAD`, `README.md`, `context.yaml`).

### 2b. Promise side — widen the extraction window, keep the clause-level trigger

Trigger stays clause-level (the veto reconciliation at `:68-75` depends on it). **New:** once a clause matches, extract targets from the **whole sentence containing it**, plus the following clause when the sentence ends in `:` or `—`. Store that sentence as `promise_sentence`; keep `quote` unchanged for back-compat. Verb morphology (`:108-189`) is untouched.

### 2c. Action side — record targets per tool_use

| tool | targets from | counts as action |
|---|---|---|
| `Write` `Edit` `MultiEdit` `NotebookEdit` | `input.file_path` → repo-rel **and** basename | yes |
| `Bash` | full `input.command` scanned by 2a, plus `cmd:<head>` | only if `ACTION_BASH_RE` matches (unchanged) |
| `Task`/`Agent`/`Workflow` | `input.description` + `prompt[:800]` + `prompt[-200:]` scanned by 2a | yes |
| `Read` `Grep` `Glob` `WebFetch` | recorded, `action=false` | **no** — reading X never keeps "I'll rewrite X" |

Match rule: `path` → basename equality; `task`/`lane` → case-insensitive substring in any action target; `cmd` → head-token equality.

### 2d. Verdict (replaces `:446-450`; `has_action` becomes telemetry only)

| targets in promise | matched by an action | verdict | blocks? |
|---|---|---|---|
| 0 | — | `unbindable` | **never** — the honest answer for a vague promise |
| n | n | `bound_kept` | no |
| n | 1..n-1 | `bound_partial` | **no in v1** (shadow-logged; promote only on ledger evidence) |
| n | 0 | `bound_unkept` | yes, subject to §3 |

Reason string must name the miss, not the count: `Unkept: "<promise_sentence>" — promised docs/x/mission.md, LANE-FOO-01; this turn's actions touched: docs/other/context.yaml.`

### 2e. Log schema — additive only (F5 permits, but keep it additive anyway)

Keep `ts session_id cwd quote pattern n_commitments tools`. Add `promise_sentence`, `targets[]`, `matched[]`, `unmatched[]`, `actions[{name,targets}]`, `has_action` (telemetry). `verdict` vocabulary becomes the four values in 2d.

## 3. Bounding the false-block cost (Stop hook, every repo, every turn)

- **B1 — `unbindable` never blocks.** By F1's own measurement this removes ~96% of today's fired volume by construction: the politeness family (`I'll do my best…`) has no target and goes permanently silent. Net expected block rate drops from 344/1581 to single digits.
- **B2 — precision gates:** the ≥6-char + STOP-set filter (2a), and the existing past-tense/artifact veto (`:191-195`) applied to the clause before the sentence window opens.
- **B3 — hard cap:** `LEADV2_PROMISE_GUARD_MAX_BLOCKS` (default **1**) per session per UTC day, counter at `~/.claude/leadv2-promise-blocks-<session>.txt`. Worst case of any extraction bug is one lost turn per session. The per-turn sentinel (`:498-505`) stays.
- **B4 — two-stage rollout:** ship with new flag `LEADV2_PROMISE_GUARD_BLOCK` default **0** (log-only, zero blocks) for 3 days; flip to 1 only after the log shows ≥1 true `bound_unkept` and no obvious false one. Rollback is one env flip, never an edit. `LEADV2_PROMISE_GUARD=0` (`:21`) unchanged as the full kill. Ledger row required — leadv2 has no `scheduled-decisions.md`, so the row goes in persona-engine `docs/leadv2/scheduled-decisions.md` (the file the daily job scans).
- **B5 — budget:** `hooks.json:584` gives 5 s. Extraction is regex over ≤1 KB per block; stay in the single stdlib heredoc, no new process, no new dependency.

## 4. Negative controls — both directions, in `.claude/scripts/tests/test-promise-action-binding.sh`

`_transcript()` (`:52-77`) must gain per-block targets (a Write with a `file_path`, a Bash with a real command, an Agent with a prompt). N5 asserts on the JSONL row, not stdout.

| # | fixture | expect |
|---|---|---|
| N1 | promise "Перепишу `docs/handoff/X/mission.md` и диспатчу `LANE-FOO-01`" + `Write docs/handoff/OTHER/context.yaml` | **BLOCK**, reason names both targets (the 2026-08-30 ground-truth turn) |
| N2 | same promise + `Write docs/handoff/X/mission.md` + `Bash leadv2-dispatch-code.sh --task LANE-FOO-01` | SILENT (`bound_kept`) |
| N3 | `and I'll do my best to help you out`, tools `[]` | SILENT (`unbindable`) — today this BLOCKS; the 193-row regression |
| N4 | existing `recap` case (`Они идут параллельно и независимо`) | SILENT — must not regress |
| N5 | promise 2 targets, 1 touched | SILENT + log row `verdict=bound_partial`, `unmatched=["LANE-FOO-01"]` |
| N6 | promise `X.md`, turn only `Read X.md` | **BLOCK** — a read is not an action |
| N7 | **mutation:** force the match fn to `return True` inside its body | N1 + N6 go RED; run it and paste output |

CI: add an explicit stem row in `tests/run-all.sh` mapping `hooks/leadv2-promise-guard.sh` → the three suites (F6: the stem map only covers `plugins/leadv2/scripts/`), and prove it with `--scope changed`.

## 5. Out of scope for the implementer

Verb morphology and `COMMIT_*` patterns (`:108-189`); the past-tense/artifact veto (`:191-195`); the reverted positional rule (stays reverted — 2c's `action=false` for reads is not a revival of it); `leadv2-prose-guard` / `leadv2-continuation-guard`; any repo other than `~/Projects/leadv2`; and promoting `bound_partial` to blocking (a separate ledger-gated decision).

DELIVERABLE_COMPLETE
