# MISSION — FORK-RUNS-A-SESSION-01, fix round 1

Resume the same worktree (`810129d0`). Review: `docs/handoff/dispatch-810129d0/review-codex.md`,
status **fail**, 0 critical, 3 high. Two of them are exactly the failure modes the brief told you to
establish honestly rather than paper over.

## H1 — the fallback destroys lane isolation (`scripts/leadv2-fork-session.sh:99-103`)

When the isolated path is unavailable the code falls back to a shared working tree. A fork running in
the shared checkout can have its edits overwritten by a concurrent lead, or overwrite theirs — the
2026-07-28 incident in this very tree. **A fork that cannot get isolation must refuse, loudly, not
degrade.** Make the fallback an explicit failure with a reason.

## H2 — Gate 1 retries discard the pending question (`:160`)

The gate asks the founder, and a retry throws the pending question away — so an answer can land
against a question that no longer exists, or the fork proceeds having effectively asked nothing. A
gate that can lose the founder's answer is worse than no gate: it manufactures consent.
Preserve the pending question across retries, and make an unanswered gate block rather than pass.

## H3

Read it in the report and fix it, or say plainly why it does not hold.

## Keep the honest part of your result

The brief asked which phases a fork can own and which it must hand back. Keep that answer, and let
these fixes narrow it if that is the truth — "a fork owns Phases 0–5 and hands back at deploy" is a
good result. Do not widen the claim to cover the phases you just had to fence off.

## Hard constraints
- Never `reset --hard`, `clean`, or `stash` — three live repos share this tree.
- Do not touch `docs/leadv2/open-threads.md`.
- Do not weaken a gate to make the fork's path shorter.

## Deliverable
The refusal-instead-of-degrade fallback, the preserved gate question, H3, and the report updated to
match what the code now does. End with DELIVERABLE_COMPLETE.
