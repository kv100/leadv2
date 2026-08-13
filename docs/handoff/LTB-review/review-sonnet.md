LABEL=critic-dispatch-LANE-TRUTH-BATCH-01-review-1786569831 SESSION_ID=409aff79-429e-4ec9-9b19-3de6ccbb23da
--- body from: docs/handoff/dispatch-LANE-TRUTH-BATCH-01-review/critic.full.md ---
verdict: REVISE
next_action: review_round_2

REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=0 high=4 medium=1 low=0

FINDING: severity=High file=plugins/leadv2/scripts/lib/leadv2-context-merge.py line=36 dimension=correctness desc=deep_merge only protects acceptance.authored_at when both skeleton.acceptance and arm.acceptance are dicts; if skeleton has no pre-existing acceptance dict (or it's not a dict) the elif branch does `result["acceptance"] = val` wholesale, letting an arm-authored acceptance.authored_at silently overwrite the engine-owned timestamp
FINDING: severity=High file=plugins/leadv2/scripts/leadv2-plan-run.sh line=439 dimension=correctness desc=classify_arm_failure/next_ok_arm_after is only invoked once per pass (first arm -> one fallback arm); if the fallback also returns refused_quota/refused_peak_hours/refused_channel_down the run gives up even though further pool arms remain, so quota pressure on 2 arms blocks a plan that a 3rd/4th arm could still service
FINDING: severity=High file=plugins/leadv2/scripts/leadv2-plan-run.sh line=367 dimension=correctness desc=extract_plan_yaml's fence-skip awk has no bound if the arm's response never emits a second/closing ``` fence (e.g. the critic-revision prompt at ~line 3125 only asks for "PLAN_FINDING lines then a revised PLAN_YAML block", no explicit fence instruction) — trailing prose after the intended YAML gets swallowed into the "extracted" text and can break yaml.safe_load downstream
FINDING: severity=High file=plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py line=763 dimension=correctness desc=_best_effort_floor_pool (the emergency floor used by every --plan-pool degraded/exception path, wired in at line 871/888) calls _review_floor() with no DISPATCHABLE_PLAN_ARMS filter, so on a resolver crash the "floor" planner arm can be glm/kimi/haiku — arms PLANNER-MODELS-DECISION-01 explicitly bans from planning roles
FINDING: severity=Medium file=plugins/leadv2/hooks/leadv2-continuation-guard.sh line=262 dimension=design desc=CONTINUATION_RE matches bare English words "pending" and "waiting on" (in addition to the intended explicit phrases) as a continuation exemption; any ordinary final sentence that happens to contain "pending" or "waiting on" silently defeats the guard the hook exists to enforce

## Detail

### 1. leadv2-context-merge.py:36 — acceptance-shape bypass (High, correctness)

```python
if key == "acceptance" and isinstance(val, dict) and isinstance(result.get("acceptance"), dict):
    for ak, av in val.items():
        if ak in ENGINE_OWNED_ACCEPTANCE:
            continue
        result["acceptance"][ak] = av
elif key not in result or key not in ENGINE_OWNED_TOP:
    result[key] = val
```

The `authored_at` protection only fires inside the first branch, which requires
`result.get("acceptance")` to already be a dict. The module's own docstring
promises "a model cannot overwrite... acceptance.authored_at" unconditionally
(design §3.2.5, R1 mitigation) — that promise only holds if the engine-written
skeleton always pre-populates a dict-shaped `acceptance` key before the first
`deep_merge` call. There is no assertion or guard in this file enforcing that
precondition; if the skeleton is missing/malformed at that key for any reason
(a caller bug, a corrupted `.tmp` skeleton write, a future skeleton-writer
change), the `elif` branch replaces `result["acceptance"]` outright with the
arm's dict, including whatever `authored_at` the arm chose to emit — the exact
scenario `docs/handoff/one-path-plan-run-01/followups.md` item 3 flags as
unresolved ("reject non-dict acceptance: nonzero exit; preserve
acceptance.authored_at"). No test in this diff exercises a non-dict/missing
`acceptance` skeleton input, so the gap is untested as well as unfixed.

Required fix: validate `isinstance(result.get("acceptance"), dict)` up front
(hard-fail with nonzero exit + stderr reason if not, per the followup), don't
fall through to a silent full-dict overwrite.

### 2. leadv2-plan-run.sh:439/593 — single-retry-only pool spill (High, correctness)

```bash
_cls="$(classify_arm_failure "${_first_rc}" "${_first_err}" "${_first_out}")"
...
_next_arm="$(next_ok_arm_after "${_first_arm}" || true)"
...
_cls2="$(classify_arm_failure "${_next_rc}" "${_next_err}" "${_next_out}")"
if [[ "${_cls2}" == "ran" ]]; then
  ...
```

`classify_arm_failure` can return `refused_quota`, `refused_peak_hours`, or
`refused_channel_down` for either the first or the second (fallback) arm, but
there is no loop — `_cls2` is checked once against `"ran"` and, if it isn't,
the code falls through to a blocked/parked terminal state rather than calling
`next_ok_arm_after` again. `resolve_plan_pool_call()` can return a pool with
3-4 arms (codex/sonnet/opus/fable), so a quota refusal on arm #1 followed by a
peak-hours refusal on arm #2 abandons the plan even when arm #3/#4 in the
resolved pool are still eligible. `followups.md` item 1 names this exact gap
("consume refused_quota/refused_peak_hours/refused_channel_down, spill to next
:ok: arm") and it is still unaddressed in this diff.

### 3. leadv2-plan-run.sh:367 — unbounded fence extraction (High, correctness)

```bash
extracted="$(awk '
  /^PLAN_YAML:/ { found=1; next }
  found && /^```/ { fence++ ; if (fence==1) next; exit }
  found { print }
' "$f" 2>/dev/null)"
```

This assumes exactly one closing fence appears after `PLAN_YAML:` and nothing
prints past it. That holds for the plan/diagnose architect prompts (lines
~2730/2734 in the reviewed diff), which explicitly wrap the block in
` ```yaml ... ``` `. It does not hold for the critic-revision prompt
(~line 3125: "Emit PLAN_FINDING: lines... then a revised PLAN_YAML block"),
which does not instruct a closing fence. If the critic model appends any
commentary after the YAML (very common LLM behavior — trailing summary
sentences, disclaimers), `found` stays true with no fence match, and every
line through EOF — including the trailing prose — is captured into the
"extracted" YAML fed to `yaml.safe_load` in `leadv2-context-merge.py`, which
either throws or silently absorbs garbage as YAML content. `followups.md`
item 2 names this exact function/line as unresolved.

### 4. leadv2-glm-policy-resolve.py:763 — unfiltered emergency floor (High, correctness)

```python
arm, ok = _review_floor(author, rank_table)
```

`_best_effort_floor_pool` is the fail-safe used by every `--plan-pool`
degraded path (both the in-`_main` `except Exception` at line 871 and the
top-level `__main__` handler at line 888), by design so "a resolver crash
anywhere... still leaves the review gate with a non-empty pool where
possible." But `_review_floor` derives its candidate purely from
`review_rank` in the routing ladder — it has no knowledge of
`DISPATCHABLE_PLAN_ARMS = {"codex", "sonnet", "opus", "fable"}` introduced in
this same diff for `PLANNER-MODELS-DECISION-01` ("glm and kimi are build-only
and are never admitted to a planning role"). On a resolver crash during a
`--plan-pool` call, the floor arm returned can be glm, kimi, or haiku,
violating the invariant this diff's own comments assert two lines away.
`followups.md` item 4 names this exact function/line as unresolved.

### 5. leadv2-continuation-guard.sh:262 — over-broad exemption regex (Medium, design)

```python
CONTINUATION_RE = re.compile(
    r'(?:работа\s+продолжается|задача\s+закрыта|continuing|task\s+closed'
    r'|pending|waiting\s+on|DELIVERABLE_COMPLETE|NOT-COMMITTED)',
    re.I | re.UNICODE)
```

The hook's entire purpose (per its header comment) is to catch a turn that
went silent without making progress or declaring status explicitly. Mixing
bare dictionary words ("pending", "waiting on") into the same alternation as
the deliberately-distinctive phrases means any ordinary closing sentence that
happens to contain those words — e.g. "the CI run is still pending" written
as idle color commentary, not a status declaration — satisfies
`has_continuation` and silently passes the guard. Recommend anchoring these
two alternatives to the intended status-line shape (e.g. requiring them at
start-of-line or paired with a colon), matching the specificity of the other
four phrases in the same regex.

## Non-blocking observations (not filed as findings)

- `leadv2-dispatch-code.sh` cmd_resolve (~line 3086) adds a second `set +e`
  after a second `source` of `leadv2-active-registry.sh`. This mirrors the
  existing SILENT-DEATH-01 pattern at line 367 and is consistent with prior
  precedent in this file — not flagged as a new defect, but worth confirming
  no code path between the two `source` calls needs `-e` semantics before the
  founder signs off on the pattern being repeated a second time in the same
  script.
- `leadv2-dispatch-product-close.sh` calls `_pc_reap_worker
  "$(_pc_run_dir_for ...)" "$(_pc_meta_value "$(_pc_run_dir_for ...)/meta.yaml" pid)"`
  twice (lines ~1509, ~1531 in the diff) — `_pc_run_dir_for` is invoked twice
  per call site. Harmless if the function is pure/deterministic, but worth a
  local variable to avoid the double subshell cost and any risk if the
  function's inputs change under it between the two calls.

## mypy/tsc

Not applicable — this diff is entirely bash/python plugin-scripting and
markdown/yaml handoff docs (`plugins/leadv2/scripts/**`,
`plugins/leadv2/hooks/**`, `docs/handoff/**`); no TypeScript changed, and this
repo's Python here is untyped stdlib-only scripting outside any mypy-checked
package (no `mypy.ini`/`pyproject` target covers `plugins/leadv2/scripts/lib/`).
Ran `python3 -m py_compile` on the two modified/new Python files instead:

```
$ python3 -m py_compile plugins/leadv2/scripts/lib/leadv2-context-merge.py plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py
(no output — both compile clean)
```

## Scope note

This diff (`docs/handoff/LTB-review/build-r2.diff`, 6825 lines / 60 files) is
not scoped to LANE-TRUTH-BATCH-01 alone — it bundles CONTINUATION-GUARD-01,
E2E-GATE-P1-REGRESSION-01, E2E-GATE-RESIDUE-01, PLUGIN-RELIABILITY-01/02,
STATUS-SURFACE-BATCH-01, and ONE-PATH-PLAN-RUN-01 changesets together. All 4
High findings above land in the ONE-PATH-PLAN-RUN-01 slice
(`leadv2-plan-run.sh`, `leadv2-context-merge.py`,
`leadv2-glm-policy-resolve.py --plan-pool`), which per this diff's own
`docs/handoff/one-path-plan-run-01/followups.md` is explicitly NOT wired into
the live dispatch path yet (`plan.js` deletion + `leadv2-dispatch-code.sh`
swap + `phases.md` doc-flip are called out as a separate, blocking follow-up
lane). That lowers real-world blast radius today, but the findings are
correctness bugs in code that is about to become load-bearing, and 3 of the 4
are already self-documented as unresolved High in the diff's own artifacts —
they should not ship into the doc-flip lane unfixed. The Medium
(continuation-guard regex) IS live today (new hook, wired via hooks.json).

Other files in the bundle (leadv2-dispatch-code.sh, leadv2-dispatch-product-close.sh
liveness/reap logic, leadv2-active-registry.sh set_log_path, leadv2-lane-status-line-tail.sh
cache-preservation, leadv2-supervise.sh, the ~15 new/modified test suites) were read but
did not surface additional Critical/High correctness issues within this review's effort
budget; a deeper pass on leadv2-supervise.sh and leadv2-plugin-sync.sh specifically was
not completed given the diff's size.

DELIVERABLE_COMPLETE
