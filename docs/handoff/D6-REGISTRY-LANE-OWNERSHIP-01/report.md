# D6-REGISTRY-LANE-OWNERSHIP-01 — report

Lane: `worktree-D6-REGISTRY-LANE-OWNERSHIP-01`, head `1797c244` ("leadv2(D6-REGISTRY-LANE-OWNERSHIP-01): lead_session_id resolver, cap wiring, zsh-safe lane-state").

## What landed

| File | Change |
|---|---|
| `plugins/leadv2/scripts/lib/leadv2-lead-identity.sh` | NEW. `leadv2_lead_session_id()` → `lead-<durable_pid>-<birth_hash>`, built on `_lv2_durable_pid` / `_lv2_pid_birth` (sourced from `leadv2-active-registry.sh`, never re-implemented). Fail-open to `direct` with one stderr warning; resolution runs inside a subshell so active-registry's `set -euo pipefail` never leaks into callers. |
| `plugins/leadv2/scripts/lib/leadv2-lane-state.sh` | `lane_register`/`lane_adopt_pid` carry additive args 6/7 (`lead_pid`, `lead_pid_birth`) into the row; NEW `lane_lead_alive <lead-session-id>` — same liveness pattern as `lane_alive`, keyed on the owning lead process, corroborating recorded-vs-observed birth. Zsh-safety: `local path` renamed to `_lv2_mutate_path`/`_lv2_mutate_lock` (zsh ties `path` to `$PATH` — the old name made every child lookup die with `env: bash: No such file or directory`); `${BASH_SOURCE[0]:-$0}` fallback. |
| `plugins/leadv2/scripts/leadv2-session-runner.sh:197` | third fallback link replaced by the resolver |
| `plugins/leadv2/scripts/leadv2-codex-session-runner.sh:101` | same |
| `plugins/leadv2/scripts/leadv2-inbox.sh:123` (`drain`) | same |
| `plugins/leadv2/scripts/leadv2-broad-status.sh:1396` | same |
| `plugins/leadv2/scripts/tests/test-lead-session-identity.sh` | NEW suite, 6 cases, self-contained sandbox (no live state touched). |

Replacement shape at all four landed sites (identical one-liner + source guard):

```bash
_LV2_LEAD_IDENTITY_SH="${SCRIPT_DIR}/lib/leadv2-lead-identity.sh"
[[ -f "${_LV2_LEAD_IDENTITY_SH}" ]] && source "${_LV2_LEAD_IDENTITY_SH}"
_LEAD_CHAIN_VAR="${LEADV2_LEAD_SESSION_ID:-${LEADV2_PARENT_SESSION_ID:-$(declare -F leadv2_lead_session_id >/dev/null 2>&1 && leadv2_lead_session_id || printf -- 'direct')}}"
```

## NOT landed (owned by another session / out of bounds)

- **`leadv2-dispatch-code.sh:7071`** — not landed, another session owns the file. Exact replacement, ready to paste (at the `local _lead_session_id=...` line, with the two source-guard lines added just above it):
  ```bash
  _LV2_LEAD_IDENTITY_SH="${SCRIPT_DIR}/lib/leadv2-lead-identity.sh"
  [[ -f "${_LV2_LEAD_IDENTITY_SH}" ]] && source "${_LV2_LEAD_IDENTITY_SH}"
  local _lead_session_id="${LEADV2_LEAD_SESSION_ID:-${LEADV2_PARENT_SESSION_ID:-$(declare -F leadv2_lead_session_id >/dev/null 2>&1 && leadv2_lead_session_id || printf -- 'direct')}}"
  ```
- **CI does not select the suite yet.** `tests/run-all.sh` NOT touched (bounds). Needed row in `EXTRA_SUITE_MAP` (suite stem `test-lead-session-identity` does not match any changed-file stem, so `--scope changed` never picks it up without this):
  ```
  leadv2-lead-identity.sh:plugins/leadv2/scripts/tests/test-lead-session-identity.sh
  lane-state.sh:plugins/leadv2/scripts/tests/test-lead-session-identity.sh
  ```

## Scope note (interpretation, flagged for review)

Bounds say "declared write set only: the lib and its suite"; the mission also says "land everything OUTSIDE the dispatcher" and the acceptance (cap behaves differently for self vs other; ≥2 distinct identities in the live registry) is unreachable without wiring the resolver into the writers that feed `lane_register` and the cap. Landed reading: lib + suite are the new files; the four non-dispatcher consumers of the exact six-site chain got the one-link replacement; `leadv2-active-registry.sh`, `leadv2-claude-profile-select.sh`, `lib/leadv2-route-arbiter.sh`, `tests/run-all.sh`, `docs/leadv2/` untouched. `lib/leadv2-lane-state.sh` changes are the repair the brief points at (`:88-91` "names the real repair and does not make it").

## Acceptance 1 — the cap test (not a count of names)

Suite case 2, `LEADV2_LANE_CAP=1`, two identities resolved by the real resolver in two distinct OS processes, registered through the real `lane_register` (the same function `dispatch-code:7074` calls — the cap authority):

```
[TEST] PASS: cap proves defect dead: lane1(same session)=0 lane2(same session)=3(refused) lane3(other session)=0
```

Second lane of the SAME session → refused (rc=3, `lane cap exceeded`); lane of ANOTHER session → permitted (rc=0). With the pre-fix behavior both would collapse into one `direct` bucket and lane3 would be refused too — mutant control 1 below proves the suite reddens exactly there when identity collapses.

## Acceptance 2 — live check: ≥2 distinct lead_session_id in the live registry while two sessions work

Two real headless `claude` sessions (distinct OS processes) were launched concurrently; each ran one worker script as a child of its own claude process, resolving its identity through the wired resolver and registering a lane in the live registry (`~/.claude/leadv2-state/leadv2/active.yaml` — the state-dir file, not the `docs/leadv2/` render).

BEFORE (same registry, prior state): live rows carried no real per-session identities (`lead_session_id` = `recovered`×4, `None`×1).

MID-FLIGHT, both sessions working (verbatim poll output):

```
=== MID-FLIGHT LIVE REGISTRY (both sessions working) ===
task_id=d6-livecheck-A lead_session_id=lead-42020-388323463 session_id=lead-42020-388323463 phase=live_check pid=69019
task_id=d6-livecheck-B lead_session_id=lead-42018-388323463 session_id=lead-42018-388323463 phase=live_check pid=69534
distinct lead_session_id values: 2
```

Cross-check: the ids the workers themselves reported (`lid_a.txt`/`lid_b.txt`) match the registry byte-for-byte (`lead-42020-388323463` / `lead-42018-388323463` — each is that session's own claude pid + shared birth-second hash). Cleanup verified: 0 live `d6-livecheck*` rows remained after both sessions deregistered.

## Negative controls — one per changed function, mutation INSIDE the body

All via `plugins/leadv2/scripts/leadv2-mutation-control.sh` (scratch copy — the lane itself is never mutated; artifacts under `mutation-control/` in this directory). `restored_rc` for every row is the suite rc on the untouched lane after the control (0; the ten-run table). Every red line below is a behavioral consequence, not a parse failure.

| # | Function (file) | In-body mutation | baseline_rc | mutated_rc | red line observed |
|---|---|---|---|---|---|
| 1 | `leadv2_lead_session_id` (lead-identity) | birth guard always-false → id collapses to `direct` | 0 | 1 (mutant killed) | `FAIL: distinct owners: got A='direct' B='direct'` |
| 2 | `register` op, cap check (lane-state) | `if not existing and len(live) >= cap:` → `if False and ...` | 0 | 1 | `FAIL: cap proves defect dead: got lane1=0 lane2=0(want 3) lane3=0(want 0)` |
| 3 | `lead_alive` op corroboration (lane-state) | `recorded and observed and recorded == observed` → `recorded or observed` | 0 | 1 | `FAIL: lead alive corroboration: recorded birth mismatch got rc=0 (want 1)` |
| 4 | `lane_lead_alive` wrapper (lane-state) | drop `"$1"` (arg-drop crash) | 0 | 1 | `FAIL: lead alive corroboration: live owner + matching birth got rc=1 (want 0)` |
| 5 | `lane_register` wrapper (lane-state) | args 6/7 → `"" ""` (lead_pid never recorded) | 0 | 1 | `FAIL: lead alive corroboration: live owner + matching birth got rc=1 (want 0)` |

Honest near-miss, retained as an artifact: my first sed for control 5 (`s/ "${6:-}" "${7:-}"/"/`) removed a quote and broke the file parse (`unexpected EOF` at line 205 — verified by `bash -n` on the mutant); the tool accepted it, but a syntax-error control does not count, so it was replaced with the parse-preserving equivalent above (`"" ""`). Both artifacts are in `mutation-control/` (the invalid one is `20260904T030826Z-12467.txt`, `red_line` shows the 127s).

Falsification (message-text vs state): the suite asserts only on return codes, resolved identity strings, and registry row state — it contains no message-text assertions, so there is no message assertion to strip; all five controls redden via state alone.

Coverage hole (stated, not omitted): the four wiring sites in the runners/inbox/broad-status are top-level one-line assignments, not functions, so they have no enclosing body to mutate; the controls above cover the resolver and the lane-state functions those lines feed. A wiring-site mutant (e.g. sourcing the lib but keeping the constant `direct`) would be caught in production by the live check above, but there is no unit control for the four individual lines.

## Ten consecutive runs

All from committed HEAD `1797c244`, bash:

```
run 1 rc=0 ... run 10 rc=0   (all: [TEST] 6 passed, 0 failed)
```

No disagreement between runs. zsh (founder shell), same HEAD: `ZSH_FINAL_RC=0`, `6 passed, 0 failed`. The suite is deliberately zsh-proof: §1 constructs the two owner processes as background job shells (distinct pids by construction) after the original `: noop; bash -c` nesting proved fork-exec-luck-dependent — green under bash, both invocations collapsed onto one pid under zsh. That disagreement was treated as the finding and the construction replaced, per brief.

## Self-check

- `bash -n` on all seven net-diff files: ok (no Python files changed; embedded python is exercised by the suite).
- `git ls-files` shows both new files tracked: `plugins/leadv2/scripts/lib/leadv2-lead-identity.sh`, `plugins/leadv2/scripts/tests/test-lead-session-identity.sh`.
- Deletion check: `git diff --diff-filter=D --name-only main...HEAD` → empty (three dots, no deletions).
- Net lane diff `git diff main...HEAD --name-only` = exactly the seven files above; no `docs/leadv2/`, no `docs/LEAD_V2_STATE.md`, no `docs/handoff/dispatch-nw*` (checkpoint-swept runtime-state churn was subtracted in `1797c244`).

## Changed-scope test runner

PLACEHOLDER-RUNALL

## Residual risks

- The four wired sites + dispatcher site guard with `declare -F` before calling the resolver and fail open to `direct`, so a missing lib degrades to today's behavior, never a hard failure.
- `lane_lead_alive` is additive; no existing consumer changed behavior.
- The salvage-commit `0d3c436c` (keeper snapshot of this worktree, content identical to `1797c244`'s parent state) is superseded by `1797c244`; nothing in it exists only there.
