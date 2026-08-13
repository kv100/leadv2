LABEL=critic-dispatch-ONE-PATH-PLAN-RUN-01-review-1786557806 SESSION_ID=5be33a9e-fb88-4029-9e6f-01139c03e957
--- body from: docs/handoff/dispatch-ONE-PATH-PLAN-RUN-01-review/critic.full.md ---
# critic — ONE-PATH-PLAN-RUN-01 build-r2.diff (independent review, round 2)

REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=0 high=4 medium=6 low=4

FINDING: severity=High file=plugins/leadv2/scripts/leadv2-plan-run.sh line=436 dimension=correctness desc=classify_arm_failure computes refused_quota/refused_peak_hours/refused_channel_down but no branch consumes them, so a quota-refused first arm blocks the plan instead of spilling to the next :ok: arm
FINDING: severity=High file=plugins/leadv2/scripts/leadv2-plan-run.sh line=373 dimension=correctness desc=extract_plan_yaml assumes PLAN_YAML: precedes the ``` fence while the mission prompt (line 307) instructs the opposite order, so real arm output leaks post-fence prose into the YAML and the merge fails
FINDING: severity=High file=plugins/leadv2/scripts/lib/leadv2-context-merge.py line=36 dimension=correctness desc=an arm emitting a non-dict acceptance: replaces the engine-owned acceptance block wholesale, dropping acceptance.authored_at, and the merge still exits 0
FINDING: severity=High file=plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py line=511 dimension=design desc=the review-floor path (and _best_effort_floor_pool) is not filtered by DISPATCHABLE_PLAN_ARMS, so a degraded plan pool falls to haiku — an arm PLANNER-MODELS-DECISION-01 excludes from planning

Scope: only `docs/handoff/ONE-PATH-PLAN-RUN-01/build-r2.diff`. The diff is NOT applied to the
working tree (`plugins/leadv2/scripts/leadv2-plan-run.sh` does not exist on disk), so all
evidence below comes from reconstructing the new files out of the diff into `/tmp/prv/` and
running them. `bash -n` on the reconstructed engine: **SYNTAX_OK**.

---

## Critical

None.

## High

### H1 — refused_* classifications are dead code; the pool never spills (correctness)
`leadv2-plan-run.sh:436-451` (plan) and `:591-605` (diagnose).

`classify_arm_failure` returns one of `refused_channel_down` / `refused_peak_hours` /
`refused_quota` / `arm_unavailable` / `ran`. Both call sites branch on **only** `ran` and
`arm_unavailable`:

```
if   [[ "${_cls}" == "ran" ]];              then architect_arm="${_first_arm}"
elif [[ "${_cls}" == "arm_unavailable" ]];  then ...try next arm...
fi
```

Any `refused_*` verdict therefore leaves `architect_arm` empty and falls straight to
`write_gate "blocked" "provider_error"` + `exit 9` — no attempt at arm 2, and the gate reason
loses the quota/peak-hours cause.

This is exactly what the engine it claims to mirror does NOT do. `leadv2-review-run.sh:512-535`
has an explicit spill loop:

```
while :; do
  cls="$(classify_arm_failure ...)"
  [[ "${cls}" != refused_* ]] && break
  emit decision "review_gate ... status=arm_refused arm=${_slot_arm} reason=${cls}"
  next_arm="$(next_ok_arm_after "${_slot_arm}" || true)"
  ...run_reviewer_arm "${next_arm}"...
done
```

The plan engine's header comment says failure classification is "lifted from
leadv2-review-run.sh" — the classifier was lifted, the consumer was not. Net effect: the entire
`--plan-pool` mechanism is inert on the failure mode it exists for. Codex hitting its weekly
quota (rc=75) blocks Phase 2 Plan outright even with sonnet/opus `:ok:` in the pool.

**Fix:** port the `while :; do ... refused_* → next_ok_arm_after → re-dispatch ... done` loop
(with the `tried` cap) into both the plan and diagnose architect passes; emit
`status=arm_refused arm=<a> reason=<cls>`, and use `all_plan_arms_unavailable` (not
`provider_error`) when the chain is exhausted.

### H2 — extractor fence order contradicts the prompt the engine sends (correctness)
`leadv2-plan-run.sh:372-374` vs `:307` and `:303`.

The mission the engine writes instructs the arm to answer:

```
Answer with one fenced block:

```yaml
PLAN_YAML:
decisions: [...]
```

i.e. **fence first, then `PLAN_YAML:`**. The extractor assumes the reverse:

```awk
/^PLAN_YAML:/ { found=1; next }
found && /^```/ { fence++ ; if (fence==1) next; exit }
found { print }
```

With prompt-shaped output, the first fence the awk sees after `PLAN_YAML:` is the **closing**
fence, which it skips as if it were the opening one — then keeps printing to EOF. Any prose the
model emits after the block is appended to the extracted YAML.

Reproduced verbatim (`/tmp/prv`, prompt-shaped output plus one trailing sentence):

```
$ awk '...' real.out > extracted.yaml && python3 -c "import yaml;yaml.safe_load(open('extracted.yaml'))"
yaml.scanner.ScannerError: could not find expected ':'
  in "extracted.yaml", line 10, column 1     # ← "Done — I have produced the plan above."
```

`leadv2-context-merge.py:1024-1031` swallows that parse error (`except Exception: continue`),
so the arm is treated as empty → `missing required fields: decisions, off_limits, plan` →
retry → `exit 7 acceptance_invalid`. A perfectly compliant architect run fails the gate.

Every stub in the diff (`fixtures/plan-run/stub-architect.sh:1183`, and the inline stubs at
diff lines 1316, 1994, 2190, 2377) emits `PLAN_YAML:` **before** the fence — the shape the awk
wants and the prompt does not ask for. So the whole suite is green on a shape no real arm
produces. See M5.

**Fix:** make the awk order-agnostic (enter on `PLAN_YAML:`, treat the *next* `^```` as
terminal, and skip a fence line that precedes `PLAN_YAML:`), and add a fixture that emits the
literal shape the prompt specifies, including trailing prose.

### H3 — an arm can delete the engine-owned acceptance block (correctness)
`plugins/leadv2/scripts/lib/leadv2-context-merge.py:36-44`.

```python
if key == "acceptance" and isinstance(val, dict) and isinstance(result.get("acceptance"), dict):
    ...preserve authored_at...
elif key not in result or key not in ENGINE_OWNED_TOP:
    result[key] = val          # ← acceptance lands here when the arm's value is not a dict
```

`acceptance` is not in `ENGINE_OWNED_TOP`, so a non-mapping `acceptance:` from an arm (a string,
a list, a fenced blob) takes the `elif` and replaces the skeleton's block, taking
`acceptance.authored_at` with it. `check_required` only tests presence of the `acceptance` key,
so the merge exits 0. Reproduced:

```
$ python3 merge.py --skeleton skel.yaml --arm arm.yaml --out merged.yaml
merge: ok -> merged.yaml        rc=0
$ grep -A1 '^acceptance' merged.yaml
acceptance: 'surface: file_artifact, observable: a human sees it'   # authored_at gone
```

The engine header advertises this as an unconditional R1 guarantee ("Engine-owned keys (id,
mission, reads, writes, lane_writes, acceptance.authored_at) are always restored after merge").
Under defaults it fails closed (`leadv2-acceptance-shape.sh:157` raises on a str `acceptance`
→ `assert-precedence` returns 1), but with `LEADV2_REQUIRE_ACCEPTANCE=0` (`plan-run.sh:722`,
a supported flag) validation is skipped, and when no `lane_writes` file exists yet
`has_existing=0` skips precedence too — so the corrupted context.yaml is written and the gate
says `status: pass`.

**Fix:** put `acceptance` handling ahead of the generic branch unconditionally — if the arm's
`acceptance` is not a mapping, discard it; always re-stamp `acceptance.authored_at` from the
skeleton after the merge loop; add `acceptance.authored_at` to the required check.

### H4 — plan degrades to haiku, outside DISPATCHABLE_PLAN_ARMS (design)
`plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py:511-518` and `:751`.

The diff filters `order` by `DISPATCHABLE_PLAN_ARMS` when `job == "plan"` (diff line 1083), but
the two floor paths are untouched:

- `resolve_review_pool:511` — when the filtered pool yields no reviewer, `_review_floor(author,
  rank_table)` appends `<arm>:floor:degraded` unconditionally.
- `_best_effort_floor_pool:751` — same call on the resolver-crash path, now reached for
  `--plan-pool` (diff lines 1142, 1151).

`rank_table` comes from `review_rank` in `config/leadv2-routing.yaml`:
`{haiku:1, sonnet:2, opus:3, fable:4}`. The plan engine passes **no** `--author`
(`plan-run.sh:206`), so `author_rank = -inf`, `higher` = all candidates, and
`min(higher)` = **haiku** — the one ranked arm that `DISPATCHABLE_PLAN_ARMS =
{codex, sonnet, opus, fable}` deliberately excludes.

The engine then admits it: no `:ok:` entry exists, so `fanout_list=("${planner}")`
(`plan-run.sh:562`) and `claude-subsession.sh --role architect --model haiku` runs the plan.
PLANNER-MODELS-DECISION-01's stated invariant ("role decides the SET") is bypassed precisely
when every real planner arm is quota-locked — the case the decision was written for.

**Fix:** pass the job down to both floor paths and restrict `rank_table` to
`DISPATCHABLE_PLAN_ARMS` when `job == "plan"`; if the filtered table is degenerate, return
`all_plan_arms_unavailable` rather than an out-of-set arm. Add a resolver test asserting
`--plan-pool` never emits `haiku`/`glm`/`kimi` in `pool=` or `reviewer=`.

## Medium

### M1 — A4 dedup guard misses non-adjacent duplicates
`leadv2-plan-run.sh:572`. `*",${_arm},")` has no trailing `*`, so it only matches when the
accumulated list *ends* with the arm. Reproduced:

```
fanout_list=(sonnet codex sonnet)  →  "NO DUPLICATE DETECTED (guard missed it)"
```

`_engine_pool_ok_arms:270-273` gets this right (`*",${arm},"*)`). The upstream list is already
deduped, so this is defence-in-depth that does not defend. **Fix:** append the trailing `*`.

### M2 — retry-overlay is never removed and leaks into the next run
`leadv2-plan-run.sh:326-327` / `:762`. The retry path writes
`plan-arm-<suffix>.retry-overlay` into the (persistent) handoff dir and nothing ever deletes
it. A later invocation for the same task appends "RETRY: previous attempt failed validation.
Fix these issues: …" — with stale reasons from a previous run — to the *first* architect
mission. **Fix:** `rm -f` the overlay after the retry dispatch (and at engine start).

### M3 — the bounded wait kills only the wrapper subshell
`leadv2-plan-run.sh:350-362`. `kill -TERM "${job_pid}"` targets the `( run_planner_arm )`
subshell; the `bash claude-subsession.sh --wait` child survives with the inherited fd on
`plan-arm-<arm>.yaml` and can keep writing after the engine has already gated. Also, a timed-out
arm never writes its `.rc`, so `cat .rc || printf '1'` may read a **stale** rc from a previous
run of the same arm in the same handoff dir, and the run surfaces as `empty_response` rather
than a timeout. **Fix:** `rm -f` the `.rc`/`.yaml`/`.err` triple before dispatch, kill the
process group (`kill -TERM -$job_pid` after `set -m`, or have the child write its own pidfile),
and add an `arm_timeout` gate reason.

### M4 — cache signature ignores `--writes`
`leadv2-plan-run.sh:152` hashes `MISSION_TEXT` only, but `lane_writes`/`writes` in the emitted
context.yaml come from `WRITES_CSV` (`:410-417`). A second run with the same mission and a
different `--writes` takes the cache-hit branch (`:163-170`), writes `status: pass`, and hands
the lane a context.yaml scoped to the *previous* run's file set. **Fix:** fold `WRITES_CSV`,
`MODE` and `TASK_CLASS` into `MISSION_SIG`.

### M5 — no test exercises either failing path
No fixture anywhere in the diff produces `LEADV2_DISPATCH_REFUSED` / rc=75 (one grep hit in the
whole diff, inside `classify_arm_failure` itself), so H1 is untested; and every stub uses the
inverted fence order, so H2 is untested. Per the review bar, a new logic branch with no
coverage is a finding in its own right. **Fix:** two suites — a refused-arm stub asserting
spill to arm 2, and a prompt-shaped stub with trailing prose asserting a clean merge.

### M6 — diagnose mode ignores the resolver refusal
`leadv2-plan-run.sh:394`: `refusal` is parsed and then never read in the diagnose branch (the
plan branch checks it at `:428`). `resolver_missing_failclosed` in diagnose surfaces as
`all_plan_arms_unavailable`, hiding a config/deploy fault behind a quota-shaped reason.
**Fix:** hoist the `case "${refusal}"` guard above the mode split.

## Low

- `leadv2-plan-run.sh:422` — `_diag_input="${_diag_input}\nDiff paths: ${DIFF_PATHS}"` embeds a
  literal backslash-n; it is later rendered with `printf '…%s\n'`, so the arm sees `\nDiff
  paths:` inline. Use `$'\n'`.
- `leadv2-context-merge.py:42` — `elif key not in result or key not in ENGINE_OWNED_TOP:` is
  always true (the `if` above already `continue`d on every engine-owned key). Dead condition;
  delete it and use a bare `else`.
- `leadv2-context-merge.py:41` — `result["acceptance"][ak] = av` mutates the skeleton's nested
  dict in place despite the `dict(skeleton)` "copy"; harmless today, a trap for the next caller.
  Use `dict(result["acceptance"])`.
- `leadv2-plan-run.sh:255` — a missing arm binary (rc=127) classifies as `ran`; only the
  body-persistence guard saves it, and the gate reason becomes `empty_response` instead of
  `provider_error`.

## Type/lint evidence

No Python/TS type surface is claimed by this diff beyond the two Python helpers; the repo
carries no mypy config for `plugins/leadv2/scripts/lib/`. Hard evidence run instead:

```
$ bash -n /tmp/prv/plan-run.sh
SYNTAX_OK

$ bash /tmp/prv/t1.sh                       # A4 dedup guard, arms=(sonnet codex sonnet)
NO DUPLICATE DETECTED (guard missed it)

$ awk '<extract_plan_yaml>' real.out > extracted.yaml   # prompt-shaped arm output
$ python3 -c "import yaml,sys;yaml.safe_load(open('extracted.yaml'))"
could not find expected ':'
  in "extracted.yaml", line 10, column 1

$ python3 /tmp/prv/merge.py --skeleton skel.yaml --arm arm.yaml --out merged.yaml
merge: ok -> merged.yaml
rc=0
$ grep '^acceptance' merged.yaml
acceptance: 'surface: file_artifact, observable: a human sees it'     # authored_at destroyed
```

**Verdict: BLOCK (FAIL)** — 4 High, 6 Medium, 4 Low.

DELIVERABLE_COMPLETE
