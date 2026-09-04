verdict: APPROVE
next_action: deploy

Round 11: fail-closed close-gate proof is now mutation-proven; lane merge-ready at HEAD 8f87a98.

- Round-11 brief named the wrong stub (product-close.sh:91); the real choke point for the persisted terminal record is leadv2-dispatch-ledger.sh:109 (`_dl_note` shells out to it as a subprocess, never sourced).
- test-consumer-symlink-farm.sh now mutates that stub unconditionally every default run: RED (terminal=landed) -> revert -> GREEN (pass_unlanded), plus the 4 loader controls and test-dirty-lane-never-lands.sh all pass.
- Found the fix already committed at HEAD (8f87a98) mid-session (a concurrent process reached the same diagnosis); verified it independently before relying on it, then cleaned up unrelated debris left by a killed concurrent `run-all.sh --scope changed` background job.

Full: full.md
