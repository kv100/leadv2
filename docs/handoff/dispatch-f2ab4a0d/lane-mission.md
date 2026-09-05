# THROWAWAY-PRA01-PROBE — PLUGIN-REVIEW-ARMS-01 evidence lane

Create exactly one new file: `docs/missions/THROWAWAY-PRA01-PROBE.md`, containing a single
H1 heading `# THROWAWAY-PRA01-PROBE` and one body line:

    Throwaway lane dispatched to prove the plugin repo's review pool resolves a
    non-author reviewer (PLUGIN-REVIEW-ARMS-01 evidence).

No other changes. This lane is throwaway evidence for PLUGIN-REVIEW-ARMS-01; finish after
the file exists so the close gate can seat a reviewer and produce a verdict.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-f2ab4a0d" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.