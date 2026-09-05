# PREPASS-PROVIDER-FALLBACK-01

Repair the mandatory architect-prepass admission path in `plugins/leadv2/scripts/leadv2-dispatch-code.sh` without disabling the design gate.

Live evidence from dispatches 17309830 and 321ade3a: both Opus and Sonnet architect runs wrote stream-json ending in `error: authentication_failed`, text `OAuth session expired and could not be refreshed`, then the dispatcher exposed only `failed_rc_1`, parked the tasks, and left root-Codex PID 99921 registered as two active Standard lanes. No worker launched.

Required behavior:
1. Parse and surface the real architect launcher failure class from its stream/handoff evidence; never reduce authentication failure to opaque `failed_rc_1`.
2. Make mandatory architect prepass use a provider-aware fallback from existing configured arms when the selected architect provider is unavailable. Reuse existing Codex/GLM/Claude launchers and canonical router/quota/lockout data; do not call raw provider CLIs.
3. Preserve the normal design artifact contract (`architect-prepass.md`, acceptance block, LANE_WRITES), retries, cache, and refusal semantics. A fallback design must be read and validated exactly like a Claude design.
4. A parked/not-dispatched prepass must not leave the caller/root PID consuming an active worker slot.
5. Journal selected architect arm, fallback reason, underlying failure class, and whether a worker was actually launched.
6. Preserve explicit rollback/env seams and existing successful Claude behavior.
7. Use existing tests where possible and run targeted prepass, dispatch-ledger, active-registry, Codex launcher, and GLM launcher suites. Do not edit tests in this lane.

Non-goals: do not disable architect prepass, weaken acceptance/writes checks, change root model, or edit lifecycle plugin hooks.

acceptance:
  surface: log_line
  observable: With Claude OAuth unavailable, a multi-file product dispatch logs the Claude authentication failure, selects an available configured architect arm, validates its design, and launches the worker without leaving a fake active lane; when no architect arm is available it parks and frees capacity.
  authored_at: 2026-08-24T18:35:00Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh
