# CODEX-TRANSPORT-DIES-ROOT-CAUSE-01 — diagnosis lane, not a fix lane

Repo: ~/Projects/leadv2 (SHARED TREE — never `git add -A`, never `reset --hard`, never `clean`,
never `stash`, never push to origin.) **Deliverable is a report, plus at most a minimal reproducer
script. Do NOT ship a behaviour change from this lane** — the fix belongs to a follow-up once the
mechanism is proven.

**COMMIT AFTER EVERY STEP.** Five workers died on this machine on 2026-09-06, every one after
writing real work and before committing it. Commit findings as you get them, even partial.

## The question

Codex worker jobs die with `cause=transport_gone_app_server_absent` — five times on the night of
2026-09-05→06. Every death costs a lane its arm. **Why does the transport die?**

## What is already known — start from this, do not re-derive it

- **The 2026-09-01 diagnosis said "the vendor SessionEnd hook tears down a SHARED broker, so one
  codex session ending kills the others". That diagnosis is at least incomplete.** Measured
  2026-09-06: `~/.claude/plugins/data/codex-openai-codex/state/*/broker.json` holds **361** files,
  each keyed to its OWN temp cwd (`/var/folders/.../T/cxc-XXXXXX`). Brokers are already isolated
  per job. So a shared-broker story does not by itself explain the deaths. Re-derive; assume
  nothing from that note beyond this correction.
- The vendor hook is
  `~/.claude/plugins/cache/openai-codex/codex/1.0.4/scripts/session-lifecycle-hook.mjs`.
  `handleSessionEnd(input)` takes `input.cwd`, then `loadBrokerSession(cwd)` →
  `sendBrokerShutdown(brokerEndpoint)` → `teardownBrokerSession({..., killProcess:
  terminateProcessTree})` → `clearBrokerSession(cwd)`. **There is no env kill-switch** — checked.
- The arm's own layer labels the death correctly; the mislabelling downstream is a SEPARATE lane
  (`CODEX-REFUSAL-MARKER-CARRIES-ITS-CAUSE-01`) already dispatched. Do not touch that code path.
- The quota ceiling is NOT the cause: the arm was at `codex 9% < 95%` in the same window.

## Hypotheses worth testing (not a closed list)

1. `input.cwd` at SessionEnd does not match the cwd the broker was registered under, so a teardown
   hits the wrong entry — or `terminateProcessTree` walks up into a shared ancestor.
2. The 361 stale `broker.json` files are themselves the symptom: brokers that were never torn down,
   with endpoints that go dead while the file persists, so a later `loadBrokerSession` returns a
   corpse and the job "reconnects" to nothing.
3. Temp-dir reaping: `/var/folders/.../T/cxc-*` is macOS-managed temp. If the OS or a cleaner
   removes the cwd, the broker's socket/endpoint disappears under a live job.
4. Something in OUR layer ends a session while a sibling job is mid-flight — check whether we ever
   run codex jobs whose cwd is nested, or whose process tree shares an ancestor.

## Method

Boundary-counts to the first zero, not theory-hopping. For each death you can find in the journals
and dispatch ledger, establish: when was the broker registered, was its endpoint alive at spawn,
did its cwd still exist at death, and which process actually sent the shutdown. Timestamps from
disk (`stat`), not from inference.

Anti-false-zero discipline, which cost this project seventeen wrong answers in one night:
- `rc=0` means nothing; `rc=$?` after a pipe reads the LAST stage's status.
- Never let `head` truncate a listing you are about to call complete.
- Quote glob pathspecs — unquoted, zsh expands them against the filesystem and a census silently
  reports zero.
- Derive every zero a second way before believing it.

## Deliverable

`docs/handoff/CODEX-TRANSPORT-DIES-ROOT-CAUSE-01/report.md`, under 100 lines:

1. The mechanism, stated as a chain of facts each with the command that shows it. If you cannot
   prove the mechanism, say so plainly and report what you eliminated and how — a ruled-out
   hypothesis with evidence is a real deliverable here.
2. Whether the 361 stale broker files are cause, symptom, or noise — with the evidence.
3. A minimal reproducer if you find one (a script under `docs/handoff/.../repro.sh`).
4. The proposed fix in one paragraph, NOT implemented, with its one-step rollback.
5. Explicitly: what the 2026-09-01 note got right and what it got wrong.
