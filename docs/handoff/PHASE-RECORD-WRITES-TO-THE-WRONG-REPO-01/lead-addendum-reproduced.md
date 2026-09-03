# LEAD ADDENDUM — both defects reproduced live, 2026-09-03. Read with `brief.md`.

Neither of these is a hypothesis any more. Both were observed while trying to resume this very
wave, and the reproduction for defect 2 is short enough to become the suite's acceptance verbatim.

## Defect 2 (`PHASE-PLAN-PROOF-IS-FILENAME-BASED-01`) — ready-made acceptance

Same file. Same bytes. Only the name differs:

```
$ leadv2-phase-record.sh record 8538ed0a plan --artifact docs/handoff/<ID>/mission.md
[leadv2-phase-record.sh] WARN: phase 'plan' for 8538ed0a recorded done but proof NOT verified — assert will refuse

$ leadv2-phase-record.sh record 8538ed0a plan --artifact docs/handoff/<ID>/brief.md
verified
```

The suite must assert exactly this pair: a real, non-empty, architect-written plan document is
rejected under one name and accepted under another, with no change to its content. After the fix,
BOTH must verify — and an empty or placeholder file must still FAIL under either name, or the
gate has been made weaker rather than content-based.

Cost of this defect, measured: it blocked the resume of all seven Wave-4 lanes
(`rc=3`, `dispatch refused: missing mandatory phases: plan,gate1`) until seven files were renamed.
The task row already recorded "two rounds overnight"; add this one.

Note for the implementer: the accepted-name allowlist today is `brief.md` / `fix-round-N.md`
(plus a `context.yaml` carrying `decisions:`, or a non-empty `architect-prepass.md`). The fix
replaces the name check with a content check — it does not extend the list of blessed names.

## Defect 1 (`PHASE-RECORD-WRITES-TO-THE-WRONG-REPO-01`) — narrower than the row says

The row reads as though `record` writes into a foreign repo generally. It does not. Measured on
the same seven lanes: with `LEADV2_PROJECT_ROOT` exported explicitly to the plugin repo in the
dispatch command, every `phases.d` landed in the CORRECT repo — checked on both sides, and
`~/Projects/persona-engine/docs/handoff/dispatch-<sig>/` was empty for all three sigs probed.

So the precise defect is: **`record` trusts an INHERITED `LEADV2_PROJECT_ROOT`, and persona-engine's
git-tracked `.claude/settings.json` exports that variable globally to every Bash subprocess in
that session regardless of cwd.** It is not "any invocation writes to the wrong repo" — it is
"an invocation that does not pin the variable inherits someone else's root and never checks".

This matters for the fix: pinning the variable at the call site is a mitigation that already
works, so the lane's job is the missing GUARD (refuse when `docs/handoff/dispatch-<sig8>/` does
not exist under the resolved root), not a change to the resolution order. The brief already
prescribes exactly that; this addendum only removes the wider claim, so the acceptance is not
written against a failure mode that does not occur.
