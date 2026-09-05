GUARD-AUDIT-FINDINGS-NEVER-REACHED-THE-CODE-01 — twenty-three guard/audit handoffs exist. Nobody
has checked whether their findings were applied. Check, one finding at a time, against the tree.

FOUNDER, 2026-09-04: "не уверен что аудиты хуков/гардов сделаны и выводы после аудита применились".
The lead's honest answer that day was: reports exist, application never verified. That is this task.

MEASURED 2026-09-04 on main `b510db3e`: 23 directories under `docs/handoff/` whose name carries
AUDIT, GUARD or CENSUS. Only 7 carry a `report.md`. The rest hold briefs, missions, or partial
notes — so "the audit was done" is itself unproven for most of them, before anyone asks whether
its findings landed.

WHY THIS MATTERS MORE THAN IT LOOKS. Two independent findings landed today, hours apart, both of
the same shape: a guard that exists and does nothing. `leadv2-codex-first-nudge.sh:113` hardcoded
`permissionDecision: allow` — structurally incapable of refusing, and its own header admitted it
while two sessions walked past it. And a second session proved that a DUPLICATE implementation of
one rule silently disarmed the negative control protecting the first: the suite went 10/10 with
one copy and 9/10 with two, because the mutation could no longer redden it. A guard's existence,
its report, and its effect are three different things.

THE WORK.

1. INVENTORY. One row per audit/census directory: does it carry a finished report, what did it
   claim, and what is its date. A directory with no report is a row that says "audit not
   finished", not a row you skip.
2. VERDICT PER FINDING, not per report. For each concrete finding: APPLIED (name the file:line in
   today's tree that implements it), NOT APPLIED (the code still has the shape the audit named),
   SUPERSEDED (the mechanism it was about no longer exists — name what replaced it), or
   UNVERIFIABLE (the finding is too vague to check — say so plainly rather than guessing).
3. Prove APPLIED by DIFFERENCE where the finding is behavioural: exhibit the guard refusing. A
   guard that cannot be shown refusing is NOT APPLIED, however good the code reads. This is the
   whole point — `permissionDecision: allow` reads like a guard.
4. Rank NOT APPLIED findings by consequence: which ones leave a live hole today.
5. FIX only the top-ranked one in this task. The inventory whole, one fix. Say which you left.

ACCEPTANCE.

1. The inventory table (23 rows) and the per-finding verdict table. Both complete; an omitted row
   is a row you must name as omitted and why.
2. For every APPLIED verdict on a behavioural finding: the command that shows the guard refusing,
   verbatim output. No output, no APPLIED.
3. For the hole you fix: a suite, plus a NEGATIVE CONTROL applied INSIDE the function body that
   reddens it, both outputs verbatim. Additionally, and this is required by today's discovery:
   state whether the rule you touched has a SECOND implementation anywhere in the tree, and if it
   does, show your negative control still reddens WITH the duplicate present. A control a
   duplicate can disarm is not a control.
4. Prove CI selects the suite with `LEADV2_RUN_ALL_SELECT_ONLY=1 tests/run-all.sh --scope changed`
   — modify the source, show the `[SELECT]` line, revert, show it gone. Both directions. Do NOT
   run a full `tests/run-all.sh` in a live checkout: a full run repointed five live control-plane
   symlinks into a temp fixture directory and deleted their targets with it, measured 2026-09-04.

CONSTRAINTS. Shared plugin tree feeding three repositories; the founder authorised work in this
tree this session. Do not touch `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh` or
`plugins/leadv2/config/leadv2-routing.yaml` — a live lane owns both. Never `git add -A`. Do not
push to origin. `tests/known-red-suites.txt` and `tests/known-failures.txt` may only shrink. Do
not "apply" a finding by adding an entry to a known-red list; that is the disease, not the cure.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-0c811596" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.

Before you finish, run your own falsification set and paste its raw output into
your final report: `bash -n` every shell file you changed, `python3 -m
py_compile` every Python file you changed, and the repo's changed-scope test
runner. Show the red output you got and the green output after your fix. A lane
whose self-check is missing or red is refused before any reviewer is spent on
it -- you will have burned the lane for nothing.

Commit your work on the lane branch before ending your session; an uncommitted
exit is treated as an incident.