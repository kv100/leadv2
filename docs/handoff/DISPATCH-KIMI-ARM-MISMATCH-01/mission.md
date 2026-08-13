# DISPATCH-KIMI-ARM-MISMATCH-01 — the resolver can pick an arm the launcher cannot run, and the dispatch dies

## What happened (live, 2026-08-05, persona-engine)

A real code dispatch was lost to this. Verbatim:

```
[leadv2-dispatch-code] arm_resolved job=build arm=kimi reason=codex_quota_gate_80pct
[leadv2-dispatch-code] ERROR: unsupported resolved dispatch arm: kimi
```

Nothing spawned. Exit 1. The only reason the work happened at all is that the lead noticed and
re-dispatched by hand.

## Root cause

`scripts/leadv2-dispatch-code.sh:2577-2583` — the fixed-order candidate-chain switch enumerates
only three arms:

```bash
case "${arm}" in
  glm)   candidate_arms=(glm kimi codex sonnet) ;;
  codex) candidate_arms=(codex sonnet) ;;
  sonnet) candidate_arms=(sonnet) ;;
  *) log_err "unsupported resolved dispatch arm: ${arm}"; exit 1 ;;
esac
```

`kimi` appears INSIDE the glm chain (as a spill target) but has no case of its own, so the moment
the resolver hands back `kimi` as the PRIMARY arm — which it does under
`reason=codex_quota_gate_80pct` — the switch falls to `*)` and hard-exits. The resolver's arm
vocabulary and the launcher's arm vocabulary have drifted apart, and the drift is silent until it
costs a dispatch.

Note the launcher DOES have a working kimi arm further down (`kimi)` spawn case at ~:1790, plus
`_apply_kimi_admission`, `_wait_kimi_verdict`, `KIMI_BIN`). So this is purely a missing branch in
the candidate-chain switch, not a missing implementation.

## The founder decision that settles which way to fix it

**Kimi was removed from the ladder by founder order on 2026-08-04** («Кими убрать — да. ГЛМ конечно
оставить»). GLM stays as primary; Kimi is the only arm removed. So the fix is NOT "teach the
launcher to run kimi" — it is "stop the resolver from ever handing back kimi", plus a guard so this
class of drift can never again silently kill a dispatch.

## What to build

1. **Remove kimi from routing as a dispatchable arm.** `config/leadv2-routing.yaml:62-65` carries
   the `kimi` arm entry (`model: moonshotai/kimi-k3-free`, `bucket: kimi`). Retire it the
   reversible way — the way this repo already retires things: mark it disabled/deprecated with a
   one-line reason and the date, rather than deleting the block, so the removal reverses with one
   edit. Whatever mechanism the file already supports for a disabled arm, use that; do not invent
   a new key shape.
2. **Remove `kimi` from the `glm)` spill chain** at :2578 so it cannot be reached as a fallback
   either. The `codex_quota_blocked` strip immediately below (:2584-2591) is the existing pattern
   for removing an arm from the chain — match its shape.
3. **Make the `*)` branch fail SAFE, not fatal.** This is the durable half of the fix and it
   matters more than the kimi specifics: any arm the resolver emits that the switch does not know
   must fall back to a working chain (`sonnet` at minimum) and emit a loud `emit decision` line
   naming the unknown arm — never `exit 1`. A resolver/launcher vocabulary mismatch must degrade
   to "dispatched on a safe arm, loudly", not to "nothing ran".
4. **Leave the kimi implementation code in place** (`kimi)` spawn case, `_apply_kimi_admission`,
   `_wait_kimi_verdict`, `KIMI_BIN`). It is unreachable once 1+2 land, and deleting it is a much
   larger diff with no benefit today. If the founder re-enables the arm, it should still work.
5. **Tests.** Add unit coverage under `tests/` matching the existing dispatch-test style:
   - resolver returns `kimi` → dispatch does NOT exit 1; it lands on a working arm and emits the
     unknown-arm decision line;
   - `arm=glm` chain no longer contains kimi;
   - `arm=codex` / `arm=sonnet` chains unchanged (regression guard).
   Prove the suite FAILS against the pre-patch file — paste both counts in the deliverable. A test
   that passes before and after proves nothing.

## Off limits

- Do not change GLM's position as primary. GLM-FIRST-01 stands.
- Do not touch the codex quota-gate thresholds or `review_arm_exclusions`.
- Do not delete the kimi launcher implementation (item 4).
- This is the plugin's single source (`~/Projects/leadv2`). Do NOT create a copy of any
  plugin-owned file inside a consuming repo.
- Stage ONLY your own files by explicit path. Never `git add -A`, never `reset --hard`, never
  `clean`, never `stash`.

## Done means

- Diff on `scripts/leadv2-dispatch-code.sh` + `config/leadv2-routing.yaml` + tests.
- Test counts before and after, pasted.
- Deliverable at `docs/handoff/DISPATCH-KIMI-ARM-MISMATCH-01/deliverable.md` with the diff summary,
  the before/after counts, and the exact one-edit rollback.
- End with DELIVERABLE_COMPLETE.
