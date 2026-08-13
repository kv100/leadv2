verdict: APPROVE
next_action: continue

Resume-once lands in leadv2-dispatch-product-close.sh alone, keyed off meta.yaml `outcome:` (provider-agnostic), relaunching via the provider's own `bg` so the quota gate is inherited.

- glm-coder's internal revive is NOT externally callable — `bg` relaunch on the same worktree is the design.
- Marker written before launch; `_PC_ASKED_INTO_VOID` must be re-resolved after handle swap.
- New suite test-dwr-resume.sh; run-core-offline baseline 26 → 27.

Full: architect.full.md
