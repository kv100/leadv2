# GLM-EFFICIENCY-01 — wire effort + flash routing + fresh capability data for GLM

LANE_WRITES: plugins/leadv2/scripts/glm-coder.sh,plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/config/model-capability.yaml,plugins/leadv2/docs/model-effort-matrix.md,plugins/leadv2/scripts/tests/test-glm-effort-wiring.sh,tests/run-all.sh,docs/handoff/GLM-EFFICIENCY-01/
Run suites with `LEADV2_SUITE_LOCK_DISABLE=1`. Merge main FIRST (`git merge main`). Commit at the end; an
uncommitted exit is a failed round. Read `docs/handoff/GLM-EFFICIENCY-AUDIT-01/report.md` first — it is the
measured basis for this brief; do not re-derive it, extend it.

## Why
Founder (2026-09-02): "we under-use GLM". The audit found three concrete gaps:
1. `leadv2-dispatch-code.sh:5100` resolves `RESOLVED_EFFORT` per task class and DROPS it (journals
   `effort_dropped` on every GLM dispatch, tag EFFORT-IS-NOT-WIRED-01). `glm-coder.sh` has no effort/thinking
   plumbing at all. Z.AI docs: GLM-5.3 / 5.3-flash think always; `reasoning_effort` low/high/max, default max.
   So a papercut pays the same reasoning cost as a Heavy task.
2. `glm-5.3-flash` has 3× the quota weight of `glm-5.3` (Z.AI devpack pages) and is the only tier with a
   documented `low` effort, but the arm choice is cost-policy only; flash is under-selected.
3. `plugins/leadv2/config/model-capability.yaml:167` self-flags the GLM rows as GLM-5.2-era numbers.

## Do
1. **Probe first, paste artifacts** (EVIDENCE CONTRACT): how does effort reach Z.AI through Claude Code?
   Check `claude -p --help` for an effort flag (CC 2.1.257), the Z.AI devpack page for Claude Code
   (`/effort`, env vars), and the Anthropic-compat request shape (`thinking` / `reasoning_effort`). Prove with ONE
   tiny run per setting (`low` vs `max`, same 1-line prompt) that the setting changes the response — compare
   wall time and, if available, the reasoning/thinking token count in the stream or the Z.AI dashboard delta.
   If nothing observable changes, say so and stop at step 2 with UNVERIFIED — do not ship a knob that
   provably does nothing (rule: a control without an engine reader is not a control).
2. Wire `RESOLVED_EFFORT` into the GLM spawn: dispatcher passes it (env `GLM_EFFORT` or an arg), `glm-coder.sh`
   applies it to the `claude -p` invocation using the mechanism step 1 proved. Mapping by class:
   Trivial/Light → `low`, Standard → `high`, Heavy/Strategic → `max`; review/verify roles → `high`.
   Replace the `effort_dropped` journal line with `effort_applied effort=<v> mechanism=<flag|env>`.
3. Routing policy: Trivial/Light build work defaults to `glm-flash` (not `glm`); Standard/Heavy stay on
   `glm-5.3`. Keep the existing lock_busy / quota fallbacks. One place, documented in
   `docs/model-effort-matrix.md` with the Z.AI URLs from the audit.
4. Refresh the GLM rows in `model-capability.yaml` from the 5.3 / 5.3-flash pages (context 1M, out 128K,
   quota weight 1× vs 3×, thinking forced, effort levels); remove the stale-flag comment at :167 and add
   `evidence:` URLs.
5. Suite `test-glm-effort-wiring.sh`: (a) dispatcher emits `effort_applied` with the class mapping for all
   4 classes (fixture, no live spawn); (b) `glm-coder.sh` spawn_args contain the effort mechanism for
   `GLM_EFFORT=low` and omit it when unset; (c) Light → arm `glm-flash`, Standard → `glm`. Mutation negative
   control, RUN and paste red: drop the effort pass-through → (a)+(b) red. Revert. Register in
   `tests/run-all.sh` EXTRA_SUITE_MAP; run `tests/run-all.sh --scope changed`, paste the selected-suite line.
6. `report.md` under `docs/handoff/GLM-EFFICIENCY-01/`: probe artifacts, mapping table, suite output, what
   remains UNVERIFIED (cache on api/anthropic is out of scope — dashboard only).

## Do NOT
- Do not touch quota gating thresholds, the lock, or Sonnet/Codex routing.
- Do not use any GLM model other than `glm-5.3` / `glm-5.3-flash` (GLM-47-BAN-01).
- No `[1m]` / auto-compact trial in this lane (separate follow-up).
