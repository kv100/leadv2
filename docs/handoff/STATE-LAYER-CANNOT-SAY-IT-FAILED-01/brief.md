# STATE-LAYER-CANNOT-SAY-IT-FAILED-01 — census: functions that write nothing and return zero

**This lane fixes nothing.** Its product is a census plus a detector suite. Fixes go out as separate
lanes afterwards, so that a repair never quietly narrows the census that justified it.

## The shape being counted

A function in the state layer takes a write, does not perform it, and returns `0`. The caller cannot
tell success from silence, so every surface downstream reports the optimistic answer. Three
instances are already known, and each was found the expensive way, at the cost of a wrong verdict:

1. **Registration.** `active_register_miss task=07401216 rc=0` — one line in forty journals; the
   pulse then reported an empty board while a lane was running.
2. **Deregistration.** `leadv2-active-registry.sh` has no CLI; the sanctioned path is to source the
   file and call `leadv2_active_unregister <id>` positionally. Invoked the obvious way it does
   nothing and says nothing.
3. **Phase records.** `leadv2-phase-record.sh:164` resolves its store from an inherited
   `LEADV2_PROJECT_ROOT`, so a lane driven from another repo's session wrote its phase records into
   **that** repo — rc=0, no output, 25 orphan `dispatch-*` directories accumulated over days across
   three sessions before anyone noticed.

## How to search — this is the whole difficulty

**Search by BEHAVIOUR, not by code text.** A grep for `return 0` inherits the blindness of the
example that suggested it: a sibling census went 2 → 4 → 6 → 7 findings over four passes because
each pass searched for the previous pass's syntax, and a fifth pass found ten more by asking what
the code *does*. The question is: *is there a path through this function on which no write happens
and the return value is still zero?* That includes

- a guard that returns early when a variable is empty (`[[ -n "$X" ]] || return 0`);
- a write to a path derived from an env var the caller never set;
- a `mkdir` / `mv` / `>` whose failure is swallowed by `2>/dev/null` or `|| true`;
- a helper invoked through a wrapper that discards its status (`… >/dev/null 2>&1 || true`);
- a loop whose body never executes because the collection was empty for a reason the function
  should have reported.

Scope: the state layer — `plugins/leadv2/scripts/lib/*.sh` plus the state-writing scripts under
`plugins/leadv2/scripts/` (registry, phase record, lane state, journal, tombstones, snapshots).

## What to deliver

1. **`docs/handoff/STATE-LAYER-CANNOT-SAY-IT-FAILED-01/census.md`** — one row per finding:
   `file:line` · function · the silent path in one sentence · what the caller sees · whether a
   caller currently depends on the zero. Rank by how far the lie travels, not by how easy the fix
   would be.
2. **A detector suite** — `plugins/leadv2/scripts/tests/test-state-layer-silent-write.sh`, with a
   `# run-all-triggers:` declaration so CI selects it (do NOT edit `tests/run-all.sh`). It must
   detect the shape, not a hardcoded list of findings: adding a new silent-write function to the
   tree makes it red without editing the suite.
3. **A backlog row per finding** via `scripts/task-add.sh` in `~/Projects/persona-engine`, each
   carrying its measurement. No fixes in this lane.

## Acceptance — it bites, deliberately

- **A census that reports "no such functions exist" must produce at least one of the three known
  instances above, found by its own method.** If your method cannot rediscover a defect that is
  already documented, then the method is what you are reporting, and the census is not evidence.
- For every row: the **measured** demonstration that the path is silent — the command, the missing
  artifact by path, and the observed `rc`. Not an argument from reading.
- Detector suite: **a negative control per changed function**, mutation inside the body, reported as
  the observed `baseline_rc` / `mutated_rc` / `restored_rc` triple. Under each mutation exactly ONE
  assertion may go red, and it must be the named one. Assert the mutant differs from the original
  byte for byte before running it.
- A control that reddens by crashing the suite or breaking the parse does not count — that proves the
  file stopped running, not that the consequence broke.
- **Ten consecutive runs**, all exit codes reported; a disagreement between runs IS the finding.

## Bounds

- **No repairs.** If a fix is one line and obvious, it still goes in the census and a backlog row,
  never in the diff. A lane that fixes as it counts always stops counting early.
- Do NOT edit `leadv2-dispatch-code.sh`, `leadv2-claude-profile-select.sh`,
  `lib/leadv2-route-arbiter.sh`, `tests/run-all.sh`, `tests/known-red-suites.txt`.
- Do NOT touch `docs/leadv2/` — shared runtime state, read by a live pulse while you work.
- Do not commit to `main`. Never `reset --hard`, `clean`, `stash`, or `worktree prune` — live lanes
  stand next to yours in a shared tree.
- Green under bash AND zsh, failing on disagreement. `declare -F` answers "defined" under zsh for a
  function that does not exist; do not build a guard on it.
- Deletion check: `git diff --diff-filter=D --name-only main...HEAD` — THREE dots.
- A file counts as saved when it appears in `git ls-files`, checked by eye.
- Your report lands in the dispatch directory of the MAIN repo. State its full path in your final
  message.

## ADDENDUM (added after dispatch, 2026-09-04) — a check on your METHOD, not an extension of scope

Do NOT widen the write set. This is a test of whether your search is bound to behaviour or to a
layer.

A fourth instance of the counted shape is already known and it lives OUTSIDE the state layer:
`leadv2-review-run.sh:1278` wraps the falsifiability gate in `[[ -f "${_FALSIFY_BIN}" ]]` with no
`else`. A missing checker means the check silently does not run and the round proceeds as if the
suite were falsifiable — write skipped, nothing said, path taken.

**Use it to grade your own method.** If a census that claims to search by behaviour finds the three
state-layer instances and would not have found this one, the method is keyed to the layer, not to
the behaviour, and that is a finding about the method which must be reported BEFORE any zero is
believed. Run your detector against that file and say plainly whether it fires.

You still do not fix it, and it does not enter your diff — it is out of your write set. Record it in
the census as an out-of-scope instance with its file:line, and file its backlog row.
