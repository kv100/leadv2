# critic — armfix.diff (SD-GLM-FLASH-ARM-DEAD-CHAIN-DECORATIVE-01), round 1 exhaustive

REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=0 high=4 medium=4 low=3

FINDING: severity=High file=plugins/leadv2/scripts/leadv2-dispatch-product-close.sh line=861 dimension=correctness desc=Census miss — the quota-advance caller of _pc_arm_advance never sets _PC_CONTINUATION_HANDED_OFF, so a successful continuation there is still terminalized by the old close owner (the exact defect-2 shape this diff claims to close).
FINDING: severity=High file=plugins/leadv2/scripts/leadv2-dispatch-code.sh line=4631 dimension=correctness desc=`_glm_model="glm-4.7"` is an unverified external model id (no routing.yaml row, no wrapper support, appears nowhere else in the repo) and the hunk is out of scope for this task.
FINDING: severity=High file=docs/handoff/SD-GLM-FLASH-ARM-DEAD-CHAIN-DECORATIVE-01/fix.md line=3 dimension=correctness desc=Root-cause claim "all four preserved GLM runs completed with exit 0 after 80-188s" is an untagged evidence-free provider-runtime claim that drives the entire fix; no run dir, meta.yaml excerpt, or probe output is cited.
FINDING: severity=High file=plugins/leadv2/scripts/leadv2-dispatch-code.sh line=7371 dimension=correctness desc=The continuation loop breaks on spawn rc=0 even when no handle= line was parsed, then reports arm_advance_exhausted attempts=none and exits 4 — the old close owner terminalizes the lane while a worker may be live.

---

## Scope read

- Diff: `docs/handoff/SD-GLM-FLASH-ARM-DEAD-CHAIN-DECORATIVE-01/armfix.diff` (290 lines, 2 files).
- Live source read: `plugins/leadv2/scripts/leadv2-dispatch-code.sh` (1506-1550, 2085-2094, 3872-3925, 4489-4530, 4610-4642, 4922-4940, 5000-5060, 7234-7385), `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` (116-300, 840-875, 992-1095, 1651-1700, 2505-2530, 2805-2835), `plugins/leadv2/scripts/leadv2-burn-governor.sh` (137, 207), `plugins/leadv2/scripts/glm-coder.sh` (101, 104, 352-354).
- Deliverable read: `fix.md`.

The diff's two stated intents are individually sound: aliasing `glm-flash` onto the `glm` provider adapters is the right shape (verified — `_spawn_worker_body` already routes both through `glm-coder.sh` with `GLM_MODEL` as the seam, `leadv2-dispatch-code.sh:4617-4627`), and deferring the write-once terminal until the chain is genuinely exhausted is the right fix for the decorative second spawn. The failures below are in the completeness of both.

---

## Lens 1 — correctness

### H1. `_pc_maybe_quota_advance` advances the chain and the old owner still terminalizes it
`leadv2-dispatch-product-close.sh:851-862`

`_pc_arm_advance` has **two** callers:

```
861:  _pc_arm_advance                    # inside _pc_maybe_quota_advance
2523: if _pc_arm_advance; then ...       # silent-arm branch (patched)
```

Only the second was patched. The first ignores the return value and never sets
`_PC_CONTINUATION_HANDED_OFF`. Its call sites:

```
1026:  [[ "${status}" == failed && "${registry_alive}" == 0 ]] && _pc_maybe_quota_advance "${AUTHOR}" "${HANDLE}"
1090:  (identical, second poll branch)
1029-1032:  if [[ ( "${status}" == complete || "${status}" == failed ) && "${registry_alive}" == 0 ]]; then
              _pc_reap_worker ...; return 1     # "worker is provably finished"
```

On a quota-shaped death the sequence is: advance succeeds → a successor worker **and** a
successor close owner exist → `pc_worker_alive` returns 1 → the old owner walks on to its own
terminal path. If `pc_silent_arm_probe` happens to be true it is now rescued by the new
`status=advanced` marker (returns 0 → flag set → `exit 5`), but if the dead worker left any diff
at all the probe is false and the old owner proceeds into the review/terminal path with
`_PC_CONTINUATION_HANDED_OFF=0`: it writes the write-once terminal and calls
`leadv2_tasks_unclaim` on a lane a live successor owns. That is defect 2, verbatim, on the
second caller.

Fix shape: set the flag inside `_pc_arm_advance`'s own success branch (single source), or make
`_pc_maybe_quota_advance` propagate — `if _pc_arm_advance; then _PC_CONTINUATION_HANDED_OFF=1;
exit 5; fi`.

### H4. `break` on rc=0 with an empty handle
`leadv2-dispatch-code.sh:7365-7379`

```
    spawn_out="$(spawn_worker "${candidate}" "${mission}" "${sig8}")"; src=$?
    if [[ ${src} -eq 0 ]]; then
      arm="${candidate}"
      handle="$(printf '%s\n' "${spawn_out}" | sed -n 's/.*handle=\(.*\)$/\1/p' | tail -1)"
      break
    fi
```

`break` fires on rc=0 regardless of whether a `handle=` line was parsed. An rc=0 / empty-handle
spawn is not hypothetical — this script's own header comment at line 81 records it happening:
"emitted `worker_spawned` with an EMPTY handle and consumed the reservation". Such a spawn then
falls to `[[ -z "${handle}" ]]` and exits 4 with `attempts=none`, because `attempted_csv` was
never appended (the loop broke rather than continued). Consequences: the journal claims nothing
was attempted, the remaining chain is abandoned without being walked, and `_pc_arm_advance`
returns 1 so the old close owner writes `no_work` while the just-spawned worker may be running.
Guard the break on `[[ -n "${handle}" ]]`, and count rc=0-with-no-handle as an attempt.

### M1. The continuation overrides the successor's chain with a possibly single-element CSV
`leadv2-dispatch-code.sh:7387`

```
spawn_product_close "${sig8}" "${arm}" "${handle}" "$(IFS=,; printf '%s' "${candidate_arms[*]}")" ...
```

Param 4 becomes `LEADV2_DISPATCH_CANDIDATE_ARMS` in the child (`spawn_product_close`,
`leadv2-dispatch-code.sh:4493,4512`). Previously `""` was passed and the child's
`_pc_arm_advance` fell back to deriving the chain from the journal's
`candidate_chain task=<sig8> arms=` line — the full ladder. Now the child gets whatever this
process computed. In the normal case that is a suffix and `_pc_next_arm_in_chain` yields the same
answer. But the new fallback

```
    else
      candidate_arms=("${arm}")
    fi
```

produces a **one-element** CSV whenever `_adv_remaining` is empty — i.e. `_advance_remaining_chain`
returned rc1 because the passed arm is not in the recorded chain, which is exactly what happens
after the arbiter re-picked an arm on a previous hop (`_advance_remaining_chain`,
`dispatch-code.sh:7234-7251`, requires an exact token match). The successor close owner then sees
a chain containing only itself, `_pc_next_arm_in_chain` returns nothing, and it emits
`chain_exhausted` and terminalizes — a chain truncation introduced by the fix that is meant to
prevent premature exhaustion. Pass `""` in that fallback case, or re-derive the full chain
before handing it down.

### M4. `DC_KIND` does not survive into `advance-arm`
`leadv2-dispatch-code.sh:4628`

`DC_KIND` is `export`ed at `:6401` inside the dispatch path, so the new `audit → glm-4.7` branch
does fire on an initial dispatch. But `advance-arm` is a **fresh process**, invoked by
product-close (`leadv2-dispatch-product-close.sh:1690`) with no `DC_KIND` in its environment and
no `--kind` flag on `cmd_advance_arm`'s parser (`:7256-7265`). An audit lane that advances an arm
therefore silently drops back to the wrapper default model. Thread the kind through advance-arm,
or resolve it from the confirmed ledger row the way `_adv_class` already is (`:7292-7297`).

---

## Lens 2 — tests-can-fail (falsification)

### M3. The diff ships no test, and the one test covering the new production line is outside it
- `fix.md` names `plugins/leadv2/scripts/tests/test-arm-advance-real.sh` as an **untracked**
  126-line harness. It is not in the diff, so it is not what is being reviewed, and CI cannot
  select it. Per this repo's own harness doctrine, a suite CI never runs is worth nothing.
- The only assertion touching the new `glm-4.7` line lives in
  `plugins/leadv2/scripts/tests/test-glm-flash-arm.sh:322-325`, also **not in this diff**:
  ```
  if grep -q '^GLM_MODEL=glm-4.7$' "${RECORD}" 2>/dev/null; then
  ```
  That asserts the dispatcher wrote the env var it was just told to write. It cannot fail if
  `glm-4.7` is not a model the provider accepts — the assertion is about our own string, not the
  external contract it encodes. Tautological with respect to the risk it appears to cover.
- No declared negative control for either defect. The `fix.md` "forced-empty arm-1 proof" shows
  two `worker_spawned` lines and asserts no `dispatch_terminal` at the second spawn. That
  exercises only the silent-arm path (`:2523`). It **cannot** fail for H1, because H1's path
  (`status=failed` + `registry_alive=0` → `_pc_maybe_quota_advance`) is never entered by a
  forced-*empty* arm. The proof is real but scoped narrower than the claim it is offered for.

---

## Lens 3 — product-invariant / contract

### M2. `review-gate.md` still says `status: blocked` on a successful continuation
`leadv2-dispatch-product-close.sh:2508-2527`

The block above the patched lines writes `review-gate.md` with `status: blocked` /
`reason: arm_produced_nothing` **before** `_pc_arm_advance` is called. The diff correctly stops
the *journal* from claiming a terminal (`action=arm_advanced` instead of `terminal=no_work`), but
the on-disk artifact the lead and the sweeps read still says blocked until the successor's own
close eventually overwrites it. During that window the two truth surfaces disagree, and the
artifact is the one a human reads. Either defer that write until the advance outcome is known, or
stamp `status: continued` / `arm: <next>` on the success path.

### Contract note (accepted, not a finding)
`exit 5` is now returned for both "blocked, terminal written" and "handed off, no terminal".
`spawn_product_close` backgrounds the close with `>/dev/null 2>&1 &` and never reads the rc
(`leadv2-dispatch-code.sh:4518-4520`), so nothing consumes the ambiguity today. Noted only because
it makes the two outcomes indistinguishable to any future synchronous caller.

---

## Lens 4 — census

Defect shape: "a `glm` branch that `glm-flash` must also match". Every remaining instance in the
two touched files:

| site | patched? | verdict |
|---|---|---|
| `dispatch-code.sh:2634` `_dispatch_worker_liveness` | yes | correct |
| `dispatch-code.sh:4977` `_arm_status_probe` | yes | correct |
| `dispatch-code.sh:5041` `_arm_exit76_signal` | yes | correct |
| `dispatch-code.sh:5060` `_arm_final_output` | yes | correct |
| `dispatch-code.sh:5016` `_arm_no_work_signal` | no | correct to skip — that case list is `kimi` only, no glm row exists |
| `dispatch-code.sh:3882` `codex\|glm) : ;;` (architect prepass fallback) | no | **L3** — `glm-flash` skipped as `no_architect_launcher`; defensible but undeclared |
| `dispatch-code.sh:3913` `glm)` (architect prepass launcher) | no | **L3** — same |
| `dispatch-code.sh:2085` `_arm_provider` | n/a | ladder-driven; correct only if the ladder registers `glm-flash` under the `glm` provider — not asserted anywhere in this diff |
| `product-close.sh:645` `_pc_run_dir_for` | yes | correct |
| `product-close.sh:682` `_pc_resume_launcher_for` | yes | correct |
| `product-close.sh:995-996` `pc_worker_alive` | yes | correct |
| `product-close.sh:2819` `elif [[ "${arm}" == glm ]]` (`run_reviewer_arm`) | no | **L3** — reviewer-arm dispatch; `glm-flash` falls through to no branch |

The second census shape — "a caller of `_pc_arm_advance` whose success must suppress the
terminal" — has two instances and only one was fixed (H1). That is the finding this section
exists to produce: the same-shape enumeration was not performed.

---

## Lens 5 — claims-without-evidence

Every external-system / external-API claim in the diff, its comments, and `fix.md`:

| claim | location | evidence | verdict |
|---|---|---|---|
| burn-governor emits `glm_daily_pct` / `glm_soft_pct` / `glm_hard_pct` | diff 1515-1517 | `leadv2-burn-governor.sh:207` prints exactly those three keys; `:137` prints them on the disabled path | **evidenced** |
| `glm-flash` runs on `glm-coder.sh` with runs under `glm-runs` | diff 68/193/216 | `leadv2-dispatch-code.sh:4617-4627` (one case row, `GLM_MODEL` seam); `glm-coder.sh:104` `GLM_MODEL="${GLM_MODEL:-glm-5.3}"` | **evidenced** |
| `glm-5.3-flash` is a valid model id | pre-existing `:4627` | `glm-coder.sh:101` comment | pre-existing, out of scope |
| **`glm-4.7` is a valid model id the provider accepts** | diff 79 / `dispatch-code.sh:4631` | none. Repo-wide grep for `glm-4` returns only this new line, a test asserting this new line, and `glm-4.5-air` (`glm-coder.sh:354,1121`). No routing.yaml row, no wrapper validation, no probe output, no doc link, no `UNVERIFIED:` tag | **H2 — BLOCKING**: untagged, evidence-free, drives a config value sent to the provider on every audit lane |
| "All four preserved GLM runs completed with exit 0 after 80-188s" | `fix.md:3` | none — no run-dir path, no `meta.yaml` excerpt, no command output | **H3 — BLOCKING**: untagged, and it is the sole basis for the "glm-flash did not die" root cause the whole diff rests on |
| "The 20s constant was `LEADV2_ARM_EARLY_VERDICT_S`" | `fix.md:3` | internal, greppable | acceptable (not an external-system claim) |
| "product-close … looked in the nonexistent `glm-flash-runs` path" | `fix.md:3` | supported by the pre-patch `_pc_run_dir_for` default branch `${_PC_RUNS_ROOT}/${author}-runs/${handle}` | **evidenced** |
| forced-empty arm-1 proof (two `worker_spawned` lines) | `fix.md:19-24` | verbatim output quoted; harness untracked and not in the diff, so unreproducible from this review | partial — see M3 |

---

## Low findings

**L1.** `emit decision "worker_spawned by=arm_advance model=${arm} handle=${handle}"` was deleted
(diff lines 155-156) with no stated reason. `spawn_worker` emits its own row
(`dispatch-code.sh:4934`, `by=router`), so no event is lost, but the provenance distinction
between a router spawn and a continuation spawn is. Repo-wide grep finds `by=arm_advance` only in
`~/.claude/leadv2-quarantine/*` snapshots, so nothing live consumes it — hence Low. If the
deletion was deliberate, say so; it reads as collateral.

**L2.** All three `burn_gate` emits now interpolate `glm_daily_pct=${glm_daily_pct}`
unconditionally (diff 25/39/52). The governor does emit the key on both its printf paths, so this
is usually populated; on any governor build/line that omits it the journal gains a bare
`glm_daily_pct=` whose value a `sed -n 's/.*glm_daily_pct=\([^ ]*\).*/\1/p'` consumer reads as the
empty string rather than absent. Cosmetic; emit the key only on the `glm_*` reason branch.

**L3.** Three residual bare-`glm` comparisons in the touched files were neither patched nor
declared out of scope — see the census table (`dispatch-code.sh:3882`, `:3913`,
`product-close.sh:2819`). None is provably broken by this diff, but "same shape, not enumerated"
is the finding.

---

## What would make this PASS

1. Set `_PC_CONTINUATION_HANDED_OFF=1` inside `_pc_arm_advance`'s success branch and have
   `_pc_maybe_quota_advance` honour it, so both callers are covered (H1).
2. Remove the `glm-4.7` hunk from this diff, or land it with a probe artifact showing the provider
   accepts that id, plus a routing.yaml row (H2).
3. Cite the four GLM run dirs / `meta.yaml` lines behind the root-cause claim, or tag it
   `UNVERIFIED:` (H3).
4. Guard the continuation `break` on a non-empty handle and count rc=0-no-handle as an attempt (H4).
5. Track the proof harness, add the `EXTRA_SUITE_MAP` row so CI selects it, and add a negative
   control for the quota-advance path specifically (M3).
6. Fix the single-element chain fallback (M1), the `review-gate.md`/journal disagreement (M2), and
   thread `DC_KIND` into `advance-arm` (M4).

DELIVERABLE_COMPLETE
