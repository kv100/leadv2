# MISSION — CODEX-DOOR-DEAD-01 (the provider is healthy; both leadv2 codex doors produce nothing)

Ledger row: `SD-CODEX-DISPATCH-DOOR-DEAD-01` in the persona-engine repo. Codex is currently locked
out for 6h, which is a stopgap, not a fix — it costs us the whole codex arm on every lane.

## The evidence

On 2026-08-16, in `persona-engine`:

- **Dispatch door.** Four lanes (`8c576a71`, `3063f046`, `f7f1c2c8`, `b2714233`) were routed to codex
  and wrote **zero bytes** — no `developer.stream.jsonl`, no file touched in the lane worktree — while
  `leadv2-dispatch-product-close` polled `waiting_worker` for 20+ minutes each. A fifth
  (`4b7593fe`) ended `blocked / worker_timeout`.
- **Review arm.** `ee807b33` returned `blocked / reason=review_body_lost, arm=codex` **twice**. The
  same diff reviewed on opus produced a full report immediately.
- **The provider is fine.** `codex-task.sh task --background --write --effort medium "reply with
  exactly: OK"` from the same repo, same shell environment, returned `OK` in ~60s. Quota is healthy:
  `leadv2-quota-live.sh codex` reads `used_percent: 27`.

So the fault is between `leadv2-dispatch-code.sh` / `leadv2-review-run.sh` and a codex process that
demonstrably works when invoked directly.

## What to find

Why a codex worker spawned through the dispatch door produces no output, and why the codex review arm
loses its report body. They may be one fault or two — do not assume.

Start from the difference that matters: what the dispatcher's codex branch does that a direct
`codex-task.sh task` invocation does not. Working directory, environment, the guard armed at spawn
(`codex-guard.sh`), the quota-watch, stdin handling (`< /dev/null` is a known requirement in this
repo), how the handle is polled, and where the body is expected to land versus where codex writes it.

Reproduce it before proposing anything. A hypothesis from reading the spawn path is not a diagnosis —
this repo's own rule is that code-reading makes hypotheses and runtime confirms them.

## Second, smaller finding to fix while you are here

`record-quota-lockout` cannot express "this provider is broken, stand it down": called with
`--provider codex --hours 3` it recorded `arm_postspawn_verdict … quota=no` and left an **expired**
lockout file untouched, so the router picked codex again minutes later. The lockout had to be written
by hand. There should be a supported way to stand a provider down for a duration, distinct from
"out of quota".

## Hard constraints
- **Never `reset --hard`, `clean`, or `stash`** in this tree — it is shared with three live repos and
  other sessions edit it concurrently. Re-`git diff` immediately before you `git add`.
- Do not touch `docs/leadv2/open-threads.md`.

## Deliverable
`docs/handoff/CODEX-DOOR-DEAD-01/report.md`: the reproduction, the mechanism, the fix (or, if the fix
is large, the mechanism plus the smallest safe mitigation), and the lockout-duration support.
End with DELIVERABLE_COMPLETE.
