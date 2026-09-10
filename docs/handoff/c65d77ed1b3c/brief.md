# SALVAGE-EXITS-ZERO-ON-CONFLICT-01

Wave B0. File: `plugins/leadv2/scripts/leadv2-lane-salvage.sh`.

## Defect (measured 2026-09-04)
The script prints `SALVAGE_RESULT verdict=conflict ... carried=0/4` and **exits 0**.
A loop over 17 B1 lanes reported "17 OK" while creating zero `salvage/*` branches:
the verdict lived in stdout, the caller read the exit code. This is the
"counter always answers, content answers truthfully" shape.

## Deliver
1. `verdict=conflict` -> a NON-ZERO exit code, distinct from `verdict=fail`.
   Pick two stable codes, document them in the script header, and keep
   `verdict=ok` at 0. Do not change stdout format — callers parse it.
2. Audit every caller of leadv2-lane-salvage.sh in this repo (`grep -rn lane-salvage`)
   and make sure none of them now breaks on the new non-zero — a caller that
   legitimately tolerates conflict must say so explicitly (`|| true` with a comment),
   never by accident.
3. Suite: `plugins/leadv2/scripts/tests/test-lane-salvage-exit-codes.sh`.
   It must drive the REAL salvage path against a scratch git repo with a
   genuine conflicting merge — do NOT stub the function under claim.

## Negative control (declare it in the suite header, and RUN it)
Mutation: inside the salvage function body, force the conflict branch to
`return 0`. The suite MUST go red. Insert the mutation INSIDE the function body,
not at top level — a top-level insert reddens every suite for the wrong reason
and reads as a pass. Paste the red output into
`docs/handoff/c65d77ed1b3c/round1-red.txt`.

## Done
- suite green on unmutated tree, red under the declared mutation, both outputs pasted
- exit codes documented in the script header
- no caller silently broken
