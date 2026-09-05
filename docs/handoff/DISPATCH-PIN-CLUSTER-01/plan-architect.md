# DISPATCH-PIN-CLUSTER-01 — architect plan (design only, no implementation)

Repo `/Users/kostiantyn.vlasenko/Projects/leadv2`. Write set: `plugins/leadv2/scripts/leadv2-dispatch-code.sh`, `…/leadv2-dispatch-product-close.sh`, `…/leadv2-dispatch-ledger.sh`, `…/lib/leadv2-admission-class.sh`, `…/lib/leadv2-lane-guard.sh` (to-create). All line refs verified on the live tree 2026-08-30.

## D1 — the worktree pin is prompt text, never a check

`leadv2-dispatch-code.sh:946-949`:
```
_set_worktree_pin_line() {
  [[ -n "${WORK_ROOT:-}" && "${WORK_ROOT}" != "${PROJECT_ROOT}" ]] || return 0
  WORKTREE_PIN_LINE="WORKTREE PIN: all edits go in ${WORK_ROOT}; do NOT cd to the main checkout…"
```
**Mechanism.** The pin is a *string prepended to the mission* (`:4616`). The only physical placement is `--cwd "${WORK_ROOT}"` (`:4639` glm, `:4679` kimi, `:4727` freepool, `:4879` codex) and `cd "${WORK_ROOT}" && … SUBSESSION_BIN` (`:4779`). cwd is an initial condition, not a boundary: one `cd`, or one absolute path in the mission text, and the worker writes into `${PROJECT_ROOT}`. Nothing re-checks — `_DISPATCH_WORKER_LIVE=1` (`:7052`) is set at spawn and the lane is never compared against the main checkout again.

**Fix.** (1) *Baseline at spawn*: in `spawn_worker` (`:4590`), before the arm `case`, when `WORK_ROOT != PROJECT_ROOT`, record `git -C "$PROJECT_ROOT" status --porcelain --untracked-files=all` (path list + digest) to `docs/handoff/dispatch-<sig8>/main-dirt.base`. (2) *Containment verdict*: new `lib/leadv2-lane-guard.sh::lv2_lane_containment_violation <sig8> <work_root> <project_root>` recomputes the main porcelain, set-diffs against the baseline, rc0 when a path appeared in main outside the orchestration-exclude set — called from the close gate (D2's choke point), ONE call site, not per-arm; verdict `refused cause=wrote_outside_lane`, never `landed`. (3) Export `LEADV2_WRITE_ROOT="${WORK_ROOT}"` beside `LEADV2_LANE_WORK_ROOT` (`:4516`) on every arm launch so a child-side guard can deny on the same value later.

## D2 — the arm-exit contract: every place success can be claimed

| # | Site | Asserts | Reaches ledger? |
|---|---|---|---|
| 1 | `dispatch-code.sh:5545-5560` `atomic_dispatch_reserve_spawn_confirm` rc=0 | worker is *live* | no terminal by design (LANDED-AT-SPAWN-01, `:7042-7050`) |
| 2 | `dispatch-code.sh:1750` `_dl_note` | refused/parked/dead only — never `landed` | yes |
| 3 | `dispatch-product-close.sh:140` `_dl_note` | **the only `landed` writer** — 8 sites `:2378 :2820 :2829 :2847 :2894 :3247 :3265 :3281` | yes |
| 4 | `leadv2-session-runner.sh:164/235/477` `phase8-passed.flag` | attempt-level "done" | no (feeds 3) |
| 5 | `leadv2-fanout-lane-launcher.sh:126` | fanout lanes (dormant under single-lead) | yes |
| 6 | `leadv2-dispatch-ledger.sh:250` `dispatch_ledger_write_terminal` / CLI `write-terminal` (`:1064`) | **single funnel — 2, 3, 5 and every future writer pass through it** | — |

Choke point = **6**, with **3** as the semantic layer. The rule goes inside `dispatch_ledger_write_terminal` so no arm, runner or future caller can route around it:
```
case "$3" in landed)
  _lr="$(LEADV2_PROJECT_ROOT="$PROJECT_ROOT" bash "$SCRIPT_DIR/leadv2-lane-worktree.sh" path-of "${2:-$1}")"
  if [[ -n "$_lr" ]] && lv2_lane_dirty "$_lr"; then set -- "$1" "$2" pass_unlanded "dirty_lane:$4" "${@:5}"; fi ;;
esac
```
`pass_unlanded` already exists in the vocabulary (`dispatch-product-close.sh:3269`), is retryable and already renders in the status surface — no new terminal word. `lv2_lane_dirty` is `_pc_lane_dirty` (`dispatch-product-close.sh:1377-1385`) lifted verbatim into `lib/leadv2-lane-guard.sh` together with `_PC_PORCELAIN_EXCLUDE_RE` and `_pc_drop_bootstrap_dirt`, so the two definitions cannot diverge — they already diverged once (`:1290-1296`).

The STOP-GATE paragraph (`dispatch-code.sh:6389-6393`) stays as advice and `leadv2-turncap-checkpoint-commit.sh` stays as recovery. Neither is enforcement: turncap commits only `touched-files manifest ∩ dirty`, which is exactly the 3-of-5 incident. Enforcement is one sentence — **a dirty lane can never produce `landed`.**

## D3 — the binding plan never reaches the lane

Every handoff path is built on `${PROJECT_ROOT}`, e.g. `dispatch-code.sh:7007`:
```
_lane_mission_path="${PROJECT_ROOT}/docs/handoff/dispatch-${sig8}/lane-mission.md"
```
same at `:2707 :2745 :3316 :4236 :6201`. **Mechanism.** The mission travels in argv (survives); the plan does not. `docs/handoff/` is excluded from the writes grammar by contract (`:3425`), the lane branches from `origin/main`, and an untracked file in the main checkout does not exist on the lane branch — so `docs/handoff/<task>/context.yaml` never resolves under `${WORK_ROOT}` and codex returns BLOCKED. Nothing copies anything into `${WORK_ROOT}`; its only uses are `--cwd` and the pin string.

**Fix.** New `_deliver_plan_into_lane <sig8> <founder_task_id>` in `dispatch-code.sh`, called from `cmd_resolve` after `_resolve_pinned_placement` (`:6023`) and before any spawn: (1) no-op when `WORK_ROOT == PROJECT_ROOT`; (2) `mkdir -p "${WORK_ROOT}/docs/handoff/${founder_task_id}"` and copy `context.yaml`, `brief.md`, `plan-*.md` from the main checkout — copy, not commit, since the handoff dir is writes-grammar-excluded (no branch pollution, no merge conflict); (3) **fail loudly** — if the source `context.yaml` exists and the copy does not resolve under `${WORK_ROOT}`, `emit decision "lane_plan_missing …"` + `_dl_note "${sig8}" refused plan_not_in_lane` + `exit 5`, the same refusal contract `_resolve_pinned_placement` already uses; (4) prepend ONE mission line naming the lane-local absolute plan path so no arm has to guess.

## D4 — class re-derived from the current mission text

`dispatch-code.sh:6082-6083`:
```
_admission_classify "${mission}" "${sig}" "${sig8}" "${task_class}" "${task_class_flagged:-0}"
task_class="${ADMISSION_CLASS}"
```
**Mechanism, two layers.** (a) `_admission_classify` (`:3488-3543`) feeds the *mission text* to `TASK_JUDGE_BIN --mission-file`. (b) The memo that would have saved it — the admission receipt — is keyed `docs/handoff/dispatch-<sig8>/admission-receipt.yaml` (`lib/leadv2-admission-class.sh:108-116`) and `sig8` is `sha256(normalised mission text)` (`compute_sig :1770`). A 40-line resume mission is a different digest ⇒ different sig8 ⇒ receipt miss ⇒ re-judged from the short text. `--task-class` is *already* honoured escalate-only (`lib/leadv2-admission-class.sh:64-88`); the gap is that nothing carries the class forward when the flag is absent.

**Fix — key on the task record, not the mission.** (1) Second receipt `docs/handoff/<founder_task_id>/task-class.yaml`, written by `leadv2_admission_write_receipt` whenever `founder_task_id` is non-empty. (2) In `_admission_classify`, after the sig8-receipt miss and **before** invoking the judge, read the task receipt and treat its class as a **floor**: `ADMISSION_CLASS=max(task_floor, mapped)`, `ADMISSION_SOURCE=task_record`; reuse the existing ladder by extracting `_lv2_class_rank` from `leadv2_admission_class` — never a second ordering. (3) `founder_task_id` is already bound before the call (`:6072`), so no new plumbing. Net: a resume mission may escalate a class, never demote it; freepool stops receiving Heavy work.

## Ordering, dependencies, shared helper

1. **Extract `lib/leadv2-lane-guard.sh` FIRST** — `lv2_lane_dirty`, `_PC_PORCELAIN_EXCLUDE_RE`, `_pc_drop_bootstrap_dirt`, `lv2_lane_root_is_own_worktree`, `_lv2_class_rank`. Pure move + `source` from `dispatch-product-close.sh`, zero behaviour change. Everything below depends on it.
2. **D2** — the choke point. Must precede D1: D1's verdict is delivered *through* it.
3. **D1** — baseline at spawn + containment call from the close gate.
4. **D3** — independent of 1-3; sequence after D2 to keep one reviewable diff.
5. **D4** — fully independent (`lib/leadv2-admission-class.sh` + one call site).

## Negative controls (one per fix; mutation applied INSIDE the function body)

| Fix | Mutation | Suite that must go red |
|---|---|---|
| D2 | In `dispatch_ledger_write_terminal`, delete the `landed→pass_unlanded` downgrade branch (keep the function) | `tests/test-dirty-lane-never-lands.sh` (new): seed a lane worktree with one uncommitted tracked edit, call `write-terminal … landed`, assert the row reads `pass_unlanded` |
| D1 | In `lv2_lane_containment_violation`, `return 1` unconditionally as the first body statement | `tests/test-lane-containment.sh` (new): write a file into the fake main checkout during a pinned dispatch, assert terminal `refused cause=wrote_outside_lane` |
| D3 | In `_deliver_plan_into_lane`, replace the `exit 5` refusal with `return 0` | `tests/test-plan-in-lane.sh` (new): dispatch `--worktree <lane>` with `context.yaml` in main only, assert rc=5 and `lane_plan_missing` journalled |
| D4 | In `_admission_classify`, drop the task-receipt floor read (fall straight through to the judge) | extend `plugins/leadv2/scripts/tests/test-admission-class.sh`: Heavy full mission, then a 40-line resume with the same `--task-id`; assert `task_class=Heavy source=task_record` |

CI selection is NOT automatic. Add four `EXTRA_SUITE_MAP` rows at `tests/run-all.sh:105-120` (`leadv2-dispatch-ledger:…/test-dirty-lane-never-lands.sh`, `leadv2-dispatch-code:…/test-lane-containment.sh`, `leadv2-dispatch-code:…/test-plan-in-lane.sh`, `leadv2-dispatch-code:…/test-admission-class.sh`) and prove each with `bash tests/run-all.sh --scope changed`. A suite `run-all.sh` never selects is worth nothing. Must stay green: `test-lane-placement-pin.sh`, `test-lane-root-not-a-worktree.sh`, `test-lane-close-loop.sh`, `test-lane-outcome.sh`, `test-close-chain.sh`, `test-admission-class.sh`.

## Risks — this dispatcher launches every lane in every repo

| Risk | Mitigation |
|---|---|
| **R1 — D2 turns every lane into `pass_unlanded`.** The exclude-set IS the safety property; per-turn injector hooks dirty every lane worktree (`dispatch-product-close.sh:1298`). A narrower copy inside the ledger = universal false positive: nothing ever lands, in any repo. | Call only the *extracted* `lv2_lane_dirty`; a grep-gate in the suite forbids a second porcelain call site. Ship behind `LEADV2_DIRTY_LANE_GATE` — shadow-log first, flip after one clean day. |
| **R2 — the ledger becomes a decision-maker**, contradicting its own header ("never gates a dispatch decision", `:64-66`). | Downgrade only, never refuse the write: the row is always written, so no lane is lost. Update that header comment in the same commit. |
| **R3 — D1 false positive from a concurrent session** — main-checkout dirt from another `/leadv2` session attributed to this lane. | Baseline is a set-diff, not a boolean: only paths that appeared after this spawn, and only outside the exclude set. On ambiguity → `pass_unlanded`, never `refused`. |
| **R4 — D3 plan copies get committed onto the lane branch.** | Copy into `docs/handoff/`, already excluded by the writes grammar (`:3425`); assert the exclusion in the suite. |
| **R5 — D4 floor pins a genuinely small follow-up to Heavy forever.** | Floor is per `founder_task_id`; an explicit flagged `--task-class` still wins downward (rule becomes "estimate beats flag upward; flag beats task floor"). Record which won in the receipt's `source`. |
| **R6 — the extraction silently changes `_pc_lane_dirty`.** | Byte-identical move as its own commit, with `test-lane-root-not-a-worktree.sh` + `test-lane-close-loop.sh` green before any behaviour commit lands on top. |

## Out of scope for the implementing agent

- Any in-worker PreToolUse write-root deny hook (D1 step 3 exports the env var only).
- Changing `leadv2-turncap-checkpoint-commit.sh` semantics or widening what it commits.
- The fanout path (`leadv2-fanout*.sh`) — dormant under single-lead mode, and it inherits the D2 fix for free because it already calls `write-terminal`.
- Router/arbiter arm selection, quota ladders, `leadv2-lane-worktree.sh` creation semantics.
- New terminal vocabulary: `landed | pass_unlanded | refused | parked | dead` is sufficient.
- Any change to consuming repos, `.mcp.json`, or `docs/tasks.yaml` — plugin single source only.

DELIVERABLE_COMPLETE
