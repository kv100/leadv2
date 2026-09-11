# STATE-PATH-RESOLVER-FAILS-OPEN-UNDER-ZSH-01

Wave B0. File: `plugins/leadv2/scripts/leadv2-state-path.sh` (line ~10) and its callers.

## Defect (measured 2026-09-04)
Line 10 dereferences `BASH_SOURCE[0]`, which is UNSET under zsh. The resolver does
not fail closed — it silently falls back to the repo path. With `LEADV2_PROJECT_ROOT`
correctly set, `_leadv2_yaml_file` returned `~/Projects/leadv2/docs/leadv2/active.yaml`
instead of the live `~/.claude/leadv2-state/leadv2/active.yaml`.
`leadv2_active_unregister` then rendered an unrelated LEAD_V2_STATE.md, removed
nothing, and returned **rc=0**. The identical calls under `bash -c` resolved
correctly and removed the rows (live rows 7 -> 3, post-state asserted).

Third variant of the wrong-repo-reports-success class. The cause is NOT a missing
env var.

## Deliver
1. Root resolution must **fail closed**: when the script's own location cannot be
   determined, print a diagnostic naming which mechanism was unavailable and
   return non-zero. Never guess a path.
2. Keep bash behaviour byte-identical; the change concerns only the unset case.
3. Suite: `plugins/leadv2/scripts/tests/test-state-path-fails-closed.sh`.
   It MUST exercise the resolver with `BASH_SOURCE` unset. Probe bash libs under
   `bash -c`, never under zsh — a zsh probe false-fails for an unrelated reason
   and has misled us before.

## Negative control (declare it, and RUN it)
Mutation: restore the silent repo-path fallback inside the resolver body.
Suite MUST go red. Paste to `docs/handoff/518b42814626/round1-red.txt`.

## Off limits
Do not touch `leadv2-active-registry.sh` — another lane owns it this round.
If a registry caller must change to accommodate the fail-closed resolver, write
the finding into your report and leave the edit to that lane.

## Done
- suite green clean / red mutated, both pasted
- a resolver failure is now a non-zero with a named diagnostic, never a fallback
