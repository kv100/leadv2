# BOARD-BLIND-TO-DETACHED-WORKERS-01 — the status board reports "no live lanes" while a worker runs

**This is canonical. The fix lands here and applies to persona-engine, m3-market and
respiro-ios at once. The founder approved editing shared on 2026-08-29 (option A).** That raises
the bar on evidence; it does not lower it.

## Observed, three times, with proof

`docs/leadv2/founder-status.md` in persona-engine printed
`⚠ ДОСКА ПУСТА — ничего не выполняется` / `(живых линий нет)` at 00:19Z, 00:33Z and 00:49Z on
2026-08-29 while a worker was genuinely running and later returned a real review PASS.

- codex lane `dispatch-ef95d34a`: journal shows `product_close ... author=codex
  handle=task-mtdmkbgy-xtd2rd waited=307s`, then `waited=612s`. Board: empty.
- glm lane `dispatch-ab0ec014`: journal shows `product_close ... author=glm
  handle=260829-034420-ab0ec014-7c43 waited=302s`. Board: empty.

**Both arms, not just codex.** Any conclusion that scopes this to codex alone is wrong.

## Mechanism as far as the lead traced it — verify before building on it

1. The board renders from `leadv2-status-render.sh` ← `docs/leadv2/status-snapshot.json` ←
   `leadv2-lanes-snapshot.sh --json`, whose live-lane source is `docs/leadv2/active.yaml`.
2. The dispatcher registers its lane row pre-spawn with the LEAD's pid
   (`pid_role=lead_durable`), then on exit its trap runs the compare-and-delete at
   `plugins/leadv2/scripts/leadv2-dispatch-code.sh:3975-4043`, journalled
   `active_lane_released ... where=exit_trap`.
3. That delete **refuses to remove a row whose `pid_role == "worker"`** (:4012). So the design is
   already correct — provided the row was promoted to a worker row.
4. Promotion happens via `leadv2_active_set_worker_pid`
   (`plugins/leadv2/scripts/leadv2-active-registry.sh:457-469`), which sets `pid_role="worker"`
   only when it receives a positive integer pid. The dispatcher calls it at
   `leadv2-dispatch-code.sh:4834-4838`.

**Hypothesis to confirm or refute first, with a file:line:** for a DETACHED worker the pid handed
to `set_worker_pid` is absent, zero, or belongs to a launcher that has already exited — so
`pid_role` never becomes `worker`, and the exit trap deletes a row whose work is still running.
Check the `codex)` arm branch specifically (it begins just after :4844 and hands off to
`codex-task.sh`, which yields a HANDLE, not a pid), and confirm what the glm branch actually
passes.

If the real mechanism turns out to be different, **follow the code, not this document**, and say
so plainly in your report.

## The fix, in one sentence

A lane row must survive the dispatcher's exit for exactly as long as its worker is really
running — including workers that have no local pid, only a handle.

Prefer the narrowest change that achieves that. Do not redesign the registry.

## Prove it — the deliverable is the test, not the diff

1. **A test that fails on today's code and passes on yours.** It must simulate a detached spawn
   (no surviving local pid, handle only), run the exit-trap release path, and assert the lane row
   is STILL in `active.yaml` afterwards and that a snapshot renders it as live. Paste the red run
   and the green run.
2. **A second assertion in the same file for the opposite direction:** a lane whose worker is
   genuinely finished must still be releasable, so this fix cannot leak dead rows onto the board
   forever. Both directions in one file.
3. The repo's own suite green — state exactly which command you ran.
4. `git diff --stat`.

## Constraints

- Do not touch `leadv2-status-render.sh` or the renderer. The board reports its source
  faithfully; the source is what is wrong.
- Do not widen the compare-and-delete's ownership checks. They exist to stop one dispatcher
  deleting another's row.
- No new dependency, no new registry file.

Report to `docs/handoff/dispatch-<task>/developer.md`.
